#!/bin/bash
# ==============================================================================
# Google Cloud VPC SC & BigQuery sharing Integration Test Executor
# ==============================================================================
set -eu

# Load environment configuration automatically if .envrc is present
if [ -f .envrc ]; then
    echo "Loading environment variables from .envrc..."
    source .envrc
fi

# Retrieve outputs from current Terraform state
if ! PROJ_B=$(terraform output -raw project_b_id 2>/dev/null) || [ -z "$PROJ_B" ]; then
    echo "❌ ERROR: Terraform state not found or project B output is empty. Please run ./deploy.sh first."
    exit 1
fi
SA_EMAIL=$(terraform output -raw service_account_email)

echo "=========================================================="
echo "Running Integration Test..."
echo "Project B: $PROJ_B"
echo "Test Service Account: $SA_EMAIL"
echo "=========================================================="

# Get access token by impersonating the test service account (with retry loop for IAM propagation)
echo "Acquiring impersonation token..."
TOKEN=""
for i in {1..20}; do
    TOKEN=$(gcloud auth print-access-token --impersonate-service-account="$SA_EMAIL" 2>/dev/null || true)
    if [ -n "$TOKEN" ]; then
        echo "✅ Successfully impersonated service account."
        break
    fi
    echo "Waiting for IAM token creator role to propagate (attempt $i/20)..."
    sleep 5
done

if [ -z "$TOKEN" ]; then
    echo "❌ ERROR: Failed to impersonate service account. IAM policy did not propagate."
    exit 1
fi

echo "Querying DMZ Linked Dataset..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"query": "SELECT * FROM `'$PROJ_B'.linked_dataset.my_view`", "useLegacySql": false, "useQueryCache": false}' \
     "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJ_B/queries")

echo "----------------------------------------------------------"
echo "Response from BigQuery:"
echo "$RESPONSE"
echo "----------------------------------------------------------"

if [[ "$RESPONSE" == *"HTTP_STATUS:200"* ]] && [[ "$RESPONSE" == *"Top Secret Project A Data"* ]]; then
    echo "✅ TEST PASSED: Cross-perimeter DMZ Linked Dataset queried successfully!"
elif [[ "$RESPONSE" == *"HTTP_STATUS:403"* ]]; then
    echo "🔒 TEST BLOCKED: Request was blocked by VPC Service Controls (expected when isolated)."
else
    echo "❌ TEST FAILED: Unexpected response status or error."
    echo "Retrieving VPC-SC denial logs from Project B ($PROJ_B)..."
    gcloud logging read "protoPayload.metadata.type=\"servicePerimeterReject\" OR (protoPayload.status.code=7 AND protoPayload.serviceName=\"bigquery.googleapis.com\")" --project="$PROJ_B" --limit=5 --format="yaml(protoPayload.status, protoPayload.metadata, protoPayload.authenticationInfo)" || true
    exit 1
fi
