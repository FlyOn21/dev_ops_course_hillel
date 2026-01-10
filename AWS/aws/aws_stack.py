from aws_cdk import (
    Stack,
    aws_ec2 as ec2, CfnOutput,
)
from constructs import Construct

class EC2Stack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        #################VPC CREATION######################
        # Create VPC without default subnets
        vpc = ec2.Vpc(
            self,
            "VPCFlyon21HW12",
            vpc_name="Flyon21VPC",
            ip_addresses=ec2.IpAddresses.cidr("192.168.0.0/16"),
            max_azs=1,
            nat_gateways=0,  # We'll create manually
            subnet_configuration=[]  # No default subnets
        )

        # Create Internet Gateway
        internet_gateway = ec2.CfnInternetGateway(
            self,
            "InternetGatewayFlyon21HW12",
            tags=[{"key": "name", "value": "Flyon21-IGW"}]
        )

        # Attach Internet Gateway to VPC
        ec2.CfnVPCGatewayAttachment(
            self,
            "IGWAttachmentFlyon21HW12",
            vpc_id=vpc.vpc_id,
            internet_gateway_id=internet_gateway.ref
        )

        # Create Public Subnet
        public_subnet = ec2.Subnet(
            self,
            "PublicSubnetFlyon21HW12",
            availability_zone=f"{self.region}a",
            vpc_id=vpc.vpc_id,
            cidr_block="192.168.0.0/24",
            map_public_ip_on_launch=True
        )

        # Create Private Subnet
        private_subnet = ec2.Subnet(
            self,
            "PrivateSubnetFlyon21HW12",
            availability_zone=f"{self.region}a",
            vpc_id=vpc.vpc_id,
            cidr_block="192.168.1.0/24"
        )

        # Create Elastic IP for NAT Gateway
        elastic_ip = ec2.CfnEIP(
            self,
            "NATGatewayEIPFlyon21HW12",
            domain="vpc",
            tags=[{"key": "name", "value": "Flyon21-NAT-EIP"}]
        )

        # Create NAT Gateway in Public Subnet
        nat_gateway = ec2.CfnNatGateway(
            self,
            "NATGatewayFlyon21HW12",
            subnet_id=public_subnet.subnet_id,
            allocation_id=elastic_ip.attr_allocation_id,
            tags=[{"key": "name", "value": "Flyon21-NAT"}]
        )

        # Create Route Table for Public Subnet
        public_route_table = ec2.CfnRouteTable(
            self,
            "PublicRouteTableFlyon21HW12",
            vpc_id=vpc.vpc_id,
            tags=[{"key": "name", "value": "Flyon21-Public-RT"}]
        )

        # Add route to Internet Gateway in Public Route Table
        ec2.CfnRoute(
            self,
            "PublicRouteFlyon21HW12",
            route_table_id=public_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=internet_gateway.ref
        )

        # Associate Public Subnet with Public Route Table
        ec2.CfnSubnetRouteTableAssociation(
            self,
            "PublicSubnetRTAssociationFlyon21HW12",
            subnet_id=public_subnet.subnet_id,
            route_table_id=public_route_table.ref
        )

        # Create Route Table for Private Subnet
        private_route_table = ec2.CfnRouteTable(
            self,
            "PrivateRouteTableFlyon21HW12",
            vpc_id=vpc.vpc_id,
            tags=[{"key": "name", "value": "Flyon21-Private-RT"}]
        )

        # Add route to NAT Gateway in Private Route Table
        ec2.CfnRoute(
            self,
            "PrivateRouteFlyon21HW12",
            route_table_id=private_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            nat_gateway_id=nat_gateway.ref
        )

        # Associate Private Subnet with Private Route Table
        ec2.CfnSubnetRouteTableAssociation(
            self,
            "PrivateSubnetRTAssociationFlyon21HW12",
            subnet_id=private_subnet.subnet_id,
            route_table_id=private_route_table.ref
        )

        #################OUTPUTS######################
        CfnOutput(
            self,
            "VPCIdOutput",
            value=vpc.vpc_id,
            description="The ID of the VPC",
            export_name="VPCIdFlyon21HW12"
        )
        CfnOutput(
            self,
            "PublicSubnetIdOutput",
            value=public_subnet.subnet_id,
            description="The ID of the Public Subnet",
            export_name="PublicSubnetIdFlyon21HW12"
        )
        CfnOutput(
            self,
            "PrivateSubnetIdOutput",
            value=private_subnet.subnet_id,
            description="The ID of the Private Subnet",
            export_name="PrivateSubnetIdFlyon21HW12"
        )
        CfnOutput(
            self,
            "InternetGatewayIdOutput",
            value=internet_gateway.ref,
            description="The ID of the Internet Gateway",
            export_name="InternetGatewayIdFlyon21HW12"
        )
        CfnOutput(
            self,
            "NATGatewayIdOutput",
            value=nat_gateway.ref,
            description="The ID of the NAT Gateway",
            export_name="NATGatewayIdFlyon21HW12"
        )
