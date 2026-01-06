# ByteFreezer Helm Chart

Deploy the ByteFreezer data processing pipeline to Kubernetes.

## Overview

This chart deploys the processing stack. For edge data collection, use the separate `proxy` chart.

| Component | Description | Port |
|-----------|-------------|------|
| **receiver** | HTTP webhook receiver, stores raw data to S3 | 8081 (API), 8080 (webhook) |
| **piper** | Data pipeline processing, transforms raw data | 8082 (API) |
| **packer** | Compresses processed data into Parquet files | 8083 (API) |

**Note:** The proxy is deployed separately using the `proxy` chart. This allows proxies to be deployed at edge locations while the processing stack runs centrally.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.0+
- Control service URL and API key (provided by ByteFreezer)
- S3-compatible storage (or use bundled MinIO)

## Quick Start

### Minimal Installation (with bundled MinIO)

```bash
helm install bytefreezer ./bytefreezer \
  --set minio.enabled=true \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

### Installation with External S3

```bash
helm install bytefreezer ./bytefreezer \
  --set s3.endpoint=s3.amazonaws.com \
  --set s3.region=us-east-1 \
  --set s3.accessKey=YOUR_ACCESS_KEY \
  --set s3.secretKey=YOUR_SECRET_KEY \
  --set s3.useSSL=true \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.imageRegistry` | Container image registry | `""` |
| `global.imagePullSecrets` | Image pull secrets | `[]` |
| `global.storageClass` | Storage class for PVCs | `""` |
| `global.deploymentType` | Deployment type (`managed` or `on_prem`) | `on_prem` |

### S3 Storage

| Parameter | Description | Default |
|-----------|-------------|---------|
| `s3.endpoint` | S3 endpoint | `minio:9000` |
| `s3.region` | S3 region | `us-east-1` |
| `s3.accessKey` | S3 access key | `""` |
| `s3.secretKey` | S3 secret key | `""` |
| `s3.useSSL` | Use SSL for S3 | `false` |
| `s3.useIAMRole` | Use IAM role instead of keys | `false` |
| `s3.existingSecret` | Use existing secret for S3 credentials | `""` |
| `s3.buckets.intake` | Bucket for raw data (receiver writes, piper reads) | `intake` |
| `s3.buckets.piper` | Bucket for processed data (piper writes, packer reads) | `piper` |
| `s3.buckets.geoip` | Bucket for GeoIP databases | `geoip` |

### MinIO (Optional)

Enable bundled MinIO if you don't have external S3 storage.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `minio.enabled` | Deploy MinIO | `false` |
| `minio.rootUser` | MinIO root user | `minioadmin` |
| `minio.rootPassword` | MinIO root password | `minioadmin` |
| `minio.persistence.enabled` | Enable persistent storage | `true` |
| `minio.persistence.size` | Storage size | `50Gi` |
| `minio.createBuckets` | Auto-create required buckets | `true` |

### Control Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `controlService.enabled` | Enable control service integration | `true` |
| `controlService.url` | Control service URL | `""` |
| `controlService.apiKey` | API key for authentication | `""` |
| `controlService.existingSecret` | Use existing secret for API key | `""` |
| `controlService.timeoutSeconds` | Request timeout | `30` |

### Component Configuration

Each component (proxy, receiver, piper, packer) supports:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `{component}.enabled` | Enable component | `true` |
| `{component}.replicaCount` | Number of replicas | `1` |
| `{component}.image.repository` | Image repository | `bytefreezer/{component}` |
| `{component}.image.tag` | Image tag | Chart appVersion |
| `{component}.resources` | Resource requests/limits | varies |
| `{component}.nodeSelector` | Node selector | `{}` |
| `{component}.tolerations` | Tolerations | `[]` |
| `{component}.affinity` | Affinity rules | `{}` |

### Receiver Webhook LoadBalancer

The receiver exposes a LoadBalancer service for external data ingestion.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `receiver.webhookService.enabled` | Enable LoadBalancer | `true` |
| `receiver.webhookService.type` | Service type | `LoadBalancer` |
| `receiver.webhookService.port` | External port | `8080` |
| `receiver.webhookService.annotations` | Service annotations | `{}` |

### Monitoring

Enable monitoring to collect metrics from ByteFreezer components.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `monitoring.enabled` | Enable metrics collection | `false` |
| `monitoring.mode` | Mode: `prometheus`, `otlp_http`, `otlp_grpc` | `prometheus` |
| `monitoring.externalEndpoint` | External metrics endpoint (for push modes) | `""` |

#### Option 1: Bundled Prometheus

Deploy a standalone Prometheus server with the chart:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `monitoring.prometheus.enabled` | Deploy Prometheus | `false` |
| `monitoring.prometheus.persistence.enabled` | Enable persistent storage | `true` |
| `monitoring.prometheus.persistence.size` | Storage size | `10Gi` |
| `monitoring.prometheus.retention` | Data retention period | `15d` |
| `monitoring.prometheus.service.type` | Service type | `ClusterIP` |

#### Option 2: Bundled VictoriaMetrics

Deploy VictoriaMetrics (Prometheus-compatible, more memory efficient):

| Parameter | Description | Default |
|-----------|-------------|---------|
| `monitoring.victoriametrics.enabled` | Deploy VictoriaMetrics | `false` |
| `monitoring.victoriametrics.persistence.enabled` | Enable persistent storage | `true` |
| `monitoring.victoriametrics.persistence.size` | Storage size | `10Gi` |
| `monitoring.victoriametrics.retention` | Data retention period | `30d` |

#### Option 3: Prometheus Operator (ServiceMonitor)

If you have Prometheus Operator (kube-prometheus-stack) installed:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `monitoring.serviceMonitor.enabled` | Create ServiceMonitor resources | `false` |
| `monitoring.serviceMonitor.labels` | Additional labels for Prometheus selection | `{}` |
| `monitoring.serviceMonitor.namespace` | Namespace for ServiceMonitors | `""` |
| `monitoring.serviceMonitor.interval` | Scrape interval | `30s` |

#### Metrics Ports

When monitoring is enabled, each service exposes a metrics port:

| Component | Metrics Port | Path |
|-----------|--------------|------|
| Receiver | 9091 | `/metrics` |
| Piper | 9092 | `/metrics` |
| Packer | 9093 | `/metrics` |

## Monitoring Examples

### With Bundled Prometheus

```bash
helm install bytefreezer ./bytefreezer \
  --set monitoring.enabled=true \
  --set monitoring.prometheus.enabled=true \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

