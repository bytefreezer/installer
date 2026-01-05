# ByteFreezer Proxy Helm Chart

Deploy ByteFreezer Proxy for edge data collection and forwarding.

## Overview

The proxy collects data via UDP (syslog, etc.) or webhook and forwards it to a ByteFreezer receiver. Deploy this chart at edge locations where data is generated.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.0+
- ByteFreezer receiver URL (from processing stack deployment)
- Control service URL and API key

## Quick Start

```bash
helm install proxy ./proxy \
  --set receiver.url=https://receiver.example.com:8080 \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY
```

## Configuration

### Required Settings

| Parameter | Description |
|-----------|-------------|
| `receiver.url` | URL of ByteFreezer receiver webhook endpoint |
| `controlService.url` | Control service URL |
| `controlService.apiKey` | API key for authentication |

### UDP Ports

Configure UDP ports based on your control service plugin configuration:

```yaml
udp:
  enabled: true
  ports:
    - port: 5514
      name: syslog
    - port: 514
      name: syslog-priv
    - port: 1514
      name: custom
  service:
    type: LoadBalancer
    annotations:
      # AWS NLB example
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

### All Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `receiver.url` | Receiver webhook URL | `""` |
| `controlService.url` | Control service URL | `""` |
| `controlService.apiKey` | API key | `""` |
| `controlService.existingSecret` | Use existing secret | `""` |
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `ghcr.io/bytefreezer/bytefreezer-proxy` |
| `image.tag` | Image tag | Chart appVersion |
| `udp.enabled` | Enable UDP service | `true` |
| `udp.ports` | List of UDP ports | `[{port: 5514, name: syslog}]` |
| `udp.service.type` | UDP service type | `LoadBalancer` |
| `webhook.enabled` | Enable webhook listener | `false` |
| `webhook.port` | Webhook port | `8080` |
| `batching.maxLines` | Max lines per batch | `10000` |
| `batching.maxBytes` | Max bytes per batch | `10485760` |
| `batching.timeoutSeconds` | Batch timeout | `30` |
| `spooling.enabled` | Enable local disk spooling | `true` |
| `spooling.maxSizeBytes` | Max spool size | `1073741824` |
| `healthReporting.enabled` | Report health to control | `true` |
| `monitoring.enabled` | Enable metrics | `false` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `256Mi` |
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `1Gi` |

## Examples

### Multi-Site Deployment

Deploy proxies at multiple sites, all forwarding to central receiver:

**Site A (us-east):**
```bash
helm install proxy-us-east ./proxy \
  --namespace site-us-east \
  --set receiver.url=https://receiver.central.example.com:8080 \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY \
  --set udp.ports[0].port=514 \
  --set udp.ports[0].name=syslog
```

**Site B (eu-west):**
```bash
helm install proxy-eu-west ./proxy \
  --namespace site-eu-west \
  --set receiver.url=https://receiver.central.example.com:8080 \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY \
  --set udp.ports[0].port=514 \
  --set udp.ports[0].name=syslog
```

### High Availability

```bash
helm install proxy ./proxy \
  --set replicaCount=3 \
  --set receiver.url=https://receiver.example.com:8080 \
  --set controlService.url=https://api.bytefreezer.com \
  --set controlService.apiKey=YOUR_API_KEY \
  --set resources.requests.cpu=500m \
  --set resources.requests.memory=512Mi
```

### Using Values File

Create `my-values.yaml`:

```yaml
receiver:
  url: https://receiver.example.com:8080

controlService:
  url: https://api.bytefreezer.com
  apiKey: YOUR_API_KEY

replicaCount: 2

udp:
  ports:
    - port: 514
      name: syslog
    - port: 5514
      name: syslog-alt

resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

Install:
```bash
helm install proxy ./proxy -f my-values.yaml
```

## Troubleshooting

### Check Status

```bash
kubectl get pods -l app.kubernetes.io/name=proxy
kubectl logs -l app.kubernetes.io/name=proxy
```

### Verify UDP Service

```bash
kubectl get svc -l app.kubernetes.io/name=proxy
```

### Test Connectivity

```bash
# Get LoadBalancer IP
LB_IP=$(kubectl get svc proxy-udp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Send test syslog message
echo "<14>Test message" | nc -u $LB_IP 5514
```

## Uninstall

```bash
helm uninstall proxy
```
