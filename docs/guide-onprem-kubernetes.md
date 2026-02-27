# How to Deploy ByteFreezer On-Prem with Kubernetes (Helm)

Deploy the complete ByteFreezer processing stack to a Kubernetes cluster using Helm charts.
Control plane runs on bytefreezer.com. Processing, storage, and proxy are self-hosted in your cluster.

**Image tag:** `v1.0.0-rc.0225b`

## What You Need

- A Kubernetes cluster (k3s, k8s, EKS, AKS, GKE, etc.)
- `kubectl` configured and pointing to your cluster
- Helm 3.x installed
- Network access from cluster to api.bytefreezer.com on HTTPS (control API)
- MetalLB installed (for LoadBalancer services on bare-metal/k3s)
- A web browser
- (Sub-version B only) A Linux host for edge proxy ("tiny")

## Architecture

### Version A: Everything in Kubernetes

```
Kubernetes Cluster
+--------------------------------------------------+
| +----------+    +----------+     +-------+       |
| | fakedata |--->|  Proxy   |---->|Receiver|      |
| +----------+    +----------+     +---+---+       |
|                                      |           |
|                                 +----+----+      |
|                                 |  MinIO  |      |
|                                 +----+----+      |
|                                      |           |
|                                 +----+----+      |
|                                 |  Piper  |      |
|                                 +----+----+      |
|                                      |           |
|                                 +----+----+      |
|                                 | Packer  |      |
|                                 +---------+      |
+--------------------------------------------------+
         |
         v
  bytefreezer.com (control plane)
```

### Version B: Proxy on Tiny, Stack in Kubernetes

```
tiny                           Kubernetes Cluster
+----------+    UDP            +--------------------------------------------------+
| fakedata |--->+--------+     | +----------+     +-------+                       |
+----------+   | Proxy  |---->| | Receiver |     | MinIO |                       |
               +--------+     | +----+-----+     +---+---+                       |
                               |      |               |                           |
                               | +----+----+     +----+----+     +---------+     |
                               | |  Piper  |     |  intake |     | Packer  |     |
                               | +----+----+     |  piper  |     +----+----+     |
                               |      |          |  packer |          |          |
                               |      +--------->|  geoip  |<--------+          |
                               +--------------------------------------------------+
```

---

## Phase 1: Create Account on bytefreezer.com

### Step 1 — Log in and create account

Open https://bytefreezer.com. Log in as system administrator.

Navigate to **Accounts** and create:

| Field | Value |
|-------|-------|
| Name | `test-onprem-k8s` |
| Email | your email |
| Deployment Type | `on_prem` |

Copy the **Account ID** and **API Key** (shown only once).

**Verify:** Account appears in the Accounts list.

---

## Phase 2: Deploy Processing Stack

### Step 2 — Get the Helm charts

```bash
# Clone the installer repo
git clone https://github.com/bytefreezer/installer.git
cd installer/helm
```

### Step 3 — Create namespace

```bash
kubectl create namespace bytefreezer
```

### Step 4 — Create values file for processing stack

Create `stack-values.yaml`:

```yaml
global:
  deploymentType: "on_prem"

# Bundled MinIO for storage
minio:
  enabled: true
  rootUser: "minioadmin"
  rootPassword: "minioadmin"
  persistence:
    enabled: true
    size: 20Gi
  createBuckets: true

# S3 credentials (match MinIO)
s3:
  endpoint: "bytefreezer-minio:9000"
  region: "us-east-1"
  accessKey: "minioadmin"
  secretKey: "minioadmin"
  useSSL: false

# Control service (bytefreezer.com)
controlService:
  enabled: true
  url: "https://api.bytefreezer.com"
  apiKey: "YOUR_API_KEY_HERE"

# Receiver
receiver:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-receiver
    tag: "v1.0.0-rc.0225b"
  webhookService:
    enabled: true
    type: LoadBalancer
    port: 8080
    annotations:
      metallb.universe.tf/address-pool: "default"

# Piper
piper:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-piper
    tag: "v1.0.0-rc.0225b"

# Packer
packer:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-packer
    tag: "v1.0.0-rc.0225b"
```

Replace `YOUR_API_KEY_HERE` with the key from Step 1.

### Step 5 — Install processing stack

```bash
helm install bytefreezer ./bytefreezer \
  -n bytefreezer \
  -f stack-values.yaml
```

### Step 6 — Verify pods are running

```bash
kubectl get pods -n bytefreezer
```

