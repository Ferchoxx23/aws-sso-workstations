
#!/usr/bin/env bash
# Creates an IAM role & instance profile for EC2 to use SSM.
set -euo pipefail
PROFILE="${1:?Usage: $0 <profile> <region> [role-name] [instance-profile]}"
REGION="${2:?Usage: $0 <profile> <region> [role-name] [instance-profile]}"
ROLE_NAME="${3:-EC2-SSM-Role}"
INSTANCE_PROFILE_NAME="${4:-EC2-SSM-InstanceProfile}"

TMP=$(mktemp)
cat > "$TMP" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect":"Allow",
    "Principal":{"Service":"ec2.amazonaws.com"},
    "Action":"sts:AssumeRole"
  }]
}
JSON

aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null 2>&1 || aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://"$TMP" --profile "$PROFILE" >/dev/null

aws iam attach-role-policy --role-name "$ROLE_NAME"   --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore   --profile "$PROFILE" >/dev/null || true

aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --profile "$PROFILE" >/dev/null 2>&1 || aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --profile "$PROFILE" >/dev/null

aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME"   --role-name "$ROLE_NAME" --profile "$PROFILE" >/dev/null || true

echo "Instance profile ready: $INSTANCE_PROFILE_NAME (role: $ROLE_NAME)"
