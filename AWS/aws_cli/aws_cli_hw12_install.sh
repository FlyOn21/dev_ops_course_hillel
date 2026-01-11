#!/bin/sh

#  ./aws_cli_hw12_install.sh ~/.ssh/zhoholiev.pub 94.131.197.224 flyon21
set -e

# Configuration
VPC_NAME="Flyon21VPC"
VPC_CIDR="192.168.0.0/16"
PUBLIC_SUBNET_CIDR="192.168.0.0/24"
PRIVATE_SUBNET_CIDR="192.168.1.0/24"
KEY_PAIR_NAME="Flyon21-KeyPair"
PUBLIC_INSTANCE_PRIVATE_IP="192.168.0.4"
PRIVATE_INSTANCE_PRIVATE_IP="192.168.1.4"

#arguments
SSH_PUBLIC_KEY_FILE="$1"
ALLOWED_SSH_IP="$2"
AWS_PROFILE="${3:-flyon21}"

# Get AWS region
AWS_REGION=$(aws configure get region --profile $AWS_PROFILE)
if [ -z "$AWS_REGION" ]; then
  echo "Error: AWS region not configured for profile: $AWS_PROFILE"
  exit 1
fi


AVAILABILITY_ZONE="${AWS_REGION}a"

echo "=========================================="
echo "AWS Infrastructure Creation Script"
echo "=========================================="
echo "AWS Profile: $AWS_PROFILE"
echo "Region: $AWS_REGION"
echo "Availability Zone: $AVAILABILITY_ZONE"
echo "=========================================="

# Function to get resource ID from output
get_value() {
  echo "$1" | grep -oP '"\w+": "\K[^"]+' | head -1
}

#################VPC CREATION######################
echo "[1/15] Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
  --profile $AWS_PROFILE \
  --query 'Vpc.VpcId' \
  --output text)
echo "VPC ID: $VPC_ID"

## Enable DNS hostnames
#aws ec2 modify-vpc-attribute \
#  --vpc-id $VPC_ID \
#  --enable-dns-hostnames \
#  --profile $AWS_PROFILE

#################SUBNETS######################
echo "[2/15] Creating Public Subnet..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_CIDR \
  --availability-zone $AVAILABILITY_ZONE \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Flyon21-Public-Subnet}]" \
  --profile $AWS_PROFILE \
  --query 'Subnet.SubnetId' \
  --output text)
echo "Public Subnet ID: $PUBLIC_SUBNET_ID"


aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_ID \
  --map-public-ip-on-launch \
  --profile $AWS_PROFILE

echo "[3/15] Creating Private Subnet..."
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_CIDR \
  --availability-zone $AVAILABILITY_ZONE \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Flyon21-Private-Subnet}]" \
  --profile $AWS_PROFILE \
  --query 'Subnet.SubnetId' \
  --output text)
echo "Private Subnet ID: $PRIVATE_SUBNET_ID"

#################INTERNET GATEWAY######################
echo "[4/15] Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=Flyon21-IGW}]" \
  --profile $AWS_PROFILE \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
echo "Internet Gateway ID: $IGW_ID"

echo "[5/15] Attaching Internet Gateway to VPC..."
aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --profile $AWS_PROFILE

#################NAT GATEWAY######################
echo "[6/15] Allocating Elastic IP for NAT Gateway..."
NAT_EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=Flyon21-NAT-EIP}]" \
  --profile $AWS_PROFILE \
  --query 'AllocationId' \
  --output text)
echo "NAT Gateway EIP Allocation ID: $NAT_EIP_ALLOCATION_ID"

echo "[7/15] Creating NAT Gateway..."
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_ID \
  --allocation-id $NAT_EIP_ALLOCATION_ID \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=Flyon21-NAT}]" \
  --profile $AWS_PROFILE \
  --query 'NatGateway.NatGatewayId' \
  --output text)
echo "NAT Gateway ID: $NAT_GATEWAY_ID"

# Wait for NAT Gateway to be available
echo "Waiting for NAT Gateway to be available..."
aws ec2 wait nat-gateway-available \
  --nat-gateway-ids $NAT_GATEWAY_ID \
  --profile $AWS_PROFILE

#################ROUTE TABLES######################
echo "[8/15] Creating Public Route Table..."
PUBLIC_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Flyon21-Public-RT}]" \
  --profile $AWS_PROFILE \
  --query 'RouteTable.RouteTableId' \
  --output text)
echo "Public Route Table ID: $PUBLIC_RT_ID"

echo "[9/15] Adding route to Internet Gateway..."
aws ec2 create-route \
  --route-table-id $PUBLIC_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --profile $AWS_PROFILE

echo "[10/15] Associating Public Subnet with Public Route Table..."
aws ec2 associate-route-table \
  --subnet-id $PUBLIC_SUBNET_ID \
  --route-table-id $PUBLIC_RT_ID \
  --profile $AWS_PROFILE