**Expected:** All pods should reach Running/Ready state.

| Pod | Status |
|-----|--------|
| bytefreezer-receiver-* | Running |
| bytefreezer-piper-* | Running |
| bytefreezer-packer-* | Running |
| bytefreezer-minio-* | Running |

```bash
# Check logs for registration
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver --tail 20
kubectl logs -n bytefreezer -l app.kubernetes.io/component=piper --tail 20
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer --tail 20
```

**Verify:** Each service logs "Registered with control service" or "Health report sent successfully".

### Step 7 — Get receiver webhook URL

```bash
kubectl get svc -n bytefreezer
```

Note the receiver webhook service's external IP or ClusterIP. You'll need this for the proxy.

For LoadBalancer:
```bash
RECEIVER_URL=$(kubectl get svc bytefreezer-receiver-webhook -n bytefreezer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Receiver URL: http://${RECEIVER_URL}:8080"
```

For ClusterIP (proxy in same cluster):
```bash
echo "Receiver URL: http://bytefreezer-receiver:8080"
```

### Step 8 — Verify services on dashboard

On bytefreezer.com, go to **Service Status**.

**Verify:** receiver, piper, packer appear under `test-onprem-k8s` account with Healthy status.

### Step 9 — Check MinIO

Port-forward to access MinIO console:

```bash
kubectl port-forward -n bytefreezer svc/bytefreezer-minio 9001:9001
```

Open http://localhost:9001. Login: `minioadmin` / `minioadmin`.

**Verify:** Buckets exist: `bytefreezer-intake`, `bytefreezer-piper`, `packer`, `bytefreezer-geoip`.

---

## Phase 3A: Deploy Proxy in Kubernetes

### Step 10A — Create proxy values file

Create `proxy-values.yaml`:

```yaml
receiver:
  url: "http://bytefreezer-receiver:8080"

controlService:
  url: "https://api.bytefreezer.com"
  accountId: "YOUR_ACCOUNT_ID_HERE"
  bearerToken: "YOUR_API_KEY_HERE"

replicaCount: 1

image:
  repository: ghcr.io/bytefreezer/bytefreezer-proxy
  tag: "v1.0.0-rc.0225b"

hostNetwork: true
nodeName: ""

udp:
  enabled: true
  ports:
    - port: 5514
      name: syslog
```

Replace `YOUR_ACCOUNT_ID_HERE` and `YOUR_API_KEY_HERE`.

If using `hostNetwork: false`, use a LoadBalancer service with MetalLB:

```yaml
hostNetwork: false
udp:
  enabled: true
  ports:
    - port: 5514
      name: syslog
  service:
    type: LoadBalancer
    annotations:
      metallb.universe.tf/address-pool: "default"
```

### Step 11A — Install proxy

```bash
helm install proxy ./proxy \
  -n bytefreezer \
  -f proxy-values.yaml
```

### Step 12A — Verify proxy

```bash
kubectl get pods -n bytefreezer -l app.kubernetes.io/name=proxy
kubectl logs -n bytefreezer -l app.kubernetes.io/name=proxy --tail 20
```

**Verify:** Proxy pod is Running. Logs show "Registered with control service".

On bytefreezer.com **Service Status**: proxy appears with Healthy status.

**Get proxy address for fakedata:**

If `hostNetwork: true`:
```bash
PROXY_IP=$(kubectl get pod -n bytefreezer -l app.kubernetes.io/name=proxy -o jsonpath='{.items[0].status.hostIP}')
echo "Proxy IP: ${PROXY_IP}"
```

If LoadBalancer:
```bash
PROXY_IP=$(kubectl get svc -n bytefreezer proxy-udp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Proxy IP: ${PROXY_IP}"
```

Skip to **Phase 4**.

---

## Phase 3B: Deploy Proxy on Tiny (Sub-version)

Use this if you want the proxy running outside the cluster (edge deployment pattern).

### Step 10B — Get receiver external URL

The receiver needs to be accessible from tiny. If you used LoadBalancer:

```bash
RECEIVER_IP=$(kubectl get svc bytefreezer-receiver-webhook -n bytefreezer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Receiver URL: http://${RECEIVER_IP}:8080"
```

If using NodePort or no LoadBalancer, use the node IP + NodePort.

**Verify:** From tiny, test connectivity:
```bash
curl -s http://${RECEIVER_IP}:8080
# Should get a response (even if error, confirms network path)
```

