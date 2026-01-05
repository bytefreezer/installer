# Instructions for Claude - ByteFreezer Installer

## Project Overview

This is the ByteFreezer Installer package - deployment configurations for self-hosted ByteFreezer installations.

## Structure

```
installer/
├── helm/           # Kubernetes Helm charts
│   ├── bytefreezer/   # Processing stack (receiver, piper, packer)
│   └── proxy/         # Edge proxy
├── docker/         # Docker Compose deployments
│   ├── bytefreezer/   # Processing stack
│   └── proxy/         # Edge proxy
├── ecs/            # AWS ECS Fargate deployments
│   ├── bytefreezer/   # Processing stack (CloudFormation + Terraform)
│   └── proxy/         # Edge proxy (CloudFormation + Terraform)
└── README.md
```

## Key Points

- This package does NOT include control plane or UI
- Customers connect to managed control service (api.bytefreezer.com)
- All deployments need: control service URL + API key + S3 storage

## When Making Changes

1. Keep configurations consistent across deployment types
2. Test Helm charts with `helm lint` and `helm template`
3. Validate docker-compose with `docker compose config`
4. Validate Terraform with `terraform fmt` and `terraform validate`
5. Update documentation when adding features
6. Keep monitoring (Prometheus) optional but available

## Configuration Consistency

Ensure these settings are consistent across all deployment types:

- Service ports: receiver (8080/8081/9091), piper (8082/9092), packer (8083/9093)
- Metrics ports: 9091 (receiver), 9092 (piper), 9093 (packer)
- S3 bucket names: intake, piper, packer, geoip
- Health check paths: /api/v1/health
