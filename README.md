# gcp-blueprint

A reusable GitHub Actions workflow that deploys infrastructure and applications to GCP using Pulumi. Point it at a GCP project and a Pulumi program — it handles state management and runs `pulumi up`.

## What it does

1. **Authenticates to GCP** via GitHub OIDC — no long-lived keys
2. **Bootstraps state storage** — creates a GCS bucket if it doesn't exist
3. **Runs your Pulumi program** — provisions infrastructure and deploys your app in one step

## Quick start

### 1. Bootstrap your GCP project

Run the bootstrap script once per project. It creates the Workload Identity Federation setup, a deploy service account, and the state bucket:

```bash
./bootstrap.sh <gcp-project-id> <github-org/repo>

# Example:
./bootstrap.sh my-project BackSlasher/my-app
```

The script will output the three values you need for GitHub. Set them as [repository variables](https://docs.github.com/en/actions/learn-github-actions/variables):

- `GCP_PROJECT_ID`
- `WIF_PROVIDER`
- `GCP_SERVICE_ACCOUNT`

### 2. Add a Pulumi project

Create a `deploy/` directory in your repo with a Pulumi project:

```
deploy/
├── Pulumi.yaml
├── package.json        # or requirements.txt, go.mod
├── index.ts            # or __main__.py, main.go
└── ...
```

The workflow detects the runtime from `Pulumi.yaml` and installs dependencies automatically. Supported runtimes: `nodejs`, `python`, `go`.

### 3. Add the workflow

Create `.github/workflows/deploy.yml` in your repo:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: BackSlasher/gcp-blueprint/.github/workflows/deploy.yml@main
    with:
      gcp_project_id: ${{ vars.GCP_PROJECT_ID }}
      workload_identity_provider: ${{ vars.WIF_PROVIDER }}
      service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
      # deploy_dir: deploy        # optional, this is the default
      # pulumi_stack: prod         # optional, this is the default
```

Push to `main` and the workflow will deploy.

## What bootstrap.sh creates

| Resource | Purpose |
|---|---|
| Workload Identity Pool (`github`) | Trusts GitHub Actions OIDC tokens |
| OIDC Provider (`github-actions`) | Maps GitHub token claims, scoped to your repo |
| Service account (`github-deploy@...`) | Identity used for deployments, granted `roles/editor` |
| GCS bucket (`blueprint-state-{project_number}`) | Pulumi state backend |

The script is idempotent — safe to re-run.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `gcp_project_id` | yes | — | GCP project ID (the string, not the number) |
| `workload_identity_provider` | yes | — | Full resource name of the Workload Identity Provider |
| `service_account` | yes | — | GCP service account email for OIDC |
| `deploy_dir` | no | `deploy` | Repo path containing the Pulumi project |
| `pulumi_stack` | no | `prod` | Pulumi stack name |

## How state is managed

The workflow creates a GCS bucket named `blueprint-state-{project_number}` on the first run (also created by `bootstrap.sh`). Subsequent runs reuse it. Pulumi logs into this bucket as its state backend — no Pulumi Cloud account required.

## Examples

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

### GKE with Helm (TypeScript)

```typescript
import * as gcp from "@pulumi/gcp";
import * as docker_build from "@pulumi/docker-build";
import * as k8s from "@pulumi/kubernetes";

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

const cluster = new gcp.container.Cluster("cluster", {
    location: "us-central1",
    initialNodeCount: 1,
});

const k8sProvider = new k8s.Provider("k8s", {
    kubeconfig: cluster.endpoint.apply(/* ... */),
});

new k8s.helm.v3.Release("app", {
    chart: "./helm",
    values: { image: { repository: image.tags[0] } },
}, { provider: k8sProvider });
```
