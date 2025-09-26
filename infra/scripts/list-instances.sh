#!/bin/bash

# Output file
echo -e "instance_id\tstate\tzone\tinstance_type\ttags"
instances=$(aws ec2 describe-instances)
# Use jq to parse and format the output
echo "$instances" | jq -r '
    .Reservations[].Instances[] |
    {
        id: .InstanceId,
        state: .State.Name,
        type: .InstanceType,
        AvailabilityZone: .Placement.AvailabilityZone,
        tags: (if .Tags then (.Tags | map("\(.Key)=\(.Value)") | join(", ")) else "" end)
    } |
    "\(.id)\t\(.state)\t\(.AvailabilityZone)\t\(.type)\t\(.tags)"
'
