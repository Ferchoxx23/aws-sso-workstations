#!/usr/bin/env bash
set -euo pipefail

# Source common utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-utils.sh"

PROFILE="${1:?profile}"
REGION="${2:?region}"
USERNAME="${3:-}"
PROJECT="${4:-}"

# Auto-detect username if not provided
if [[ -z "$USERNAME" ]]; then
  echo "Auto-detecting username from current AWS SSO session..."
  USERNAME=$(get_current_username "$PROFILE" "$REGION")
  echo "Detected username: $USERNAME"
fi
FILTERS=(Name=tag:Owner,Values=${USERNAME} Name=instance-state-name,Values=running)
if [[ -n "$PROJECT" ]]; then FILTERS+=(Name=tag:Project,Values=${PROJECT}); fi
INSTANCE_IDS=$(aws ec2 describe-instances --filters "${FILTERS[@]}" --query 'Reservations[].Instances[].InstanceId' --output text --profile "$PROFILE" --region "$REGION")
if [[ -z "$INSTANCE_IDS" || "$INSTANCE_IDS" == "None" ]]; then
  echo "No running instances for Owner=$USERNAME ${PROJECT:+Project=$PROJECT}"; exit 0
fi
aws ec2 stop-instances --instance-ids $INSTANCE_IDS --profile "$PROFILE" --region "$REGION" >/dev/null
echo "Stopping: $INSTANCE_IDS"
