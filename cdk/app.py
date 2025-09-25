
#!/usr/bin/env python3
import os
from aws_cdk import (
    App, Stack, aws_ec2 as ec2, aws_iam as iam
)
from constructs import Construct

class WorkstationBaseline(Stack):
    def __init__(self, scope: Construct, cid: str, **kwargs):
        super().__init__(scope, cid, **kwargs)

        # Security Group: no inbound, all egress
        vpc = ec2.Vpc.from_lookup(self, 'DefaultVPC', is_default=True)
        sg = ec2.SecurityGroup(self, 'WsSg', vpc=vpc, allow_all_outbound=True, description='Egress only for SSM')

        # Instance Role for SSM
        role = iam.Role(self, 'SsmRole', assumed_by=iam.ServicePrincipal('ec2.amazonaws.com'))
        role.add_managed_policy(iam.ManagedPolicy.from_aws_managed_policy_name('AmazonSSMManagedInstanceCore'))

        iam.CfnInstanceProfile(self, 'WsInstanceProfile', roles=[role.role_name])

        # (Optional) Interface endpoints for SSM when you move to private subnets
        # ec2.InterfaceVpcEndpoint(self, 'SsmEp', vpc=vpc, service=ec2.InterfaceVpcEndpointAwsService.SSM)
        # ec2.InterfaceVpcEndpoint(self, 'SsmMsgEp', vpc=vpc, service=ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES)
        # ec2.InterfaceVpcEndpoint(self, 'Ec2MsgEp', vpc=vpc, service=ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES)
        # ec2.GatewayVpcEndpoint(self, 'S3Ep', vpc=vpc, service=ec2.GatewayVpcEndpointAwsService.S3)

app = App()
WorkstationBaseline(app, 'WorkstationBaseline')
app.synth()
