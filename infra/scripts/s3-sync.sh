#!/usr/bin/env bash
# Helper for bi-directional sync with S3 user prefix
set -euo pipefail
ACTION="${1:?Usage: $0 <push|pull> <bucket> <prefix> <username> [path]}"
BUCKET="${2:?bucket}"; PREFIX="${3:?prefix}"; USERNAME="${4:?username}"; PATH_LOCAL="${5:-$HOME/workspace}"
S3URI="s3://${BUCKET}/${PREFIX}/${USERNAME}/"
case "$ACTION" in
  push) aws s3 sync "$PATH_LOCAL" "$S3URI" --delete ;;
  pull) aws s3 sync "$S3URI" "$PATH_LOCAL" ;;
  *) echo "Unknown action: $ACTION"; exit 1;;
 esac
