# gcp-blueprint

A reusable GitHub Actions workflow that deploys infrastructure and applications to GCP using Terraform + Helm. Point it at a GCP project and a directory — it handles state management, infrastructure provisioning, and app deployment.

## What it does

1. **Bootstraps Terraform state** — creates a GCS bucket (`blueprint-tfstate-{project_number}`) if it doesn't exist
2. **Provisions infrastructure** — runs `terraform apply` against your Terraform config
3. **Deploys your app** — reads GKE cluster info from Terraform outputs, then runs `helm upgrade --install`

All authentication uses GitHub OIDC — no long-lived keys.

## Prerequisites

- A GCP project with the following APIs enabled:
  - Kubernetes Engine API
  - Cloud Storage API
  - Cloud Resource Manager API
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines#github-actions) configured to trust your GitHub repo
- A GCP service account with permissions to:
  - Create/manage GCS buckets (for TF state)
  - Apply your Terraform resources
  - Access the target GKE cluster

## Repository layout

Your calling repo should have this structure (path is configurable via `deploy_dir`, defaults to `deploy`):

```
deploy/
├── terraform/
│   ├── main.tf          # your infrastructure — must use a gcs backend
│   ├── variables.tf
│   └── ...
└── helm/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        └── ...
```

### Terraform requirements

Your Terraform config **must**:

1. Declare a `gcs` backend (the bucket is injected at init time):
   ```hcl
   terraform {
     backend "gcs" {}
   }
   ```

2. Define these two outputs — the workflow checks for them before running `apply`:
   ```hcl
   output "gke_cluster_name" {
     value = google_container_cluster.main.name
   }

   output "gke_cluster_location" {
     value = google_container_cluster.main.location
   }
   ```

### Helm

The `helm/` directory is passed directly to `helm upgrade --install`. It can be a chart with `Chart.yaml`, or any structure Helm accepts (including subchart references).

## Usage

Create a workflow in your repo that calls this one:

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: your-org/gcp-blueprint/.github/workflows/deploy.yml@main
    with:
      gcp_project_id: my-gcp-project
      workload_identity_provider: projects/123456/locations/global/workloadIdentityPools/github/providers/github-actions
      service_account: deploy@my-gcp-project.iam.gserviceaccount.com
      # deploy_dir: deploy          # optional, this is the default
      # helm_release_name: app      # optional, this is the default
```

### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `gcp_project_id` | yes | — | GCP project ID (the string, not the number) |
| `workload_identity_provider` | yes | — | Full resource name of the Workload Identity Provider |
| `service_account` | yes | — | GCP service account email for OIDC |
| `deploy_dir` | no | `deploy` | Repo path containing `terraform/` and `helm/` |
| `helm_release_name` | no | `app` | Name for the Helm release |

## How state is managed

The workflow automatically creates a GCS bucket named `blueprint-tfstate-{project_number}` in your project on the first run. Subsequent runs reuse it. The bucket has versioning enabled so you can recover from bad state.

Your Terraform config should declare `backend "gcs" {}` with no bucket — the workflow injects the bucket name via `-backend-config` at init time.
