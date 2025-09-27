#!/usr/bin/env bash
set -euo pipefail

# EC2 Image Builder AMI Creation Script
# Creates custom Amazon Linux 2023 workstation AMIs with dev tools

# Configuration
REGION="${REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-sub-dev-dev}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
COMPONENT_NAME="${COMPONENT_NAME:-workstation-dev-tools}"
RECIPE_NAME="${RECIPE_NAME:-amazon-linux-workstation}"
PIPELINE_NAME="${PIPELINE_NAME:-workstation-pipeline}"
INFRA_NAME="${INFRA_NAME:-workstation-infra-config}"
DIST_NAME="${DIST_NAME:-workstation-distribution}"
AMI_NAME_PATTERN="${AMI_NAME_PATTERN:-AL2023-Workstation-{{imagebuilder:buildDate}}}"
PARENT_SSM="${PARENT_SSM:-ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64}"

# Required IAM resources
PROFILE_NAME="EC2ImageBuilderInstanceProfile"
ROLE_NAME="EC2ImageBuilderInstanceRole"

AWS="aws --region ${REGION} --profile ${PROFILE}"

# Get script directory for component file
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
COMP_FILE="${SCRIPT_DIR}/../components/workstation-dev-tools.yml"

# Usage function
usage() {
    cat <<EOF
Usage: $0 [options]

Creates an EC2 Image Builder pipeline for custom Amazon Linux 2023 workstation AMIs.

Options:
    -s, --subnet-id SUBNET     Subnet ID for build instances (required)
    -g, --security-group SG    Security group ID for build instances (required)
    -r, --region REGION        AWS region (default: us-east-1)
    -p, --profile PROFILE      AWS profile (default: sub-dev-dev)
    -t, --instance-type TYPE   Instance type for builds (default: t3.medium)
    -n, --pipeline-name NAME   Pipeline name (default: workstation-pipeline)
    --start-build              Start a build immediately after setup
    --schedule CRON            Schedule expression (default: weekly Sunday 09:00 UTC)
    -h, --help                 Show this help

Examples:
    # Create pipeline with default VPC subnet and security group
    $0 --subnet-id subnet-042e2fa6a0489e19b --security-group sg-0123456789abcdef0

    # Create and start immediate build
    $0 -s subnet-042e2fa6a0489e19b -g sg-0123456789abcdef0 --start-build

Required AWS permissions:
    - imagebuilder:*
    - iam:CreateRole, iam:AttachRolePolicy, iam:CreateInstanceProfile
    - ec2:DescribeSubnets, ec2:DescribeSecurityGroups
EOF
}

# Parse arguments
SUBNET_ID=""
SG_ID=""
START_BUILD=false
SCHEDULE_CRON="cron(0 9 ? * SUN *)"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        -g|--security-group)
            SG_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            AWS="aws --region ${REGION} --profile ${PROFILE}"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            AWS="aws --region ${REGION} --profile ${PROFILE}"
            shift 2
            ;;
        -t|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -n|--pipeline-name)
            PIPELINE_NAME="$2"
            shift 2
            ;;
        --start-build)
            START_BUILD=true
            shift
            ;;
        --schedule)
            SCHEDULE_CRON="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "${SUBNET_ID}" ]]; then
    echo "Error: --subnet-id is required" >&2
    usage >&2
    exit 1
fi

if [[ -z "${SG_ID}" ]]; then
    echo "Error: --security-group is required" >&2
    usage >&2
    exit 1
fi

# Validate component file exists
if [[ ! -f "${COMP_FILE}" ]]; then
    echo "Error: Component file not found at ${COMP_FILE}" >&2
    exit 1
fi

# Preflight checks
command -v aws >/dev/null || { echo "Error: aws CLI not found"; exit 1; }

echo "Creating EC2 Image Builder pipeline..."
echo "  Region: ${REGION}"
echo "  Profile: ${PROFILE}"
echo "  Subnet: ${SUBNET_ID}"
echo "  Security Group: ${SG_ID}"
echo "  Pipeline: ${PIPELINE_NAME}"
echo