echo "[11/15] Creating Private Route Table..."
PRIVATE_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Flyon21-Private-RT}]" \
  --profile $AWS_PROFILE \
  --query 'RouteTable.RouteTableId' \
  --output text)
echo "Private Route Table ID: $PRIVATE_RT_ID"

echo "[12/15] Adding route to NAT Gateway..."
aws ec2 create-route \
  --route-table-id $PRIVATE_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GATEWAY_ID \
  --profile $AWS_PROFILE

echo "[13/15] Associating Private Subnet with Private Route Table..."
aws ec2 associate-route-table \
  --subnet-id $PRIVATE_SUBNET_ID \
  --route-table-id $PRIVATE_RT_ID \
  --profile $AWS_PROFILE

#################SSH KEY PAIR######################
echo "[14/15] Creating SSH Key Pair..."
if [ -n "$SSH_PUBLIC_KEY_FILE" ] && [ -f "$SSH_PUBLIC_KEY_FILE" ]; then
  echo "Using provided SSH PUBLIC key from: $SSH_PUBLIC_KEY_FILE"

  if ! grep -q "ssh-rsa\|ssh-ed25519\|ecdsa-sha2" "$SSH_PUBLIC_KEY_FILE"; then
    echo "ERROR: The file doesn't appear to be a valid SSH public key."
    echo "Expected format: ssh-rsa AAAAB3... or ssh-ed25519 AAAAC3..."
    echo "You provided a public key file (.pub), not a private key (.pem)"
    echo "Example: ~/.ssh/id_rsa.pub or ~/.ssh/zhoholiev.pub"
    exit 1
  fi

  aws ec2 import-key-pair \
    --key-name $KEY_PAIR_NAME \
    --public-key-material fileb://$SSH_PUBLIC_KEY_FILE \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$KEY_PAIR_NAME}]" \
    --profile $AWS_PROFILE

  echo "✓ SSH public key imported successfully"
  echo "Note: Use your existing private key (corresponding to this public key) to connect to instances"
else
  echo "No public key file provided - creating NEW key pair"
  echo "A new private key will be generated and saved to ${KEY_PAIR_NAME}.pem"

  aws ec2 create-key-pair \
    --key-name $KEY_PAIR_NAME \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$KEY_PAIR_NAME}]" \
    --profile $AWS_PROFILE \
    --query 'KeyMaterial' \
    --output text > ${KEY_PAIR_NAME}.pem
  chmod 400 ${KEY_PAIR_NAME}.pem

  echo "✓ New private key saved to ${KEY_PAIR_NAME}.pem"
  echo "IMPORTANT: Keep this file safe - you cannot download it again!"
fi

#################SECURITY GROUPS######################
echo "[15/15] Creating Security Groups..."

# Public Security Group
PUBLIC_SG_ID=$(aws ec2 create-security-group \
  --group-name Flyon21-Public-SG \
  --description "Security group for public EC2 instance (Bastion) - allows SSH from your IP only" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=Flyon21-Public-SG}]" \
  --profile $AWS_PROFILE \
  --query 'GroupId' \
  --output text)
echo "Public Security Group ID: $PUBLIC_SG_ID"

if [ -n "$ALLOWED_SSH_IP" ]; then
  echo "Adding SSH ingress rule for IP: $ALLOWED_SSH_IP"
  aws ec2 authorize-security-group-ingress \
    --group-id $PUBLIC_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr ${ALLOWED_SSH_IP}/32 \
    --profile $AWS_PROFILE
else
  echo "WARNING: Adding SSH ingress rule from anywhere (0.0.0.0/0) - !!!CHANGE THIS!!!"
  aws ec2 authorize-security-group-ingress \
    --group-id $PUBLIC_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --profile $AWS_PROFILE
fi

# Private Security Group
PRIVATE_SG_ID=$(aws ec2 create-security-group \
  --group-name Flyon21-Private-SG \
  --description "Security group for private EC2 instance - allows SSH from public subnet only" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=Flyon21-Private-SG}]" \
  --profile $AWS_PROFILE \
  --query 'GroupId' \
  --output text)
echo "Private Security Group ID: $PRIVATE_SG_ID"

aws ec2 authorize-security-group-ingress \
  --group-id $PRIVATE_SG_ID \
  --protocol tcp \
  --port 22 \
  --source-group $PUBLIC_SG_ID \
  --profile $AWS_PROFILE

#################EC2 INSTANCES######################
echo "Getting latest Amazon Linux 2 AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2" \
  "Name=state,Values=available" \
  --profile $AWS_PROFILE \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)
echo "AMI ID: $AMI_ID"

echo "Creating Public EC2 Instance..."
PUBLIC_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --key-name $KEY_PAIR_NAME \
  --security-group-ids $PUBLIC_SG_ID \
  --subnet-id $PUBLIC_SUBNET_ID \
  --private-ip-address $PUBLIC_INSTANCE_PRIVATE_IP \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Flyon21-Public-Instance}]" \
  --profile $AWS_PROFILE \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "Public Instance ID: $PUBLIC_INSTANCE_ID"

