# Deploy ByteFreezer with Claude + MCP

Use Claude Code as your deployment assistant. Connect it to the ByteFreezer MCP server and describe your deployment goal in plain English — Claude handles tenant creation, dataset configuration, config generation, deployment, and verification.

Each guide below includes prerequisites, Claude setup, deployment prompts, and post-deployment instructions specific to that deployment type.

## Choose Your Deployment

| Deployment | What It Does | Guide |
|---|---|---|
| **Managed (Proxy Only)** | Deploy a single proxy on your host. Processing and storage on bytefreezer.com. | [Deploy Managed Proxy with Claude](guide-deploy-with-claude-managed.md) |
| **On-Prem Docker Compose** | Deploy the full stack (proxy, receiver, piper, packer, MinIO) on a single host. | [Deploy On-Prem Docker with Claude](guide-deploy-with-claude-docker.md) |
| **On-Prem Kubernetes** | Deploy the full stack to a Kubernetes cluster with Helm. | [Deploy On-Prem K8s with Claude](guide-deploy-with-claude-k8s.md) |

## How It Works

Claude Code runs on **your workstation**. It connects to the ByteFreezer control plane via MCP for tenant/dataset/config management, and uses SSH or kubectl to deploy services on remote infrastructure.

```
Your Workstation                    Remote
+------------------+
| Claude Code      |
|   |               |
|   +-- MCP --------|------> api.bytefreezer.com  (tenant, dataset, config generation)
|   |               |
|   +-- SSH --------|------> testhost              (docker compose, files, fakedata)
|   |               |
|   +-- kubectl ----|------> k8s cluster           (helm install, pods, services)
+------------------+
```

## Manual Guides

If you prefer step-by-step instructions without Claude:

- [Managed Quickstart Guide](guide-managed-quickstart.md)
- [On-Prem Docker Compose Guide](guide-onprem-docker-compose.md)
- [On-Prem Kubernetes Guide](guide-onprem-kubernetes.md)
