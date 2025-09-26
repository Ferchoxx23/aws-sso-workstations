#!/usr/bin/env bash
set -euo pipefail
PROFILE="${1:?profile}"; REGION="${2:?region}"; INSTANCE_ID="${3:?instance-id}"
aws ssm start-session --target "$INSTANCE_ID" --profile "$PROFILE" --region "$REGION"
