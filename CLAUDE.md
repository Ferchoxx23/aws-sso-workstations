# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS SSO-based EC2 workstation provisioning system that allows team members to securely create and manage personal EC2 instances accessed via AWS Systems Manager Session Manager (no SSH required).

## Core Architecture

- **SSO Authentication**: Users authenticate via AWS IAM Identity Center with short-lived credentials
- **ABAC Security**: Attribute-based access control using `username` principal tags; instances tagged with `Owner=<username>`
- **Session Manager Access**: Zero inbound ports - all access via AWS SSM over HTTPS (port 443 outbound only)
- **S3 Workspace Sync**: Per-user S3 prefixes for workspace synchronization (`s3://<bucket>/<prefix>/<username>/`)

## Common Commands

### Initial Setup (one-time)
```bash
# Install CDK CLI
npm install -g aws-cdk

# Login with admin SSO profile for bootstrapping
aws sso login --profile sub-dev-admin

# Create default VPC if none exists
aws ec2 create-default-vpc --profile sub-dev-admin

# Bootstrap IAM resources for SSM
./infra/scripts/bootstrap-iam-for-ssm.sh sub-dev-admin us-east-1

# Bootstrap CDK toolkit (optional)
cd cdk/
uv sync
uv run cdk bootstrap --profile sub-dev-admin
```

### Daily Workstation Management
```bash
# Login with developer profile
aws sso login --profile sub-dev-dev

# Create workstation (specify subnet for better instance type support)
./infra/scripts/create-workstation.sh \
  --profile sub-dev-dev --region us-east-1 \
  --username <username> --project <project> \
  --instance-type t3.small --arch x86_64 --volume-gb 50 \
  --subnet-id subnet-042e2fa6a0489e19b

# Start session
aws ssm start-session --target <instance-id> --profile sub-dev-dev --region us-east-1

# Stop workstation
./infra/scripts/stop-workstation.sh sub-dev-dev us-east-1 <username> [project]
```

### S3 Workspace Sync
```bash
# Upload workspace to S3 (from EC2)
./infra/scripts/s3-sync.sh push <bucket> <prefix> <username> [local-path]

# Download workspace from S3 (to EC2)
./infra/scripts/s3-sync.sh pull <bucket> <prefix> <username> [local-path]
```

### CDK Infrastructure
```bash
# Deploy baseline infrastructure (optional - permission boundaries may prevent deployment)
cd cdk/
uv sync
uv run cdk deploy --profile sub-dev-admin --require-approval never

# Note: The system works without CDK deployment - IAM resources are created by bootstrap script
```

## File Structure

```
infra/
  scripts/           # Shell scripts for workstation lifecycle
  policies/          # IAM permission set policies for ABAC
cdk/                 # AWS CDK Python infrastructure code
aws-config-git/      # AWS CLI configuration management
```

## Key Implementation Details

- **Instance Tags**: All instances must have `Owner=<username>`, `Project=<project>`, `Name=<project>-<username>`
- **Security**: IMDSv2 required, no inbound security group rules, SSM instance profile mandatory
- **ABAC Policy**: Users can only manage instances where `Owner` tag matches their `${aws:PrincipalTag/username}`
- **AMI Selection**: Automatic latest Amazon Linux 2023 AMI selection via SSM Parameter Store
- **Default Resources**: Uses default VPC/subnets but creates dedicated security group
- **Dual Profiles**: Admin profile (`sub-dev-admin`) for bootstrapping, developer profile (`sub-dev-dev`) for daily use
- **Permission Boundaries**: Account has permission boundaries that may prevent CDK deployments; bootstrap script provides alternative

## Development Guidelines

- All custom code should be Python or Bash
- Infrastructure defined in AWS CDK (Python)
- Follow existing script patterns for argument parsing and error handling
- Use AWS CLI with SSO profiles consistently
- Tag all AWS resources with Owner and Project for ABAC compliance
- Use ruff for Python code linting and formatting
- Use uv for Python dependency management

## Security Notes

- No SSH keys or inbound ports required
- All access via Session Manager over HTTPS
- ABAC ensures users can only access their own resources
- S3 bucket policies enforce per-user prefixes via principal tags