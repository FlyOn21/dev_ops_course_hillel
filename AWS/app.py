#!/usr/bin/env python3
import os

import aws_cdk as cdk

from aws.aws_stack import EC2Stack


app = cdk.App()
stack = EC2Stack(app, "EC2Stack", env =cdk.Environment(region="eu-central-1"))
cdk.Tags.of(stack).add("dev_ops", "hw12")
cdk.Tags.of(stack).add("owner", "flyon21")

app.synth()