# Create IAM role and instance profile if needed
echo "==> Setting up IAM resources..."
if ! ${AWS} iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
    cat > /tmp/trust-ec2.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
    ${AWS} iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/trust-ec2.json >/dev/null
    ${AWS} iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder
    ${AWS} iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    echo "Created IAM role: ${ROLE_NAME}"
    rm -f /tmp/trust-ec2.json
else
    echo "IAM role exists: ${ROLE_NAME}"
fi

if ! ${AWS} iam get-instance-profile --instance-profile-name "${PROFILE_NAME}" >/dev/null 2>&1; then
    ${AWS} iam create-instance-profile --instance-profile-name "${PROFILE_NAME}" >/dev/null
    sleep 3  # Allow time for profile creation
    ${AWS} iam add-role-to-instance-profile \
        --instance-profile-name "${PROFILE_NAME}" \
        --role-name "${ROLE_NAME}" || true
    echo "Created instance profile: ${PROFILE_NAME}"
else
    echo "Instance profile exists: ${PROFILE_NAME}"
fi

# Create or update component
echo "==> Creating Image Builder component..."
COMP_ARN="$(${AWS} imagebuilder list-components --owner Self \
    --query "components[?name=='${COMPONENT_NAME}']|[0].arn" --output text 2>/dev/null || true)"

if [[ -z "${COMP_ARN}" || "${COMP_ARN}" == "None" ]]; then
    COMP_ARN="$(${AWS} imagebuilder create-component \
        --name "${COMPONENT_NAME}" \
        --semantic-version 1.0.0 \
        --platform Linux \
        --data "file://${COMP_FILE}" \
        --description "Workstation development tools for Amazon Linux 2023" \
        --query 'componentBuildVersionArn' --output text)"
    echo "Created component: ${COMPONENT_NAME}"
else
    echo "Component exists: ${COMPONENT_NAME}"
fi
echo "Component ARN: ${COMP_ARN}"

# Create image recipe
echo "==> Creating image recipe..."
RECIPE_ARN="$(${AWS} imagebuilder list-image-recipes \
    --query "imageRecipeSummaryList[?name=='${RECIPE_NAME}']|[0].arn" --output text 2>/dev/null || true)"

