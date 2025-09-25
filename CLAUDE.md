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
# Login with SSO (once per shell session)
aws sso login --profile <sso-profile>

# Bootstrap IAM resources for SSM
./infra/scripts/bootstrap-iam-for-ssm.sh <sso-profile> <region>
```

### Workstation Management
```bash
# Create workstation
./infra/scripts/create-workstation.sh --profile <sso-profile> --region <region> --username <username> --project <project> --instance-type t3.small --arch x86_64 --volume-gb 50

# Start session
./infra/scripts/start-session.sh <sso-profile> <region> <instance-id>

# Stop workstation
./infra/scripts/stop-workstation.sh <sso-profile> <region> <username> [project]
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
# Deploy baseline infrastructure
cd cdk/
pip install -r requirements.txt
cdk deploy --profile <sso-profile>
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

## Development Guidelines

- All custom code should be Python or Bash
- Infrastructure defined in AWS CDK (Python)
- Follow existing script patterns for argument parsing and error handling
- Use AWS CLI with SSO profiles consistently
- Tag all AWS resources with Owner and Project for ABAC compliance

## Security Notes

- No SSH keys or inbound ports required
- All access via Session Manager over HTTPS
- ABAC ensures users can only access their own resources
- S3 bucket policies enforce per-user prefixes via principal tags