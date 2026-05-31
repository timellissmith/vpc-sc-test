#!/bin/bash
# ==============================================================================
# Google Cloud VPC SC & BigQuery sharing Infrastructure Teardown
# ==============================================================================
set -eu

# Load environment configuration automatically if .envrc is present
if [ -f .envrc ]; then
    echo "Loading environment variables from .envrc..."
    source .envrc
fi

echo "=========================================================="
echo "Tearing Down Infrastructure..."
echo "=========================================================="

terraform destroy -auto-approve

# Clean up local state cache
rm -f terraform.tfstate terraform.tfstate.backup

echo "=========================================================="
echo "🎉 Teardown complete. All temporary projects, folders, and perimeters destroyed."
echo "=========================================================="
