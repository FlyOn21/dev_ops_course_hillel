#!/bin/sh

set -e  # Exit on error

# Configuration
VPC_NAME="Flyon21VPC"
KEY_PAIR_NAME="Flyon21-KeyPair"
AWS_PROFILE="${1:-flyon21}"

echo "=========================================="
echo "AWS Infrastructure Cleanup Script"
echo "=========================================="
echo "AWS Profile: $AWS_PROFILE"
echo "WARNING: This will delete all Flyon21 infrastructure!"
echo "=========================================="
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo ""
echo "Starting cleanup..."

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=$VPC_NAME" \
  --profile $AWS_PROFILE \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo "VPC not found. Nothing to clean up."
  exit 0
fi

echo "Found VPC: $VPC_ID"

#################TERMINATE EC2 INSTANCES######################
echo "[1/12] Terminating EC2 Instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped,stopping" \
  --profile $AWS_PROFILE \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [ -n "$INSTANCE_IDS" ]; then
  echo "Terminating instances: $INSTANCE_IDS"
  aws ec2 terminate-instances \
    --instance-ids $INSTANCE_IDS \
    --profile $AWS_PROFILE
  echo "Waiting for instances to terminate..."
  aws ec2 wait instance-terminated \
    --instance-ids $INSTANCE_IDS \
    --profile $AWS_PROFILE
  echo "Instances terminated."
else
  echo "No instances to terminate."
fi

#################RELEASE ELASTIC IPs######################
echo "[2/12] Releasing Elastic IPs..."
EIP_ALLOCATION_IDS=$(aws ec2 describe-addresses \
  --filters "Name=domain,Values=vpc" \
  --profile $AWS_PROFILE \
  --query "Addresses[?Tags[?Key=='Name' && contains(Value, 'Flyon21')]].AllocationId" \
  --output text)

if [ -n "$EIP_ALLOCATION_IDS" ]; then
  for ALLOCATION_ID in $EIP_ALLOCATION_IDS; do
    echo "Releasing EIP: $ALLOCATION_ID"
    aws ec2 release-address \
      --allocation-id $ALLOCATION_ID \
      --profile $AWS_PROFILE || echo "Failed to release $ALLOCATION_ID (may already be released)"
  done
else
  echo "No Elastic IPs to release."
fi

#################DELETE NAT GATEWAYS######################
echo "[3/12] Deleting NAT Gateways..."
NAT_GATEWAY_IDS=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
  --profile $AWS_PROFILE \
  --query 'NatGateways[].NatGatewayId' \
  --output text)

if [ -n "$NAT_GATEWAY_IDS" ]; then
  for NAT_GW_ID in $NAT_GATEWAY_IDS; do
    echo "Deleting NAT Gateway: $NAT_GW_ID"
    aws ec2 delete-nat-gateway \
      --nat-gateway-id $NAT_GW_ID \
      --profile $AWS_PROFILE
  done
  echo "Waiting for NAT Gateways to be deleted..."
  for NAT_GW_ID in $NAT_GATEWAY_IDS; do
    aws ec2 wait nat-gateway-deleted \
      --nat-gateway-ids $NAT_GW_ID \
      --profile $AWS_PROFILE || echo "NAT Gateway $NAT_GW_ID deletion wait timeout (continuing anyway)"
  done
else
  echo "No NAT Gateways to delete."
fi

#################DELETE ROUTE TABLE ASSOCIATIONS AND ROUTES######################
echo "[4/12] Deleting Route Table Associations..."
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --profile $AWS_PROFILE \
  --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
  --output text)

if [ -n "$ROUTE_TABLE_IDS" ]; then
  for RT_ID in $ROUTE_TABLE_IDS; do
    ASSOCIATION_IDS=$(aws ec2 describe-route-tables \
      --route-table-ids $RT_ID \
      --profile $AWS_PROFILE \
      --query 'RouteTables[].Associations[?!Main].RouteTableAssociationId' \
      --output text)

    if [ -n "$ASSOCIATION_IDS" ]; then
      for ASSOC_ID in $ASSOCIATION_IDS; do
        echo "Disassociating route table association: $ASSOC_ID"
        aws ec2 disassociate-route-table \
          --association-id $ASSOC_ID \
          --profile $AWS_PROFILE
      done
    fi
  done
