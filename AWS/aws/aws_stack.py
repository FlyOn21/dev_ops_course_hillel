from aws_cdk import (
    Stack,
    aws_ec2 as ec2, CfnOutput,
)
from constructs import Construct

class EC2Stack(Stack):

    def __init__(self, scope: Construct, construct_id: str, ssh_public_key: str = None,
                 allowed_ssh_ip: str = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        #################VPC CREATION######################
        # Create VPC
        vpc = ec2.Vpc(
            self,
            "VPCFlyon21HW12",
            vpc_name="Flyon21VPC",
            ip_addresses=ec2.IpAddresses.cidr("192.168.0.0/16"),
            max_azs=1,
            create_internet_gateway=False,
            nat_gateways=0,
            subnet_configuration=[]
        )

        #Public Subnet
        public_subnet = ec2.Subnet(
            self,
            "PublicSubnetFlyon21HW12",
            availability_zone=f"{self.region}a",
            vpc_id=vpc.vpc_id,
            cidr_block="192.168.0.0/24",
            map_public_ip_on_launch=True
        )

        #Private Subnet
        private_subnet = ec2.Subnet(
            self,
            "PrivateSubnetFlyon21HW12",
            availability_zone=f"{self.region}a",
            vpc_id=vpc.vpc_id,
            cidr_block="192.168.1.0/24"
        )

        # Create IGW
        internet_gateway = ec2.CfnInternetGateway(
            self,
            "InternetGatewayFlyon21HW12",
            tags=[{"key": "name", "value": "Flyon21-IGW"}]
        )

        # Attach IGW to VPC
        igw_attachment = ec2.CfnVPCGatewayAttachment(
            self,
            "IGWAttachmentFlyon21HW12",
            vpc_id=vpc.vpc_id,
            internet_gateway_id=internet_gateway.ref
        )
        igw_attachment.add_dependency(internet_gateway)

        # Create ElasticIP for NAT
        elastic_ip = ec2.CfnEIP(
            self,
            "NATGatewayEIPFlyon21HW12",
            domain="vpc",
            tags=[{"key": "name", "value": "Flyon21-NAT-EIP"}]
        )

        # Create NAT in Public Subnet
        nat_gateway = ec2.CfnNatGateway(
            self,
            "NATGatewayFlyon21HW12",
            subnet_id=public_subnet.subnet_id,
            allocation_id=elastic_ip.attr_allocation_id,
            tags=[{"key": "name", "value": "Flyon21-NAT"}]
        )
        nat_gateway.add_dependency(elastic_ip)

        #Route Table for Public Subnet
        public_route_table = ec2.CfnRouteTable(
            self,
            "PublicRouteTableFlyon21HW12",
            vpc_id=vpc.vpc_id,
            tags=[{"key": "name", "value": "Flyon21-Public-RT"}]
        )

        # Add route to IGW in Public Route Table
        public_route = ec2.CfnRoute(
            self,
            "PublicRouteFlyon21HW12",
            route_table_id=public_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            gateway_id=internet_gateway.ref
        )
        public_route.add_dependency(igw_attachment)
        public_route.add_dependency(public_route_table)

        # Associate Public Subnet with Public Route Table
        assosiate_publick_subnet = ec2.CfnSubnetRouteTableAssociation(
            self,
            "PublicSubnetRTAssociationFlyon21HW12",
            subnet_id=public_subnet.subnet_id,
            route_table_id=public_route_table.ref
        )
        assosiate_publick_subnet.add_dependency(public_route_table)

        # Create Route Table for Private Subnet
        private_route_table = ec2.CfnRouteTable(
            self,
            "PrivateRouteTableFlyon21HW12",
            vpc_id=vpc.vpc_id,
            tags=[{"key": "name", "value": "Flyon21-Private-RT"}]
        )

        # Add route to NAT in Private Route Table
        private_route= ec2.CfnRoute(
            self,
            "PrivateRouteFlyon21HW12",
            route_table_id=private_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            nat_gateway_id=nat_gateway.ref
        )
        private_route.add_dependency(nat_gateway)

        # Associate Private Subnet with Private Route Table
        assosiate_private = ec2.CfnSubnetRouteTableAssociation(
            self,
            "PrivateSubnetRTAssociationFlyon21HW12",
            subnet_id=private_subnet.subnet_id,
            route_table_id=private_route_table.ref
        )
        assosiate_private.add_dependency(private_route_table)

        #################SSH KEY PAIR######################
        key_pair_kwargs = {
            "key_pair_name": "Flyon21-KeyPair"
        }

        if ssh_public_key:
            key_pair_kwargs["public_key_material"] = ssh_public_key

        key_pair = ec2.KeyPair(
            self,
            "EC2KeyPairFlyon21HW12",
            **key_pair_kwargs
        )

        #################SECURITY GROUPS######################
        # Security Group for Public EC2
        public_security_group = ec2.SecurityGroup(
            self,
            "PublicSecurityGroupFlyon21HW12",
            vpc=vpc,
            security_group_name="Flyon21-Public-SG",
            description="Security group for public EC2 instance (Bastion) - allows SSH from your IP only",
            allow_all_outbound=True
        )

        # Add SSH ingress rule
        if allowed_ssh_ip:
            public_security_group.add_ingress_rule(
                peer=ec2.Peer.ipv4(f"{allowed_ssh_ip}/32"),
                connection=ec2.Port.tcp(22),
                description=f"Allow SSH from your IP: {allowed_ssh_ip}"
            )
        else:
            public_security_group.add_ingress_rule(
                peer=ec2.Peer.any_ipv4(),
                connection=ec2.Port.tcp(22),
                description="Allow SSH from anywhere. !!!CHANGE THIS!!!"
            )

        # Security Group for Private EC2
        private_security_group = ec2.SecurityGroup(
            self,
            "PrivateSecurityGroupFlyon21HW12",
            vpc=vpc,
            security_group_name="Flyon21-Private-SG",
            description="Security group for private EC2 instance - allows SSH from public subnet only",
            allow_all_outbound=True #outbound traffic
        )

        # Add SSH ingress rule from Public SG
        private_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(public_security_group.security_group_id),
            connection=ec2.Port.tcp(22),
            description="Allow SSH from bastion host security group"
        )

        #################EC2 INSTANCES######################
        #Latest Amazon Linux AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            kernel=ec2.AmazonLinux2Kernel.KERNEL_5_10,
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
            cpu_type=ec2.AmazonLinuxCpuType.X86_64 # or ARM_64
        )

        #EC2 Instance in Public Subnet
        public_instance = ec2.Instance(
            self,
            "PublicEC2InstanceFlyon21HW12",
            instance_type=ec2.InstanceType("t2.micro"),
            machine_image=amzn_linux,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[public_subnet]),
            security_group=public_security_group,
            key_pair=key_pair,
            instance_name="Flyon21-Public-Instance",
            private_ip_address="192.168.0.4"
        )

        #ElasticIP for Public Instance for SSH
        public_eip = ec2.CfnEIP(
            self,
            "PublicInstanceEIPFlyon21HW12",
            domain="vpc",
            instance_id=public_instance.instance_id,
            tags=[{"key": "name", "value": "Flyon21-Public-Instance-EIP"}]
        )

        #EC2 Instance in Private Subnet
        private_instance = ec2.Instance(
            self,
            "PrivateEC2InstanceFlyon21HW12",
            instance_type=ec2.InstanceType("t2.micro"),
            machine_image=amzn_linux,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[private_subnet]),
            security_group=private_security_group,
            key_pair=key_pair,
            instance_name="Flyon21-Private-Instance",
            private_ip_address="192.168.1.4"
        )

        #################OUTPUTS######################
        # Output VPC ID
        CfnOutput(
            self,
            "VPCIdOutput",
            value=vpc.vpc_id,
            description="The ID of the VPC",
            export_name="VPCIdFlyon21HW12"
        )

        # Output Public Subnet ID
        CfnOutput(
            self,
            "PublicSubnetIdOutput",
            value=public_subnet.subnet_id,
            description="The ID of the Public Subnet",
            export_name="PublicSubnetIdFlyon21HW12"
        )

        # Output Private Subnet ID
        CfnOutput(
            self,
            "PrivateSubnetIdOutput",
            value=private_subnet.subnet_id,
            description="The ID of the Private Subnet",
            export_name="PrivateSubnetIdFlyon21HW12"
        )

        # Output Internet Gateway ID
        CfnOutput(
            self,
            "InternetGatewayIdOutput",
            value=internet_gateway.ref,
            description="The ID of the Internet Gateway",
            export_name="InternetGatewayIdFlyon21HW12"
        )

        # Output NAT Gateway ID
        CfnOutput(
            self,
            "NATGatewayIdOutput",
            value=nat_gateway.ref,
            description="The ID of the NAT Gateway",
            export_name="NATGatewayIdFlyon21HW12"
        )

        # Output Key Pair Name
        CfnOutput(
            self,
            "KeyPairNameOutput",
            value=key_pair.key_pair_name,
            description="The name of the SSH Key Pair",
            export_name="KeyPairNameFlyon21HW12"
        )

        # Output Public EC2 Instance ID
        CfnOutput(
            self,
            "PublicInstanceIdOutput",
            value=public_instance.instance_id,
            description="The ID of the Public EC2 Instance",
            export_name="PublicInstanceIdFlyon21HW12"
        )

        # Output Public EC2 Instance Private IP
        CfnOutput(
            self,
            "PublicInstancePrivateIpOutput",
            value=public_instance.instance_private_ip,
            description="The Private IP of the Public EC2 Instance",
            export_name="PublicInstancePrivateIpFlyon21HW12"
        )

        # Output Public EC2 Instance Public IP (EIP - Stable)
        CfnOutput(
            self,
            "PublicInstancePublicIpOutput",
            value=public_eip.ref,
            description="The Public IP (EIP) of the Public EC2 Instance - stable, doesn't change on restart",
            export_name="PublicInstancePublicIpFlyon21HW12"
        )

        # Output Private EC2 Instance ID
        CfnOutput(
            self,
            "PrivateInstanceIdOutput",
            value=private_instance.instance_id,
            description="The ID of the Private EC2 Instance",
            export_name="PrivateInstanceIdFlyon21HW12"
        )

        # Output Private EC2 Instance Private IP
        CfnOutput(
            self,
            "PrivateInstancePrivateIpOutput",
            value=private_instance.instance_private_ip,
            description="The Private IP of the Private EC2 Instance",
            export_name="PrivateInstancePrivateIpFlyon21HW12"
        )

        # Output Security Group IDs
        CfnOutput(
            self,
            "PublicSecurityGroupIdOutput",
            value=public_security_group.security_group_id,
            description="The ID of the Public Security Group",
            export_name="PublicSecurityGroupIdFlyon21HW12"
        )
        CfnOutput(
            self,
            "PrivateSecurityGroupIdOutput",
            value=private_security_group.security_group_id,
            description="The ID of the Private Security Group",
            export_name="PrivateSecurityGroupIdFlyon21HW12"
        )