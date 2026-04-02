# ByteFreezer Installer

Self-hosted deployment packages for ByteFreezer data processing pipeline.

## Deploy with Claude + MCP

Skip the manual steps. Connect [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to the ByteFreezer MCP server and describe your deployment in plain English -- Claude creates accounts, generates configs, deploys services, and verifies the pipeline end to end.

Make sure your claude code is running,

register and get [bytefreezer API key](https://bytefreezer.com/dashboard/api-keys).

```bash
claude mcp add --transport http bytefreezer \
  https://mcp.bytefreezer.com/mcp \
  --header "Authorization: Bearer YOUR_BYTEFREEZER_API_KEY"
```

Make sure to restart claude code session, so new mcp server recognized.

Ask Claude Code to verify bytefreezer mcp

> *"please see if bytefreezer mcp is accessible"*

Then read one of the guides below.

Claude handles everything -- account creation, config generation, deployment, dataset assignment, and verification. Works with Docker Compose, Kubernetes (Helm), systemd, or standalone binaries.

Each deploy guide builds a bytefreezer demo. deploying demo data feed adn allowing you to see a data via UI Dashboard for managed deploy, or via connector component for on prem deploys.

---

## Tested Deployment Guides (MCP-automated)

These guides have full MCP runbook support with automated config generation,
deployment, pipeline verification, and cleanup.

| Guide | Description |
|-------|-------------|
| [Managed Quickstart](docs/guide-managed.md) | Proxy test only -- deploy a single proxy, we handle the rest |
| [On-Prem: Docker Compose](docs/guide-onprem-docker.md) | Full stack on a single host, your data stays local |
| [On-Prem: Kubernetes](docs/guide-onprem-k8s.md) | Full stack on K8s with Helm charts |
| [On-Prem: HA Kubernetes](docs/guide-onprem-k8s-ha.md) | 3x replicas, PDBs, anti-affinity, failure tested |

Post-deployment content is included in each guide above: dashboard overview, transformations, connector, demo vs. production.

---

## Tested Deployment Targets

| Platform | Directory | MCP Runbook |
|----------|-----------|-------------|
| **Docker Compose** | `docker/` | `bf_runbook name=onprem-full-docker-compose` |
| **Kubernetes (Helm)** | `helm/` | `bf_runbook name=onprem-full-k8s` |
| **Kubernetes HA (Helm)** | `helm/` | `bf_runbook name=onprem-ha-k8s` |
| **Managed Proxy** | `docker/` | `bf_runbook name=proxy-managed-docker-compose` |

---

## Community Deployment Guides

These targets have config keys aligned with verified deployments but have **not been
end-to-end tested** with the MCP runtime. See [community/README.md](community/README.md)
for details and known limitations.

| Platform | Directory | Notes |
|----------|-----------|-------|
| **Ansible** | `community/ansible/` | Bare metal / VMs, systemd services |
| **Azure AKS** | `community/azure/aks/` | Terraform, uses Helm chart |
| **Azure Container Instances** | `community/azure/container-instances/` | Terraform |
| **AWS ECS Fargate** | `community/ecs/` | CloudFormation + Terraform |
| **GCP GKE** | `community/gcp/gke/` | Terraform, uses Helm chart |
| **GCP Cloud Run** | `community/gcp/cloud-run/` | Terraform, no UDP support |

---

## Architecture

ByteFreezer consists of two deployment units:

1. **Processing Stack** (`bytefreezer`) - Deploy centrally
   - Receiver: HTTP webhook receiver, stores raw data to S3
   - Piper: Data pipeline processing, transforms raw data
   - Packer: Compresses processed data into Parquet files
   - Connector: DuckDB query engine for parquet files

2. **Proxy** (`proxy`) - Deploy at edge locations
   - Collects data and forwards to the processing stack

```
   Edge Sites                              Central Processing
                                       +---------------------------+
+------------------+                   |                           |
|  Site A          |                   |   +----------+            |
|  +-----------+   |   +-----------+   |   | Receiver |            |
|  |   Proxy   |---+-->|           +---+-->+----+-----+            |
|  +-----------+   |   |           |   |        |                  |
+------------------+   |           |   |        v                  |
                       |  Network  |   |   +----+----+             |
+------------------+   |           |   |   |   S3    |             |
|  Site B          |   |           |   |   +----+----+             |
|  +-----------+   |   |           |   |        |                  |
|  |   Proxy   |---+-->|           |   |   +----+----+             |
|  +-----------+   |   +-----------+   |   |  Piper  |             |
+------------------+                   |   +----+----+             |
                                       |        |                  |
                                       |   +----+----+             |
                                       |   | Packer  |             |
                                       |   +----+----+             |
                                       |        |                  |
                                       |   +----+-----+            |
                                       |   | Connector |            |
                                       |   +----------+            |
                                       +---------------------------+
```

## Prerequisites

- ByteFreezer control service access (URL + API key)
- S3-compatible storage (or use bundled MinIO for testing)

---

## Kubernetes (Helm)

Deploy to any Kubernetes cluster using Helm charts.

```bash
cd helm

# Deploy processing stack
helm install bytefreezer ./bytefreezer \
  --set minio.enabled=true \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY

# Deploy proxy
helm install proxy ./proxy \
  --set receiver.url=http://bytefreezer-receiver:8080 \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

See [helm/bytefreezer/README.md](helm/bytefreezer/README.md) for configuration options.

---

## Docker Compose

Deploy to single hosts or small environments.

```bash
cd docker/bytefreezer

# Configure
cp .env.example .env
# Edit .env with credentials

# Start with MinIO
docker compose --profile with-minio up -d
```

See [docker/README.md](docker/README.md) for full configuration.

---

## Configuration Reference

### Control Service

All deployments require control service configuration:

| Parameter | Description |
|-----------|-------------|
| `controlService.url` | Control service URL (e.g., https://api.bytefreezer.com) |
| `controlService.apiKey` | API key for authentication |

### S3 Storage

Configure S3-compatible storage:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `s3.endpoint` | S3 endpoint | `minio:9000` |
| `s3.region` | S3 region | `us-east-1` |
| `s3.accessKey` | Access key | - |
| `s3.secretKey` | Secret key | - |
| `s3.useSSL` | Use SSL | `false` |

### Monitoring

All deployment types support Prometheus metrics:

| Component | Metrics Port | Path |
|-----------|--------------|------|
| Receiver | 9091 | `/metrics` |
| Piper | 9092 | `/metrics` |
| Packer | 9093 | `/metrics` |

---

## Support

For issues and questions:
- Documentation: https://docs.bytefreezer.com
- Support: support@bytefreezer.com