if [[ -z "${RECIPE_ARN}" || "${RECIPE_ARN}" == "None" ]]; then
    RECIPE_ARN="$(${AWS} imagebuilder create-image-recipe \
        --name "${RECIPE_NAME}" \
        --semantic-version 1.0.0 \
        --parent-image "${PARENT_SSM}" \
        --components "[{\"componentArn\":\"${COMP_ARN}\"}]" \
        --description "Amazon Linux 2023 workstation with development tools" \
        --block-device-mappings '[{"deviceName":"/dev/xvda","ebs":{"volumeSize":30,"volumeType":"gp3","encrypted":true,"deleteOnTermination":true}}]' \
        --query 'imageRecipeArn' --output text)"
    echo "Created recipe: ${RECIPE_NAME}"
else
    echo "Recipe exists: ${RECIPE_NAME}"
fi
echo "Recipe ARN: ${RECIPE_ARN}"

# Create infrastructure configuration
echo "==> Creating infrastructure configuration..."
INFRA_ARN="$(${AWS} imagebuilder list-infrastructure-configurations \
    --query "infrastructureConfigurationSummaryList[?name=='${INFRA_NAME}']|[0].arn" --output text 2>/dev/null || true)"

if [[ -z "${INFRA_ARN}" || "${INFRA_ARN}" == "None" ]]; then
    INFRA_ARN="$(${AWS} imagebuilder create-infrastructure-configuration \
        --name "${INFRA_NAME}" \
        --instance-types "${INSTANCE_TYPE}" \
        --instance-profile "${PROFILE_NAME}" \
        --security-group-ids "${SG_ID}" \
        --subnet-id "${SUBNET_ID}" \
        --description "Infrastructure configuration for workstation AMI builds" \
        --query 'infrastructureConfigurationArn' --output text)"
    echo "Created infrastructure config: ${INFRA_NAME}"
else
    echo "Infrastructure config exists: ${INFRA_NAME}"
fi
echo "Infrastructure ARN: ${INFRA_ARN}"

# Create distribution configuration
echo "==> Creating distribution configuration..."
DIST_ARN="$(${AWS} imagebuilder list-distribution-configurations \
    --query "distributionConfigurationSummaryList[?name=='${DIST_NAME}']|[0].arn" --output text 2>/dev/null || true)"

if [[ -z "${DIST_ARN}" || "${DIST_ARN}" == "None" ]]; then
    DIST_ARN="$(${AWS} imagebuilder create-distribution-configuration \
        --name "${DIST_NAME}" \
        --description "Distribution configuration for workstation AMIs" \
        --distributions "[{\"region\":\"${REGION}\",\"amiDistributionConfiguration\":{\"name\":\"${AMI_NAME_PATTERN}\",\"description\":\"Custom Amazon Linux 2023 workstation AMI\",\"launchPermission\":{\"userIds\":[]}}}]" \
        --query 'distributionConfigurationArn' --output text)"
    echo "Created distribution config: ${DIST_NAME}"
else
    echo "Distribution config exists: ${DIST_NAME}"
fi
echo "Distribution ARN: ${DIST_ARN}"

# Create image pipeline
echo "==> Creating image pipeline..."
PIPELINE_ARN="$(${AWS} imagebuilder list-image-pipelines \
    --query "imagePipelineList[?name=='${PIPELINE_NAME}']|[0].arn" --output text 2>/dev/null || true)"

if [[ -z "${PIPELINE_ARN}" || "${PIPELINE_ARN}" == "None" ]]; then
    PIPELINE_ARN="$(${AWS} imagebuilder create-image-pipeline \
        --name "${PIPELINE_NAME}" \
        --description "Automated pipeline for workstation AMI builds" \
        --image-recipe-arn "${RECIPE_ARN}" \
        --infrastructure-configuration-arn "${INFRA_ARN}" \
        --distribution-configuration-arn "${DIST_ARN}" \
        --schedule "{\"scheduleExpression\":\"${SCHEDULE_CRON}\",\"pipelineExecutionStartCondition\":\"EXPRESSION_MATCH_ONLY\",\"timezone\":\"Etc/UTC\"}" \
        --query 'imagePipelineArn' --output text)"
    echo "Created pipeline: ${PIPELINE_NAME}"
else
    echo "Pipeline exists: ${PIPELINE_NAME}"
fi
echo "Pipeline ARN: ${PIPELINE_ARN}"

# Start build if requested
if [[ "${START_BUILD}" == "true" ]]; then
    echo "==> Starting image build..."
    BUILD_ARN="$(${AWS} imagebuilder start-image-pipeline-execution \
        --image-pipeline-arn "${PIPELINE_ARN}" \
        --query 'imageBuildVersionArn' --output text)"
    echo "Build started: ${BUILD_ARN}"
    echo
    echo "Monitor build progress:"
    echo "  ${AWS} imagebuilder get-image --image-build-version-arn \"${BUILD_ARN}\" --query 'image.state'"
fi

echo
echo "✓ Pipeline setup complete!"
echo
echo "Useful commands:"
echo "  # List builds"
echo "  ${AWS} imagebuilder list-image-builds --query 'imageBuildVersionList[?starts_with(arn, \`${PIPELINE_ARN}\`)]'"
echo
echo "  # Start manual build"
echo "  ${AWS} imagebuilder start-image-pipeline-execution --image-pipeline-arn \"${PIPELINE_ARN}\""
echo
echo "  # List created AMIs"
echo "  ${AWS} ec2 describe-images --owners self --filters 'Name=name,Values=AL2023-Workstation-*'"