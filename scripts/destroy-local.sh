#!/bin/bash
# Local destruction script for ALZ-v3
# Deletes all resources created by the deployment

set -e

ENV="${1:-prod}"
LOCATION="${2:-eastus}"

echo "=========================================="
echo "ALZ-v3 Destruction Script"
echo "=========================================="
echo "Environment: $ENV"
echo "Location: $LOCATION"
echo "=========================================="

# Confirmation
read -p "Are you sure you want to delete all resources? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Finding resource groups..."

# Find resource groups with ALZ-v3 tag
RESOURCE_GROUPS=$(az group list \
    --query "[?tags.ManagedBy=='ALZ-v3-Local' || tags.ManagedBy=='ALZ-v3-Pipeline'].name" \
    -o tsv)

if [ -z "$RESOURCE_GROUPS" ]; then
    echo "No resource groups found"
    exit 0
fi

echo "Resource groups to delete:"
echo "$RESOURCE_GROUPS"
echo ""

# Delete in parallel
for rg in $RESOURCE_GROUPS; do
    echo "Deleting: $rg"
    az group delete -n $rg --yes --no-wait &
done

wait

echo ""
echo "Deletion initiated for all resource groups"
echo "Waiting for completion..."

# Wait loop
MAX_WAIT=600
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    REMAINING=$(az group list \
        --query "[?tags.ManagedBy=='ALZ-v3-Local' || tags.ManagedBy=='ALZ-v3-Pipeline'].name" \
        -o tsv | wc -l)

    if [ "$REMAINING" -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo "All resource groups deleted successfully!"
        echo "=========================================="
        exit 0
    fi

    echo "Waiting... $REMAINING resource groups remaining"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

echo ""
echo "WARNING: Timeout reached. Some groups may still be deleting."
az group list --query "[?tags.ManagedBy=='ALZ-v3-Local' || tags.ManagedBy=='ALZ-v3-Pipeline'].name" -o table