else
  echo "No route table associations to delete."
fi

#################DETACH AND DELETE INTERNET GATEWAY######################
echo "[5/12] Detaching and Deleting Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --profile $AWS_PROFILE \
  --query 'InternetGateways[0].InternetGatewayId' \
  --output text)

if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
  echo "Detaching Internet Gateway: $IGW_ID"
  aws ec2 detach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --profile $AWS_PROFILE
  echo "Deleting Internet Gateway: $IGW_ID"
  aws ec2 delete-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --profile $AWS_PROFILE
else
  echo "No Internet Gateway to delete."
fi

#################DELETE ROUTE TABLES######################
echo "[6/12] Deleting Route Tables..."
if [ -n "$ROUTE_TABLE_IDS" ]; then
  for RT_ID in $ROUTE_TABLE_IDS; do
    echo "Deleting Route Table: $RT_ID"
    aws ec2 delete-route-table \
      --route-table-id $RT_ID \
      --profile $AWS_PROFILE
  done
else
  echo "No route tables to delete."
fi

#################DELETE SECURITY GROUPS######################
echo "[7/12] Deleting Security Groups..."
SG_IDS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --profile $AWS_PROFILE \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text)

if [ -n "$SG_IDS" ]; then
  # Wait a bit to ensure all instances are fully terminated
  sleep 10

  for SG_ID in $SG_IDS; do
    echo "Deleting Security Group: $SG_ID"
    aws ec2 delete-security-group \
      --group-id $SG_ID \
      --profile $AWS_PROFILE || echo "Failed to delete $SG_ID (may have dependencies, will retry)"
  done

  # Retry once more for security groups that might have had dependencies
  sleep 5
  for SG_ID in $SG_IDS; do
    aws ec2 delete-security-group \
      --group-id $SG_ID \
      --profile $AWS_PROFILE 2>/dev/null || echo "Security group $SG_ID already deleted or still has dependencies"
  done
else
  echo "No security groups to delete."
fi

#################DELETE SUBNETS######################
echo "[8/12] Deleting Subnets..."
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --profile $AWS_PROFILE \
  --query 'Subnets[].SubnetId' \
  --output text)

if [ -n "$SUBNET_IDS" ]; then
  for SUBNET_ID in $SUBNET_IDS; do
    echo "Deleting Subnet: $SUBNET_ID"
    aws ec2 delete-subnet \
      --subnet-id $SUBNET_ID \
      --profile $AWS_PROFILE
  done
else
  echo "No subnets to delete."
fi

#################DELETE VPC######################
echo "[9/12] Deleting VPC..."
aws ec2 delete-vpc \
  --vpc-id $VPC_ID \
  --profile $AWS_PROFILE
echo "VPC deleted: $VPC_ID"

#################DELETE KEY PAIR######################
echo "[10/12] Deleting Key Pair..."
aws ec2 delete-key-pair \
  --key-name $KEY_PAIR_NAME \
  --profile $AWS_PROFILE 2>/dev/null && echo "Key pair deleted: $KEY_PAIR_NAME" || echo "Key pair not found or already deleted"

#################DELETE LOCAL KEY FILE######################
echo "[11/12] Cleaning up local key file..."
if [ -f "${KEY_PAIR_NAME}.pem" ]; then
  rm -f ${KEY_PAIR_NAME}.pem
  echo "Local key file deleted: ${KEY_PAIR_NAME}.pem"
else
  echo "No local key file found."
fi

echo "[12/12] Cleanup complete!"
echo ""
echo "=========================================="
echo "All Flyon21 infrastructure has been deleted."
echo "=========================================="
