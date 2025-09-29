#!/usr/bin/env bash
# Helper for bi-directional sync with S3 user prefix
set -euo pipefail

# Source common utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-utils.sh"

ACTION="${1:?Usage: $0 <push|pull> <bucket> <prefix> [username] [path] [profile] [region]}"
BUCKET="${2:?bucket}"
PREFIX="${3:?prefix}"
USERNAME="${4:-}"
PATH_LOCAL="${5:-$HOME/workspace}"
PROFILE="${6:-sub-dev-dev}"
REGION="${7:-us-east-1}"

# Auto-detect username if not provided
if [[ -z "$USERNAME" ]]; then
  echo "Auto-detecting username from current AWS SSO session..."
  USERNAME=$(get_current_username "$PROFILE" "$REGION")
  echo "Detected username: $USERNAME"
fi
S3URI="s3://${BUCKET}/${PREFIX}/${USERNAME}/"
case "$ACTION" in
  push) aws s3 sync "$PATH_LOCAL" "$S3URI" --delete ;;
  pull) aws s3 sync "$S3URI" "$PATH_LOCAL" ;;
  *) echo "Unknown action: $ACTION"; exit 1;;
 esac