Access Prometheus UI:
```bash
kubectl port-forward svc/bytefreezer-prometheus 9090:9090
# Open http://localhost:9090
```

### With Prometheus Operator

If you have kube-prometheus-stack installed:

```bash
helm install bytefreezer ./bytefreezer \
  --set monitoring.enabled=true \
  --set monitoring.serviceMonitor.enabled=true \
  --set monitoring.serviceMonitor.labels.release=prometheus \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

### With External Prometheus

Configure your external Prometheus to scrape ByteFreezer services:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'bytefreezer-receiver'
    kubernetes_sd_configs:
      - role: service
        namespaces:
          names: ['bytefreezer']
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_component]
        regex: receiver
        action: keep
      - source_labels: [__meta_kubernetes_service_port_name]
        regex: metrics
        action: keep

  - job_name: 'bytefreezer-piper'
    kubernetes_sd_configs:
      - role: service
        namespaces:
          names: ['bytefreezer']
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_component]
        regex: piper
        action: keep
      - source_labels: [__meta_kubernetes_service_port_name]
        regex: metrics
        action: keep

  - job_name: 'bytefreezer-packer'
    kubernetes_sd_configs:
      - role: service
        namespaces:
          names: ['bytefreezer']
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_component]
        regex: packer
        action: keep
      - source_labels: [__meta_kubernetes_service_port_name]
        regex: metrics
        action: keep
```

### Grafana Dashboard

Both Prometheus and VictoriaMetrics work with Grafana. To connect:

1. Add data source in Grafana:
   - Type: Prometheus
   - URL: `http://bytefreezer-prometheus:9090` (or `http://bytefreezer-victoriametrics:8428`)

2. Import ByteFreezer dashboards or create custom ones using available metrics.

## Scaling

### Horizontal Scaling

Scale components by increasing replica count:

```bash
helm upgrade bytefreezer ./bytefreezer \
  --set receiver.replicaCount=3 \
  --set piper.replicaCount=2 \
  --set packer.replicaCount=2
```

**How parallel processing works:**

