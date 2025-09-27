#!/usr/bin/env bash
set -euo pipefail
INSTANCE_TYPE="t3.small"
ARCH="x86_64"
VOLUME_GB="50"
INSTANCE_PROFILE="EC2-SSM-InstanceProfile"
SUBNET_ID=""
SG_ID=""
PROJECT=""
USERNAME=""
PROFILE=""
REGION=""
CUSTOM_AMI_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-type) INSTANCE_TYPE="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    --volume-gb) VOLUME_GB="$2"; shift 2;;
    --instance-profile) INSTANCE_PROFILE="$2"; shift 2;;
    --subnet-id) SUBNET_ID="$2"; shift 2;;
    --sg-id) SG_ID="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --username) USERNAME="$2"; shift 2;;
    --profile) PROFILE="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --ami-id) CUSTOM_AMI_ID="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [[ -z "$PROFILE" || -z "$REGION" || -z "$USERNAME" || -z "$PROJECT" ]]; then
  echo "Usage: $0 --profile <sso-profile> --region <region> --username <owner> --project <project> [options]"
  exit 2
fi

if [[ -n "$CUSTOM_AMI_ID" ]]; then
  AMI_ID="$CUSTOM_AMI_ID"
  echo "Using custom AMI: $AMI_ID"
else
  if [[ "$ARCH" == "arm64" ]]; then
    AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-arm64"
  else
    AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  fi
  AMI_ID=$(aws ssm get-parameters --names "$AMI_PARAM" --query 'Parameters[0].Value' --output text --profile "$PROFILE" --region "$REGION")
  echo "Using latest AL2023 AMI: $AMI_ID"
fi

if [[ -z "$SG_ID" ]]; then
  VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text --profile "$PROFILE" --region "$REGION")
  if [[ "$VPC_ID" == "None" ]]; then
    echo "No default VPC found. Provide --subnet-id and --sg-id explicitly."; exit 3
  fi
  SG_NAME="workstation-ssm-egress-only"
  SG_ID=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text --profile "$PROFILE" --region "$REGION")
  if [[ "$SG_ID" == "None" ]]; then
    SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" --description "No inbound; all egress for SSM" --vpc-id "$VPC_ID" --query 'GroupId' --output text --profile "$PROFILE" --region "$REGION")
    aws ec2 authorize-security-group-egress --group-id "$SG_ID" --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0,Description="All out"}]' --profile "$PROFILE" --region "$REGION" >/dev/null
  fi
fi

if [[ -z "$SUBNET_ID" ]]; then
  SUBNET_ID=$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text --profile "$PROFILE" --region "$REGION")
  if [[ "$SUBNET_ID" == "None" ]]; then
    echo "No default subnet found. Provide --subnet-id explicitly."; exit 4
  fi
fi

NAME_TAG="${PROJECT}-${USERNAME}"

INSTANCE_ID=$(aws ec2 run-instances   --image-id "$AMI_ID"   --instance-type "$INSTANCE_TYPE"   --iam-instance-profile Name="$INSTANCE_PROFILE"   --subnet-id "$SUBNET_ID"   --security-group-ids "$SG_ID"   --associate-public-ip-address   --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$VOLUME_GB,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]"   --metadata-options "HttpTokens=required,HttpEndpoint=enabled"   --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG},{Key=Owner,Value=$USERNAME},{Key=Project,Value=$PROJECT}]"                         "ResourceType=volume,Tags=[{Key=Owner,Value=$USERNAME},{Key=Project,Value=$PROJECT}]"   --query 'Instances[0].InstanceId' --output text --profile "$PROFILE" --region "$REGION")

echo "Launched: $INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --profile "$PROFILE" --region "$REGION"
echo "Instance running. Waiting for SSM registration..."
for i in {1..30}; do
  MI=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" --query 'InstanceInformationList[0].InstanceId' --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null || true)
  if [[ "$MI" != "None" && -n "$MI" ]]; then
    echo "SSM managing: $MI"; break
  fi
  sleep 10
done

echo "Start a session: aws ssm start-session --target $INSTANCE_ID --profile $PROFILE --region $REGION"