### Step 11B — Deploy proxy on tiny via Docker

SSH to tiny:

```bash
ssh tiny
mkdir -p ~/bytefreezer-proxy/config
cd ~/bytefreezer-proxy
```

Create `docker-compose.yml`:

```bash
cat > docker-compose.yml << 'EOF'
services:
  proxy:
    image: ghcr.io/bytefreezer/bytefreezer-proxy:v1.0.0-rc.0225b
    container_name: bytefreezer-proxy
    ports:
      - "8008:8008"
      - "5514:5514/udp"
    environment:
      PROXY_CONTROL_SERVICE_API_KEY: ${CONTROL_API_KEY}
    volumes:
      - ./config/proxy.yaml:/etc/bytefreezer/config.yaml:ro
      - proxy-spool:/var/spool/bytefreezer-proxy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8008/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

volumes:
  proxy-spool:
EOF
```

Create `.env`:

```bash
cat > .env << 'EOF'
CONTROL_API_KEY=YOUR_API_KEY_HERE
EOF
```

Create `config/proxy.yaml` (replace `RECEIVER_URL` with the LoadBalancer IP from Step 10B):

```bash
cat > config/proxy.yaml << 'EOF'
app:
  name: "bytefreezer-proxy"
  version: "1.0.0"

server:
  api_port: 8008

receiver:
  url: "http://RECEIVER_IP:8080"

control_service:
  enabled: true
  control_url: "https://api.bytefreezer.com"
  timeout_seconds: 30

udp:
  enabled: true
  ports:
    - port: 5514
      name: syslog

batching:
  enabled: true
  max_lines: 10000
  max_bytes: 10485760
  timeout_seconds: 30
  compression_enabled: true
  compression_level: 6

spooling:
  enabled: true
  directory: "/var/spool/bytefreezer-proxy"
  max_size_bytes: 1073741824
  retry_attempts: 3
  retry_interval_seconds: 60

health_reporting:
  enabled: true
  report_interval: 30
  timeout_seconds: 10
  register_on_startup: true
EOF
```

Start:

```bash
docker compose up -d
docker compose ps   # Should show healthy
docker compose logs proxy | head -20
```

**Verify:** Proxy appears on bytefreezer.com Service Status page.

`PROXY_IP` for fakedata = tiny's IP address.

---

## Phase 4: Configure Dataset

### Step 13 — Create tenant

On bytefreezer.com, navigate to **Tenants** (under `test-onprem-k8s` account):

| Field | Value |
|-------|-------|
| Name | `demo` |

### Step 14 — Create dataset

Navigate to **Datasets** (under `demo` tenant):

| Field | Value |
|-------|-------|
| Name | `syslog-test` |
| Active | Yes |

