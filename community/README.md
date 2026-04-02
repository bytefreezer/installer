# Community Deployment Guides

These deployment targets provide infrastructure-as-code for platforms beyond the core
MCP-tested Docker Compose and Kubernetes/Helm deployments. Config templates have been
aligned with verified config keys, but the full pipeline has **not been end-to-end
validated** on these platforms.

For verified, MCP-automated deployments, use:
- [Managed Quickstart](../docs/guide-managed.md) -- proxy only, processing on bytefreezer.com
- [On-Prem: Docker Compose](../docs/guide-onprem-docker.md) -- full stack, single host
- [On-Prem: Kubernetes](../docs/guide-onprem-k8s.md) -- full stack, Helm charts

## Available Targets

| Directory | Platform | Status | Notes |
|-----------|----------|--------|-------|
| `ansible/` | Bare metal / VMs | Config keys fixed | Systemd + Docker containers |
| `azure/aks/` | Azure Kubernetes Service | Uses Helm chart (tested) | Azure Blob needs S3-compatible gateway |
| `azure/container-instances/` | Azure Container Instances | Env var mapping untested | No health checks configured |
| `ecs/` | AWS ECS Fargate | Env var mapping untested | CloudFormation + Terraform |
| `gcp/gke/` | Google Kubernetes Engine | Uses Helm chart (tested) | GCS needs HMAC keys for S3 interop |
| `gcp/cloud-run/` | GCP Cloud Run | Env var mapping untested | No UDP support (HTTP only) |

## Known Limitations

### Environment Variable Mapping
The ECS, Azure Container Instances, and GCP Cloud Run targets configure services via
environment variables. ByteFreezer services use koanf/mapstructure for config parsing,
and the env var naming convention may not map correctly to all config keys. The services
primarily expect YAML config files (verified in Docker Compose and Helm deployments).

### Cloud Object Storage
- **Azure Blob Storage** is not S3-compatible. Services expect the S3 API. Use MinIO
  Gateway or an S3-compatible endpoint.
- **GCS** has S3-compatible interop but requires HMAC keys, not standard GCP service
  account credentials. See: https://cloud.google.com/storage/docs/interoperability

### AKS and GKE (Helm-based)
These targets use the same Helm chart that is tested via MCP. The Helm chart itself is
verified. The Terraform wrapping (cluster creation, storage setup) is untested.

## Contributing

If you deploy ByteFreezer on one of these platforms and find issues:
1. Fix the config and submit a PR
2. Document any platform-specific gotchas
3. Add end-to-end verification steps

Once a target is validated with a full pipeline test (fakedata -> proxy -> receiver ->
piper -> packer -> parquet -> connector query), it can be promoted to a first-class
deployment guide with MCP runbook support.
