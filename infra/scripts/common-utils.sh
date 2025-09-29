#!/usr/bin/env bash

# Shared utility functions for workstation management scripts

# Extract the current AWS user's username from their SSO session
# This matches the principal tag used in ABAC policies
get_current_username() {
    local profile="${1:?profile required}"
    local region="${2:?region required}"

    # Extract username from the ARN's session name (last part after /)
    aws sts get-caller-identity \
        --profile "$profile" \
        --region "$region" \
        --query 'Arn' \
        --output text | \
        sed 's|.*/||'
}

# Validate that the provided username matches the current AWS identity
# This helps catch mismatches that would cause ABAC failures
validate_username() {
    local provided_username="${1:?username required}"
    local profile="${2:?profile required}"
    local region="${3:?region required}"

    local current_username
    current_username=$(get_current_username "$profile" "$region")

    if [[ "$provided_username" != "$current_username" ]]; then
        echo "WARNING: Provided username '$provided_username' does not match current AWS identity '$current_username'" >&2
        echo "This will likely cause ABAC permission failures. Consider using auto-detected username." >&2
        return 1
    fi

    return 0
}