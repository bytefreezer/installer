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

Create `proxy-values.yaml`:

```yaml
receiver:
  url: "https://receiver.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"
```

Install:

```bash
helm install proxy ./proxy -n bytefreezer -f proxy-values.yaml
```

## Configuration

### Required Settings

| Parameter | Description |
|-----------|-------------|
| `receiver.url` | URL of ByteFreezer receiver webhook endpoint |
| `controlService.url` | Control service URL |
| `controlService.accountId` | Account ID for config polling |
| `controlService.bearerToken` | API key for authentication |

### Network Modes

The proxy supports three network modes for UDP traffic:

#### Option 1: hostNetwork (Direct Node Access)

Pod uses the host's network namespace. UDP ports bind directly to the node's IP address.

Create `proxy-hostnetwork.yaml`:

```yaml
receiver:
  url: "https://receiver.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"

hostNetwork: true
nodeName: "worker-1"

udp:
  enabled: true
  ports:
    - port: 514
      name: syslog
```

```bash
helm install proxy ./proxy -n bytefreezer -f proxy-hostnetwork.yaml
```

**Pros:**
- Lowest latency, no NAT overhead
- Simple - clients send directly to node IP
- Works without LoadBalancer support

**Cons:**
- Pod tied to specific node
- Port conflicts if other services use same ports
- Only one proxy per node

**Use when:** On-prem deployments, edge locations, bare-metal

#### Option 2: LoadBalancer (MetalLB / Cloud LB)

Pod uses cluster networking with external LoadBalancer for UDP traffic.

Create `proxy-loadbalancer.yaml`:

```yaml
receiver:
  url: "https://receiver.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"

hostNetwork: false

udp:
  enabled: true
  ports:
    - port: 514
      name: syslog
  service:
    type: LoadBalancer
    annotations:
      metallb.universe.tf/loadBalancerIPs: "192.168.86.139"
```

```bash
helm install proxy ./proxy -n bytefreezer -f proxy-loadbalancer.yaml
```

**Pros:**
- Pod can run on any node
- Kubernetes manages scheduling
- Can have multiple replicas behind LB

**Cons:**
- Requires LoadBalancer support (MetalLB, cloud provider)
- Slightly higher latency due to NAT

**Use when:** Cloud deployments, clusters with MetalLB

#### Option 3: ClusterIP (Internal Only)

Pod only accessible within the cluster.

Create `proxy-internal.yaml`:

```yaml
receiver:
  url: "https://receiver.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"

hostNetwork: false

udp:
  enabled: true
  service:
    type: ClusterIP
```

```bash
helm install proxy ./proxy -n bytefreezer -f proxy-internal.yaml
```

**Use when:** Proxy receives data from other pods in the cluster

### Node Selection

When using `hostNetwork: true`, you typically want to control which node the proxy runs on:

**Specific node by name:**

```yaml
nodeName: "tp4"
```

**By node label:**

```bash
# First label the node
kubectl label node tp4 bytefreezer-proxy=true
```

```yaml
nodeSelector:
  bytefreezer-proxy: "true"
```

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

**Site A (us-east) - `proxy-us-east.yaml`:**

```yaml
receiver:
  url: "https://receiver.central.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"

hostNetwork: true
nodeName: "edge-us-east-1"

udp:
  enabled: true
  ports:
    - port: 514
      name: syslog
```

```bash
helm install proxy-us-east ./proxy -n site-us-east -f proxy-us-east.yaml
```

**Site B (eu-west) - `proxy-eu-west.yaml`:**

```yaml
receiver:
  url: "https://receiver.central.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"

hostNetwork: true
nodeName: "edge-eu-west-1"

udp:
  enabled: true
  ports:
    - port: 514
      name: syslog
```

```bash
helm install proxy-eu-west ./proxy -n site-eu-west -f proxy-eu-west.yaml
```

### High Availability

Create `proxy-ha.yaml`:

```yaml
receiver:
  url: "https://receiver.example.com"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "your-account-id"
  bearerToken: "your-api-key"

replicaCount: 3
hostNetwork: false

udp:
  enabled: true
  ports:
    - port: 514
      name: syslog
  service:
    type: LoadBalancer

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

```bash
helm install proxy ./proxy -n bytefreezer -f proxy-ha.yaml
```

## UDP Buffer Tuning

For high-throughput UDP sources (syslog, sFlow, NetFlow, etc.), the kernel must allow large socket buffers. The proxy requests 8MB buffers by default and will report warnings in the UI if the kernel limits them.

### Required Kernel Settings

On each node running the proxy:

```bash
# Increase UDP buffer limits
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.rmem_default=8388608
sudo sysctl -w net.core.netdev_max_backlog=50000

# Make persistent
cat <<EOF | sudo tee /etc/sysctl.d/99-bytefreezer.conf
net.core.rmem_max=16777216
net.core.rmem_default=8388608
net.core.netdev_max_backlog=50000
EOF
```

### Per-Dataset Buffer Size

The `read_buffer_size` is configured per dataset in Control (defaults to 8MB). If you see "UDP socket drops" warnings:

1. Verify kernel settings are applied (`sysctl net.core.rmem_max`)
2. Increase `read_buffer_size` in the dataset configuration via Control
3. Restart the proxy to apply changes

### Verifying Buffer Settings

```bash
# Check current kernel limits
sysctl net.core.rmem_max net.core.rmem_default

# Check proxy logs for buffer warnings
kubectl logs -l app.kubernetes.io/name=proxy | grep -i buffer
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


helm install proxy-tp5 /home/andrew/workspace/bytefreezer/installer/helm/proxy \
    -n bytefreezer \
    --create-namespace \
    -f proxy-tp5.yaml

  Or to upgrade if already installed:

  helm upgrade proxy-tp5 /home/andrew/workspace/bytefreezer/installer/helm/proxy \
    -n bytefreezer \
    -f proxy-tp5.yaml

 Check status:

  kubectl get pods -n bytefreezer -l app.kubernetes.io/name=proxy
  kubectl logs -n bytefreezer -l app.kubernetes.io/name=proxy

