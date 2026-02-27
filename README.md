# ByteFreezer Installer

Self-hosted deployment packages for ByteFreezer data processing pipeline.

## Deploy with Claude + MCP

Skip the manual steps. Connect [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to the ByteFreezer MCP server and describe your deployment in plain English — Claude creates accounts, generates configs, deploys services, and verifies the pipeline end to end.

```bash
claude mcp add --transport http bytefreezer \
  https://mcp.bytefreezer.com/mcp \
  --header "Authorization: Bearer YOUR_API_KEY"
```

Then tell Claude what you want:

> *"Deploy a full on-prem ByteFreezer stack with Docker Compose on this host. Create an account, tenant, and syslog dataset. Start fakedata and verify data flows to parquet."*

Claude handles everything — account creation, config generation, deployment, dataset assignment, and verification. Works with Docker Compose, Kubernetes (Helm), systemd, or standalone binaries.

**[Read the full guide](docs/guide-deploy-with-claude.md)**

---

## Getting Started Guides

| Guide | Description |
|-------|-------------|
| [Managed Quickstart](docs/guide-managed-quickstart.md) | Proxy test only — deploy a single proxy, we handle the rest |
| [On-Prem: Docker Compose](docs/guide-onprem-docker-compose.md) | Full stack on a single host, your data stays local |
| [On-Prem: Kubernetes](docs/guide-onprem-kubernetes.md) | Full stack on K8s with Helm charts |
| [Deploy with Claude + MCP](docs/guide-deploy-with-claude.md) | AI-assisted deployment using Claude Code |

---

## Deployment Options

| Platform | Directory | Description |
|----------|-----------|-------------|
| **Kubernetes** | | |
| [Helm Charts](#kubernetes-helm) | `helm/` | Helm charts for any K8s cluster |
| [Azure AKS](#azure-aks) | `azure/aks/` | Terraform for Azure Kubernetes Service |
| [GCP GKE](#gcp-gke) | `gcp/gke/` | Terraform for Google Kubernetes Engine |
| **Serverless Containers** | | |
| [AWS ECS Fargate](#aws-ecs-fargate) | `ecs/` | CloudFormation + Terraform |
| [Azure Container Instances](#azure-container-instances) | `azure/container-instances/` | Terraform |
| [GCP Cloud Run](#gcp-cloud-run) | `gcp/cloud-run/` | Terraform |
| **Other** | | |
| [Docker Compose](#docker-compose) | `docker/` | Single-host or small deployments |
| [Ansible](#ansible) | `ansible/` | Bare metal / VMs |

## Architecture

ByteFreezer consists of two deployment units:

1. **Processing Stack** (`bytefreezer`) - Deploy centrally
   - Receiver: HTTP webhook receiver, stores raw data to S3
   - Piper: Data pipeline processing, transforms raw data
   - Packer: Compresses processed data into Parquet files

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
                                       |   +---------+             |
                                       |                           |
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

## Azure AKS

Deploy to Azure Kubernetes Service using Terraform.

```bash
cd azure/aks/bytefreezer/terraform

# Configure
cat > terraform.tfvars <<EOF
control_service_url     = "https://api.bytefreezer.com"
control_service_api_key = "YOUR_API_KEY"
location                = "eastus"
EOF

terraform init
terraform apply
```

See [azure/aks/](azure/aks/) for full configuration.

---

## Azure Container Instances

Serverless containers on Azure (similar to ECS Fargate).

```bash
cd azure/container-instances/bytefreezer/terraform

# Configure
cat > terraform.tfvars <<EOF
control_service_url     = "https://api.bytefreezer.com"
control_service_api_key = "YOUR_API_KEY"
location                = "eastus"
EOF

terraform init
terraform apply
```

---

## GCP GKE

Deploy to Google Kubernetes Engine using Terraform.

```bash
cd gcp/gke/bytefreezer/terraform

# Configure
cat > terraform.tfvars <<EOF
project_id              = "your-gcp-project"
control_service_url     = "https://api.bytefreezer.com"
control_service_api_key = "YOUR_API_KEY"
region                  = "us-central1"
EOF

terraform init
terraform apply
```

---

## GCP Cloud Run

Serverless containers on Google Cloud.

```bash
cd gcp/cloud-run/bytefreezer/terraform

# Configure
cat > terraform.tfvars <<EOF
project_id              = "your-gcp-project"
control_service_url     = "https://api.bytefreezer.com"
control_service_api_key = "YOUR_API_KEY"
region                  = "us-central1"
EOF

terraform init
terraform apply
```

**Note:** Cloud Run doesn't support UDP, so proxy functionality is limited to HTTP.

---

## AWS ECS Fargate

Deploy to AWS ECS Fargate using CloudFormation or Terraform.

### CloudFormation

```bash
cd ecs/bytefreezer

aws cloudformation create-stack \
  --stack-name bytefreezer \
  --template-body file://cloudformation.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=vpc-xxx \
    ParameterKey=SubnetIds,ParameterValue="subnet-a,subnet-b" \
    ParameterKey=ControlServiceUrl,ParameterValue=https://api.bytefreezer.com \
    ParameterKey=ControlServiceApiKey,ParameterValue=YOUR_API_KEY \
  --capabilities CAPABILITY_IAM
```

### Terraform

```bash
cd ecs/bytefreezer/terraform

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

terraform init
terraform apply
```

See [ecs/README.md](ecs/README.md) for full configuration.

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

# Optional: Enable Prometheus
docker compose --profile with-minio --profile with-prometheus up -d
```

See [docker/README.md](docker/README.md) for full configuration.

---

## Ansible

Deploy to bare metal servers or VMs.

```bash
cd ansible/bytefreezer

# Create inventory
cp inventory.yml.example inventory.yml
# Edit with your servers

# Create secrets
cp vars/secrets.yml.example vars/secrets.yml
# Edit with API key
ansible-vault encrypt vars/secrets.yml

# Deploy
ansible-playbook -i inventory.yml playbook.yml --ask-vault-pass
```

See [ansible/README.md](ansible/README.md) for full configuration.

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

## Comparison

| Feature | Helm | Docker | ECS | ACI | Cloud Run | Ansible |
|---------|------|--------|-----|-----|-----------|---------|
| Auto-scaling | Yes | Manual | Yes | Manual | Yes | Manual |
| UDP Support | Yes | Yes | Yes | Yes | No | Yes |
| Managed K8s | - | - | - | - | - | - |
| Serverless | No | No | Yes | Yes | Yes | No |
| Min Cost | Low | Low | Medium | Low | Low | Low |

---

## Support

For issues and questions:
- Documentation: https://docs.bytefreezer.com
- Support: support@bytefreezer.com