# Wait for public instance to be running
echo "Waiting for public instance to be running..."
aws ec2 wait instance-running \
  --instance-ids $PUBLIC_INSTANCE_ID \
  --profile $AWS_PROFILE

echo "Allocating Elastic IP for Public Instance..."
PUBLIC_INSTANCE_EIP=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=Flyon21-Public-Instance-EIP}]" \
  --profile $AWS_PROFILE \
  --query 'AllocationId' \
  --output text)
echo "Public Instance EIP Allocation ID: $PUBLIC_INSTANCE_EIP"

echo "Associating Elastic IP with Public Instance..."
aws ec2 associate-address \
  --instance-id $PUBLIC_INSTANCE_ID \
  --allocation-id $PUBLIC_INSTANCE_EIP \
  --profile $AWS_PROFILE

# Get the actual public IP
PUBLIC_IP=$(aws ec2 describe-addresses \
  --allocation-ids $PUBLIC_INSTANCE_EIP \
  --profile $AWS_PROFILE \
  --query 'Addresses[0].PublicIp' \
  --output text)

echo "Creating Private EC2 Instance..."
PRIVATE_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --key-name $KEY_PAIR_NAME \
  --security-group-ids $PRIVATE_SG_ID \
  --subnet-id $PRIVATE_SUBNET_ID \
  --private-ip-address $PRIVATE_INSTANCE_PRIVATE_IP \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Flyon21-Private-Instance}]" \
  --profile $AWS_PROFILE \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "Private Instance ID: $PRIVATE_INSTANCE_ID"

# Wait for private instance to be running
echo "Waiting for private instance to be running..."
aws ec2 wait instance-running \
  --instance-ids $PRIVATE_INSTANCE_ID \
  --profile $AWS_PROFILE

#################OUTPUTS######################
echo ""
echo "=========================================="
echo "Infrastructure Created Successfully!"
echo "=========================================="
echo ""
echo "VPC:"
echo "  VPC ID: $VPC_ID"
echo "  VPC CIDR: $VPC_CIDR"
echo ""
echo "Subnets:"
echo "  Public Subnet ID: $PUBLIC_SUBNET_ID ($PUBLIC_SUBNET_CIDR)"
echo "  Private Subnet ID: $PRIVATE_SUBNET_ID ($PRIVATE_SUBNET_CIDR)"
echo ""
echo "Gateways:"
echo "  Internet Gateway ID: $IGW_ID"
echo "  NAT Gateway ID: $NAT_GATEWAY_ID"
echo ""
echo "Route Tables:"
echo "  Public Route Table ID: $PUBLIC_RT_ID"
echo "  Private Route Table ID: $PRIVATE_RT_ID"
echo ""
echo "Security Groups:"
echo "  Public Security Group ID: $PUBLIC_SG_ID"
echo "  Private Security Group ID: $PRIVATE_SG_ID"
echo ""
echo "Key Pair:"
echo "  Key Pair Name: $KEY_PAIR_NAME"
echo ""
echo "EC2 Instances:"
echo "  Public Instance ID: $PUBLIC_INSTANCE_ID"
echo "  Public Instance Private IP: $PUBLIC_INSTANCE_PRIVATE_IP"
echo "  Public Instance Public IP (EIP): $PUBLIC_IP"
echo ""
echo "  Private Instance ID: $PRIVATE_INSTANCE_ID"
echo "  Private Instance Private IP: $PRIVATE_INSTANCE_PRIVATE_IP"
echo ""
echo "=========================================="
echo "Connection Instructions:"
echo "=========================================="
echo ""

if [ -n "$SSH_PUBLIC_KEY_FILE" ]; then
  PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_FILE%.pub}"
  echo "Using YOUR existing private key: $PRIVATE_KEY_PATH"
  echo "(This corresponds to the public key you provided: $SSH_PUBLIC_KEY_FILE)"
  echo ""
  echo "To connect to the public instance (bastion):"
  echo "  ssh -i $PRIVATE_KEY_PATH ec2-user@$PUBLIC_IP"
  echo ""
  echo "To connect to the private instance (via bastion):"
  echo "  ssh -i $PRIVATE_KEY_PATH -o ProxyCommand=\"ssh -i $PRIVATE_KEY_PATH -W %h:%p ec2-user@$PUBLIC_IP\" ec2-user@$PRIVATE_INSTANCE_PRIVATE_IP"
else
  echo "To connect to the public instance (bastion):"
  echo "  ssh -i /path/to/your/private-key ec2-user@$PUBLIC_IP"
  echo ""
  echo "To connect to the private instance (via bastion):"
  echo "  ssh -i /path/to/your/private-key -o ProxyCommand=\"ssh -i /path/to/your/private-key -W %h:%p ec2-user@$PUBLIC_IP\" ec2-user@$PRIVATE_INSTANCE_PRIVATE_IP"
fi
echo ""
echo "=========================================="
