#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a GCP project for use with gcp-blueprint.
# Creates: WIF pool + provider, deploy service account, state bucket.
#
# Usage:
#   ./bootstrap.sh <gcp-project-id> <github-org/repo>
#
# Example:
#   ./bootstrap.sh my-project BackSlasher/my-app

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <gcp-project-id> <github-org/repo>"
  exit 1
fi

PROJECT_ID="$1"
GITHUB_REPO="$2"
POOL_ID="github"
PROVIDER_ID="github-actions"
SA_NAME="github-deploy"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Bootstrapping project '${PROJECT_ID}' for repo '${GITHUB_REPO}'"
echo ""

# --- Enable required APIs ---

echo "==> Enabling APIs..."
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  --project="${PROJECT_ID}" \
  --quiet

# --- Workload Identity Federation ---

echo "==> Creating Workload Identity Pool..."
gcloud iam workload-identity-pools create "${POOL_ID}" \
  --project="${PROJECT_ID}" \
  --location=global \
  --display-name="GitHub Actions" \
  2>/dev/null || echo "    (pool already exists)"

echo "==> Creating OIDC Provider..."
gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" \
  --location=global \
  --workload-identity-pool="${POOL_ID}" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${GITHUB_REPO}'" \
  2>/dev/null || echo "    (provider already exists)"

# --- Service Account ---

echo "==> Creating service account..."
gcloud iam service-accounts create "${SA_NAME}" \
  --project="${PROJECT_ID}" \
  --display-name="GitHub Actions Deploy" \
  2>/dev/null || echo "    (service account already exists)"

echo "==> Granting editor role..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/editor" \
  --condition=None \
  --quiet

# --- WIF → Service Account binding ---

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

echo "==> Binding WIF to service account..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${MEMBER}" \
  --condition=None \
  --quiet

# --- State bucket ---

BUCKET_NAME="blueprint-state-${PROJECT_NUMBER}"

echo "==> Creating state bucket gs://${BUCKET_NAME}..."
gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --location=US \
  --uniform-bucket-level-access \
  2>/dev/null || echo "    (bucket already exists)"

# --- Output ---

echo ""
echo "=== Done ==="
echo ""
echo "Set these as GitHub repository variables:"
echo ""
echo "  GCP_PROJECT_ID     = ${PROJECT_ID}"
echo "  GCP_PROJECT_NUMBER = ${PROJECT_NUMBER}"
echo ""
echo "Then in your repo's .github/workflows/deploy.yml:"
echo ""
echo "  uses: BackSlasher/gcp-blueprint/.github/workflows/deploy.yml@main"
echo "  with:"
echo "    gcp_project_id: \${{ vars.GCP_PROJECT_ID }}"
echo "    gcp_project_number: \${{ vars.GCP_PROJECT_NUMBER }}"
