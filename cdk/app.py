#!/usr/bin/env python3
from aws_cdk import App, Environment, Stack
from constructs import Construct


class WorkstationBaseline(Stack):
    def __init__(self, scope: Construct, cid: str, **kwargs):
        super().__init__(scope, cid, **kwargs)

        # Use existing resources created by bootstrap script instead of CDK
        # All infrastructure is created via ./infra/scripts/bootstrap-iam-for-ssm.sh
        pass


app = App()
WorkstationBaseline(
    app, "WorkstationBaseline", env=Environment(account="058264484340", region="us-east-1")
)
app.synth()
