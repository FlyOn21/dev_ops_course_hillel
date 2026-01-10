#!/usr/bin/env python3
import os

import aws_cdk as cdk

from aws.aws_stack import EC2Stack

with open(os.path.expanduser("~/.ssh/zhoholiev.pub"), "r") as f:
    ssh_public_key = f.read().strip()

app = cdk.App()
stack = EC2Stack(
    app,
    "EC2StackHomeWork12",
    env=cdk.Environment(region="eu-central-1"),
    ssh_public_key=ssh_public_key,
    allowed_ssh_ip="94.131.197.224"
)
cdk.Tags.of(stack).add("dev_ops", "hw12")
cdk.Tags.of(stack).add("owner", "flyon21")
cdk.Tags.of(stack).add("project", "ec2_cdk_project")

app.synth()
