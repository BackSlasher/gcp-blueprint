# gcp-blueprint

A reusable GitHub Actions workflow that deploys infrastructure and applications to GCP using Pulumi. Point it at a GCP project and a Pulumi program — it handles state management and runs `pulumi up`.

## What it does

1. **Authenticates to GCP** via GitHub OIDC — no long-lived keys
2. **Bootstraps state storage** — creates a GCS bucket if it doesn't exist
3. **Runs your Pulumi program** — provisions infrastructure and deploys your app in one step

## Prerequisites

- A GCP project with the APIs enabled for whatever you're deploying (GKE, Cloud Run, Artifact Registry, etc.)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines#github-actions) configured to trust your GitHub repo
- A GCP service account with permissions to create GCS buckets (for state) and manage your target resources

## Repository layout

Your calling repo should have a Pulumi project in the deploy directory (configurable via `deploy_dir`, defaults to `deploy`):

```
deploy/
├── Pulumi.yaml
├── package.json        # or requirements.txt, go.mod
├── index.ts            # or __main__.py, main.go
└── ...
```

The workflow detects the runtime from `Pulumi.yaml` and installs dependencies automatically. Supported runtimes: `nodejs`, `python`, `go`.

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
      # deploy_dir: deploy        # optional, this is the default
      # pulumi_stack: prod         # optional, this is the default
```

### Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `gcp_project_id` | yes | — | GCP project ID (the string, not the number) |
| `workload_identity_provider` | yes | — | Full resource name of the Workload Identity Provider |
| `service_account` | yes | — | GCP service account email for OIDC |
| `deploy_dir` | no | `deploy` | Repo path containing the Pulumi project |
| `pulumi_stack` | no | `prod` | Pulumi stack name |

## How state is managed

The workflow creates a GCS bucket named `blueprint-state-{project_number}` on the first run. Subsequent runs reuse it. Pulumi logs into this bucket as its state backend — no Pulumi Cloud account required.

## Examples

### GKE with Helm (TypeScript)

Your Pulumi program can provision a GKE cluster, build and push a Docker image to Artifact Registry, and deploy via Helm — all in one `pulumi up`:

```typescript
import * as gcp from "@pulumi/gcp";
import * as docker_build from "@pulumi/docker-build";
import * as k8s from "@pulumi/kubernetes";

// Artifact Registry repo
const repo = new gcp.artifactregistry.Repository("repo", {
    repositoryId: "my-app",
    format: "DOCKER",
    location: "us-central1",
});

// Build and push image
const image = new docker_build.Image("app-image", {
    context: { location: "../../" },  // repo root
    tags: [pulumi.interpolate`${repo.location}-docker.pkg.dev/${gcp.config.project}/${repo.repositoryId}/app:latest`],
    push: true,
});

// GKE cluster
const cluster = new gcp.container.Cluster("cluster", {
    location: "us-central1",
    initialNodeCount: 1,
});

// Helm release using the built image
const k8sProvider = new k8s.Provider("k8s", {
    kubeconfig: cluster.endpoint.apply(/* ... */),
});

new k8s.helm.v3.Release("app", {
    chart: "./helm",
    values: { image: { repository: image.tags[0] } },
}, { provider: k8sProvider });
```

### Cloud Run (TypeScript)

```typescript
import * as gcp from "@pulumi/gcp";
import * as docker_build from "@pulumi/docker-build";

const repo = new gcp.artifactregistry.Repository("repo", {
    repositoryId: "my-app",
    format: "DOCKER",
    location: "us-central1",
});

const image = new docker_build.Image("app-image", {
    context: { location: "../../" },
    tags: [pulumi.interpolate`${repo.location}-docker.pkg.dev/${gcp.config.project}/${repo.repositoryId}/app:latest`],
    push: true,
});

new gcp.cloudrunv2.Service("service", {
    location: "us-central1",
    template: {
        containers: [{
            image: image.ref,
        }],
    },
});
```
