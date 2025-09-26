#!/usr/bin/env python3
from aws_cdk import App, Environment, Stack
from aws_cdk import aws_ec2 as ec2
from constructs import Construct


class WorkstationBaseline(Stack):
    def __init__(self, scope: Construct, cid: str, **kwargs):
        super().__init__(scope, cid, **kwargs)

        # Security Group: no inbound, all egress
        # vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
        # sg = ec2.SecurityGroup(
        #     self, "WsSg", vpc=vpc, allow_all_outbound=True, description="Egress only for SSM"
        # )

        # Use existing resources created by bootstrap script instead of CDK
        pass


app = App()
WorkstationBaseline(
    app, "WorkstationBaseline", env=Environment(account="058264484340", region="us-east-1")
)
app.synth()
