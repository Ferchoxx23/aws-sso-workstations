from aws_cdk import Stack
from constructs import Construct


class WorkstationBaseline(Stack):
    def __init__(self, scope: Construct, cid: str, **kwargs):
        super().__init__(scope, cid, **kwargs)

        # Use existing resources created by bootstrap script instead of CDK
        # All infrastructure is created via ./infra/scripts/bootstrap-iam-for-ssm.sh
        pass
