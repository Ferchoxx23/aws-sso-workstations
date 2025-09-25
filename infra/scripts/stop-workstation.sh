
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${1:?profile}"; REGION="${2:?region}"; USERNAME="${3:?username}"; PROJECT="${4:-}"
FILTERS=(Name=tag:Owner,Values=${USERNAME} Name=instance-state-name,Values=running)
if [[ -n "$PROJECT" ]]; then FILTERS+=(Name=tag:Project,Values=${PROJECT}); fi
INSTANCE_IDS=$(aws ec2 describe-instances --filters "${FILTERS[@]}" --query 'Reservations[].Instances[].InstanceId' --output text --profile "$PROFILE" --region "$REGION")
if [[ -z "$INSTANCE_IDS" || "$INSTANCE_IDS" == "None" ]]; then
  echo "No running instances for Owner=$USERNAME ${PROJECT:+Project=$PROJECT}"; exit 0
fi
aws ec2 stop-instances --instance-ids $INSTANCE_IDS --profile "$PROFILE" --region "$REGION" >/dev/null
echo "Stopping: $INSTANCE_IDS"