- **Receiver**: All replicas can accept data simultaneously (LoadBalancer distributes traffic)
- **Piper**: Replicas process different files in parallel (file-level locking via control service)
- **Packer**: Replicas process different tenants in parallel (tenant-level locking via control service)

Each replica has a unique instance ID (Kubernetes pod hostname). The control service coordinates work distribution to prevent duplicate processing.

### Resource Scaling

Adjust resources per component:

```yaml
piper:
  replicaCount: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 4000m
      memory: 4Gi
```

## Examples

### Production Deployment with AWS S3

```bash
helm install bytefreezer ./bytefreezer \
  --namespace bytefreezer \
  --create-namespace \
  --set s3.endpoint=s3.us-east-1.amazonaws.com \
  --set s3.region=us-east-1 \
  --set s3.useSSL=true \
  --set s3.useIAMRole=true \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY \
  --set receiver.replicaCount=3 \
  --set piper.replicaCount=2 \
  --set packer.replicaCount=2 \
  --set monitoring.enabled=true \
  --set monitoring.victoriametrics.enabled=true
```

### Development/Testing with MinIO

```bash
helm install bytefreezer ./bytefreezer \
  --namespace bytefreezer-dev \
  --create-namespace \
  --set minio.enabled=true \
  --set minio.persistence.enabled=false \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

### Using Values File

Create `my-values.yaml`:

```yaml
minio:
  enabled: true
  persistence:
    size: 100Gi

controlService:
  url: https://api.bytefreezer.com
  apiKey: YOUR_API_KEY

receiver:
  replicaCount: 3
  webhookService:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb

piper:
  replicaCount: 2
  processing:
    maxConcurrentJobs: 20

packer:
  replicaCount: 2
  parquet:
    maxFileSizeMB: 256

monitoring:
  enabled: true
  victoriametrics:
    enabled: true
    persistence:
      size: 50Gi
```

Install with values file:

```bash
helm install bytefreezer ./bytefreezer -f my-values.yaml
```

## Architecture

```
                                    Processing Stack (this chart)
                    ┌─────────────────────────────────────────────────────────┐
                    │                    Kubernetes Cluster                    │
                    │                                                          │
  From Proxies      │     ┌──────────┐                                        │
  ─────────────────►│     │ Receiver │──┐                                     │
  (edge locations)  │     └──────────┘  │                                     │
                    │          ▲        │                                     │
                    │    LoadBalancer   ▼                                     │
                    │               ┌───────┐                                 │
                    │               │ MinIO │ (optional)                      │
                    │               │  S3   │                                 │
                    │               └───────┘                                 │
                    │                   │                                     │
                    │       ┌───────────┼───────────┐                         │
                    │       ▼           ▼           ▼                         │
                    │  ┌───────┐   ┌───────┐   ┌────────┐                     │
                    │  │ Piper │   │ Piper │   │ Packer │                     │
                    │  └───────┘   └───────┘   └────────┘                     │
                    │       │           │           │                         │
                    └───────┼───────────┼───────────┼─────────────────────────┘
                            │           │           │
                            ▼           ▼           ▼
                 ┌─────────────────────────────────────────┐
                 │         Control Service (Managed)        │
                 │         api.bytefreezer.com              │
                 └─────────────────────────────────────────┘
```

## Data Flow

1. **Proxies** (deployed separately) collect data and forward to **Receiver**
2. **Receiver** stores raw data to S3 (`intake` bucket)
3. **Piper** polls S3, processes data, stores to S3 (`piper` bucket)
4. **Packer** polls S3, packs into Parquet files, uploads to per-tenant destinations (from Control API)
5. All components report health and coordinate via **Control Service**

## Troubleshooting

### Check Component Status

```bash
kubectl get pods -l app.kubernetes.io/instance=bytefreezer
kubectl logs -l app.kubernetes.io/component=receiver
kubectl logs -l app.kubernetes.io/component=piper
```

### Verify S3 Connectivity

```bash
kubectl exec -it deploy/bytefreezer-receiver -- wget -qO- http://minio:9000/minio/health/ready
```

### Check Control Service Connectivity

```bash
kubectl exec -it deploy/bytefreezer-piper -- wget -qO- https://api.bytefreezer.com/api/v1/health
```

### View Receiver LoadBalancer IP

```bash
kubectl get svc bytefreezer-receiver-webhook -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Uninstall

```bash
helm uninstall bytefreezer
```

To also remove PVCs:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=bytefreezer
```
