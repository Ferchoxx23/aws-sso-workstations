from aws_cdk import (
    CfnOutput,
    Stack,
)
from aws_cdk import (
    aws_ec2 as ec2,
)
from aws_cdk import (
    aws_iam as iam,
)
from aws_cdk import (
    aws_imagebuilder as imagebuilder,
)
from constructs import Construct


class ImageBuilderStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs):
        super().__init__(scope, construct_id, **kwargs)

        # Instance profile for Image Builder builds
        role = iam.Role(
            self,
            "ImageBuilderInstanceRole",
            role_name="EC2ImageBuilderInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("EC2InstanceProfileForImageBuilder"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        instance_profile = iam.CfnInstanceProfile(
            self,
            "ImageBuilderInstanceProfile",
            instance_profile_name="EC2ImageBuilderInstanceProfile",
            roles=[role.role_name],
        )

        # Component for workstation development tools
        component = imagebuilder.CfnComponent(
            self,
            "WorkstationDevToolsComponent",
            name="workstation-dev-tools",
            platform="Linux",
            version="1.0.0",
            description="Install essential development tools on Amazon Linux 2023",
            data=self._get_component_data(),
        )

        # Image recipe combining AL2023 base with dev tools
        recipe = imagebuilder.CfnImageRecipe(
            self,
            "WorkstationImageRecipe",
            name="amazon-linux-workstation",
            version="1.0.0",
            parent_image="{{ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64}}",
            description="Amazon Linux 2023 workstation with development tools",
            components=[
                imagebuilder.CfnImageRecipe.ComponentConfigurationProperty(
                    component_arn=component.attr_arn
                )
            ],
            block_device_mappings=[
                imagebuilder.CfnImageRecipe.InstanceBlockDeviceMappingProperty(
                    device_name="/dev/xvda",
                    ebs=imagebuilder.CfnImageRecipe.EbsInstanceBlockDeviceSpecificationProperty(
                        volume_size=30,
                        volume_type="gp3",
                        encrypted=True,
                        delete_on_termination=True,
                    ),
                )
            ],
        )

        # Look up default VPC and get first available subnet
        default_vpc = ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)

        # Create security group allowing outbound access for builds
        security_group = ec2.SecurityGroup(
            self,
            "ImageBuilderSecurityGroup",
            vpc=default_vpc,
            description="Security group for Image Builder instances",
            security_group_name="imagebuilder-sg",
        )
        security_group.add_egress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.all_traffic(),
            "Allow all outbound traffic for package downloads",
        )

        # Infrastructure configuration
        infra_config = imagebuilder.CfnInfrastructureConfiguration(
            self,
            "WorkstationInfrastructureConfiguration",
            name="workstation-infra-config",
            instance_types=["t3.medium"],
            instance_profile_name=instance_profile.instance_profile_name,
            security_group_ids=[security_group.security_group_id],
            subnet_id=default_vpc.public_subnets[0].subnet_id,
            description="Infrastructure configuration for workstation AMI builds",
        )

        # Distribution configuration
        dist_config = imagebuilder.CfnDistributionConfiguration(
            self,
            "WorkstationDistributionConfiguration",
            name="workstation-distribution",
            description="Distribution configuration for workstation AMIs",
            distributions=[
                imagebuilder.CfnDistributionConfiguration.DistributionProperty(
                    region=self.region,
                    ami_distribution_configuration=imagebuilder.CfnDistributionConfiguration.AmiDistributionConfigurationProperty(
                        name="AL2023-Workstation-{{imagebuilder:buildDate}}",
                        description="Custom Amazon Linux 2023 workstation AMI",
                        ami_tags={"Name": "AL2023-Workstation", "Source": "ImageBuilder"},
                    ),
                )
            ],
        )

        # Image pipeline with weekly schedule
        pipeline = imagebuilder.CfnImagePipeline(
            self,
            "WorkstationImagePipeline",
            name="workstation-pipeline",
            description="Automated pipeline for workstation AMI builds",
            image_recipe_arn=recipe.attr_arn,
            infrastructure_configuration_arn=infra_config.attr_arn,
            distribution_configuration_arn=dist_config.attr_arn,
            schedule=imagebuilder.CfnImagePipeline.ScheduleProperty(
                schedule_expression="cron(0 9 ? * SUN *)",  # Weekly Sunday 09:00 UTC
                pipeline_execution_start_condition="EXPRESSION_MATCH_ONLY",
                timezone="Etc/UTC",
            ),
            image_tests_configuration=imagebuilder.CfnImagePipeline.ImageTestsConfigurationProperty(
                image_tests_enabled=True,
                timeout_minutes=90,
            ),
        )

        # Add dependencies
        recipe.add_dependency(component)
        infra_config.add_dependency(instance_profile)
        dist_config.add_dependency(recipe)
        pipeline.add_dependency(infra_config)
        pipeline.add_dependency(dist_config)

        # Outputs
        CfnOutput(
            self, "PipelineArn", value=pipeline.attr_arn, description="Image Builder Pipeline ARN"
        )
        CfnOutput(
            self, "ComponentArn", value=component.attr_arn, description="Dev Tools Component ARN"
        )
        CfnOutput(self, "RecipeArn", value=recipe.attr_arn, description="Image Recipe ARN")

    def _get_component_data(self) -> str:
        """Load component data from existing YAML file"""
        import pathlib

        # Get the component file path relative to this CDK directory
        cdk_dir = pathlib.Path(__file__).parent
        component_file = (
            cdk_dir.parent / "infra" / "image-builder" / "components" / "workstation-dev-tools.yml"
        )

        if not component_file.exists():
            raise FileNotFoundError(f"Component file not found: {component_file}")

        return component_file.read_text()
