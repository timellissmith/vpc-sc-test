#!/bin/bash
# ==============================================================================
# Google Cloud VPC SC & BigQuery sharing Infrastructure Deployer
# ==============================================================================
set -eu

# Load environment configuration automatically if .envrc is present
if [ -f .envrc ]; then
    echo "Loading environment variables from .envrc..."
    source .envrc
fi

# Ensure essential variables are present
if [ -z "${TF_VAR_org_id:-}" ] || [ -z "${TF_VAR_billing_id:-}" ]; then
    echo "❌ ERROR: TF_VAR_org_id and TF_VAR_billing_id must be set. Please check your .env file."
    exit 1
fi

# Default parameter to false if not provided (isolated by default)
CROSS_PERIMETER_ACCESS=${1:-false}

echo "=========================================================="
echo "Deploying / Updating Infrastructure..."
echo "enable_cross_perimeter_access = $CROSS_PERIMETER_ACCESS"
echo "=========================================================="

terraform init
terraform apply -var="enable_cross_perimeter_access=$CROSS_PERIMETER_ACCESS" -auto-approve

# Retrieve outputs from Terraform
PROJ_B=$(terraform output -raw project_b_id)
SA_EMAIL=$(terraform output -raw service_account_email)

echo "=========================================================="
echo "✅ Deployment / Update complete."
echo "Project B: $PROJ_B"
echo "Test Service Account: $SA_EMAIL"
echo "=========================================================="