Configure:
- **Input:** syslog, port `5514`
- **Output S3:**
  - Endpoint: `bytefreezer-minio:9000` (from packer's perspective in the cluster)
  - Bucket: `packer`
  - Access Key: `minioadmin`
  - Secret Key: `minioadmin`
  - SSL: off
  - Region: `us-east-1`

### Step 15 — Assign to proxy

Edit the dataset. Set **Assigned Proxy** to the proxy instance.

**Verify:** Dataset shows assigned proxy ID.

Wait 1-2 minutes for config sync.

---

## Phase 5: Generate Test Data and Verify

### Step 16 — Run fakedata

**If proxy is in Kubernetes (Version A):**

```bash
kubectl run fakedata --rm -it \
  --image=ghcr.io/bytefreezer/bytefreezer-fakedata:latest \
  -n bytefreezer \
  --restart=Never \
  -- syslog --host ${PROXY_IP} --port 5514 --rate 10
```

Or deploy as a pod:

```bash
cat <<'EOF' | kubectl apply -n bytefreezer -f -
apiVersion: v1
kind: Pod
metadata:
  name: fakedata
spec:
  hostNetwork: true
  containers:
  - name: fakedata
    image: ghcr.io/bytefreezer/bytefreezer-fakedata:latest
    command: ["/bytefreezer-fakedata", "syslog", "--host", "PROXY_IP_HERE", "--port", "5514", "--rate", "10"]
  restartPolicy: Always
EOF
```

Replace `PROXY_IP_HERE` with the proxy IP from Phase 3A.

**If proxy is on tiny (Version B):**

On tiny:

```bash
docker run --rm --network host \
  ghcr.io/bytefreezer/bytefreezer-fakedata:latest \
  syslog --host 127.0.0.1 --port 5514 --rate 10
```

### Step 17 — Verify proxy receives data

```bash
# Version A (k8s)
kubectl logs -n bytefreezer -l app.kubernetes.io/name=proxy --tail 20

# Version B (tiny)
docker compose logs proxy --tail 20
```

**Verify:** Logs show batch activity, forwarding to receiver.

### Step 18 — Verify receiver stores to S3

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver --tail 20
```

**Verify in MinIO** (port-forward if needed):

```bash
kubectl port-forward -n bytefreezer svc/bytefreezer-minio 9001:9001
```

Open http://localhost:9001 → `bytefreezer-intake` bucket. Files appear with `.jsonl.snappy` extension.

### Step 19 — Verify piper processes

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=piper --tail 20
```

**Verify:** `bytefreezer-piper` bucket in MinIO has `.jsonl` files.

### Step 20 — Verify packer produces parquet

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer --tail 20
```

**Verify:** `packer` bucket in MinIO has `.parquet` files.

### Step 21 — Check bytefreezer.com dashboard

**Statistics page:**
- Events flowing through all stages
- All service cards active

**Activity page:**
- Piper processing entries
- Packer accumulation entries

**Service Status page:**
- All services Healthy

**Query page:**
- Run query against `syslog-test` dataset
- Returns rows with fakedata fields

**Verify:** Data visible end-to-end from fakedata to parquet query results.

---

## Phase 6: Explore Features

### Step 22 — Add transformations

Go to **Datasets** → `syslog-test` → **Pipeline** tab.

Add:
- **Rename:** `source_ip` → `src`
- **Add field:** `cluster` = `"k8s-test"`

Save. Wait for piper config refresh (up to 5 minutes).

**Verify:** New events in query have `src` and `cluster` fields.

### Step 23 — Test dataset pause

Pause the dataset on bytefreezer.com.

**Verify:**
- Proxy stops forwarding (check logs)
- Statistics stop increasing

Resume. **Verify:** Data flow resumes.

### Step 24 — Verify parquet output with transformations

After packer cycle completes:

**Verify:** Query returns events with transformed fields in parquet data.

---

## Phase 7: Cleanup

### Stop fakedata

```bash
# Version A
kubectl delete pod fakedata -n bytefreezer

# Version B
# Ctrl+C the docker run command
```

### Uninstall Helm releases

```bash
helm uninstall proxy -n bytefreezer
helm uninstall bytefreezer -n bytefreezer
```

### Delete PVCs

```bash
kubectl delete pvc -n bytefreezer --all
```

### Delete namespace

```bash
kubectl delete namespace bytefreezer
```

### Stop proxy on tiny (Version B only)

```bash
ssh tiny
cd ~/bytefreezer-proxy
docker compose down -v
```

### Remove test account (optional)

On bytefreezer.com, delete the `test-onprem-k8s` account.

---

## Troubleshooting

**Pods stuck in Pending:**
```bash
kubectl describe pod <pod-name> -n bytefreezer
# Check: insufficient resources, PVC not binding, image pull errors
```

**Image pull errors:**
```bash
kubectl get events -n bytefreezer --sort-by='.lastTimestamp'
# May need imagePullSecrets for ghcr.io
# For public images, verify tag exists:
# docker pull ghcr.io/bytefreezer/bytefreezer-receiver:v1.0.0-rc.0225b
```

**Services not registering:**
```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver | grep -i control
# Check API key is correct
# Check cluster DNS can resolve api.bytefreezer.com
kubectl exec -n bytefreezer deploy/bytefreezer-receiver -- wget -qO- https://api.bytefreezer.com/api/v1/health
```

**MinIO not accessible:**
```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=minio
kubectl get pvc -n bytefreezer
# Check PVC is bound and storage class exists
```

**Proxy cannot reach receiver (Version B):**
```bash
# From tiny:
curl -v http://RECEIVER_IP:8080
# Check LoadBalancer IP is assigned
# Check firewall rules between tiny and cluster
```

**No data in MinIO buckets:**
```bash
# Check each service in order:
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver | grep -i "error\|s3"
kubectl logs -n bytefreezer -l app.kubernetes.io/component=piper | grep -i "error\|process"
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer | grep -i "error\|parquet"
```

**UDP not working (hostNetwork):**
```bash
# Verify the node accepts UDP on the port
ss -ulnp | grep 5514
# Verify sysctl settings for UDP buffers
sysctl net.core.rmem_max
```
