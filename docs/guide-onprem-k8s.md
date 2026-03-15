# ByteFreezer On-Prem Deployment (Kubernetes)

Deploy the complete ByteFreezer processing stack to a Kubernetes cluster using Helm charts. Control plane runs on bytefreezer.com for coordination. Processing, storage, and proxy are self-hosted in your cluster -- your data stays on your infrastructure.

**Objective:** End-to-end test of the full on-prem stack on Kubernetes. Verify all services register, data flows from proxy through receiver/piper/packer, and parquet files land in your cluster's MinIO. To query your parquet data, use the [example query project](https://github.com/bytefreezer/query-example) or build your own using AI and [ByteFreezer MCP](https://github.com/bytefreezer/mcp).

**Time to complete:** 20-30 minutes (manual), 10-15 minutes (Claude + MCP).

> **Do not send sensitive or production data to bytefreezer.com.** The control plane on bytefreezer.com is a shared test platform. Your data stays in your cluster, but the control plane is not secured for production use.

## Contents

- [What You Need](#what-you-need)
- [Architecture](#architecture)
- [Method A: Step-by-Step Manual](#method-a-step-by-step-manual)
  - [Phase 1: Create Account](#phase-1-create-account-on-bytefreezercom)
  - [Phase 2: Deploy Processing Stack](#phase-2-deploy-processing-stack)
  - [Phase 3A: Deploy Proxy in Kubernetes](#phase-3a-deploy-proxy-in-kubernetes)
  - [Phase 3B: Deploy Proxy on Testhost](#phase-3b-deploy-proxy-on-testhost-edge-proxy)
  - [Phase 4: Configure Dataset](#phase-4-configure-dataset)
  - [Phase 5: Generate Test Data and Verify](#phase-5-generate-test-data-and-verify)
  - [Phase 6: Explore Features](#phase-6-explore-features)
- [Method B: Deploy with Claude + MCP](#method-b-deploy-with-claude--mcp)
- [Understanding the Data Pipeline](#understanding-the-data-pipeline)
- [What You Can See on the Dashboard](#what-you-can-see-on-the-dashboard)
  - [Service Status Page](#service-status-page)
  - [Statistics Page](#statistics-page)
  - [Activity Page](#activity-page)
  - [Datasets Page](#datasets-page)
  - [Audit Log](#audit-log)
- [Connector](#connector)
  - [Web UI (Interactive Mode)](#web-ui-interactive-mode)
  - [Modes](#modes)
  - [SQL Queries](#sql-queries)
  - [Destinations](#destinations)
  - [Adding Custom Destinations](#adding-custom-destinations)
  - [Configuration Reference](#connector-configuration-reference)
- [What You Can Do Next](#what-you-can-do-next)
  - [Play with Transformations](#play-with-transformations)
  - [Enable GeoIP Enrichment](#enable-geoip-enrichment)
  - [Try Different Data Sources](#try-different-data-sources)
- [Demo vs. Production: What's Different](#demo-vs-production-whats-different)
  - [Data Sovereignty Summary](#data-sovereignty-summary)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

---

## What You Need

**Both methods:**

- A Kubernetes cluster (k3s, k8s, EKS, AKS, GKE, etc.)
- `kubectl` configured and pointing to your cluster
- Helm 3.x installed
- Network access from cluster to api.bytefreezer.com on HTTPS (control API)
- MetalLB installed (for LoadBalancer services on bare-metal/k3s)
- A web browser
- (Version B only) A Linux host with Docker for edge proxy ("testhost")

**Additional for Method B (Claude + MCP):**

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on your workstation
- SSH access from your workstation to testhost (for edge proxy variant only)

---

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

### Version B: Proxy on Testhost, Stack in Kubernetes

```
testhost                           Kubernetes Cluster
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

## Choose Your Deployment Method

- **[Method A: Step-by-Step Manual](#method-a-step-by-step-manual)** -- Follow the instructions yourself using the dashboard, kubectl, and helm.
- **[Method B: Deploy with Claude + MCP](#method-b-deploy-with-claude--mcp)** -- Tell Claude what you want in plain English; it handles the API calls, Helm values generation, and deployment.

---

# Method A: Step-by-Step Manual

Follow each step yourself using the bytefreezer.com dashboard, kubectl, and helm.

## Phase 1: Create Account on bytefreezer.com

### Step 1 -- Log in and create account

Open https://bytefreezer.com. Log in as system administrator.

Navigate to **Accounts** and create:

| Field | Value |
|-------|-------|
| Name | `test-onprem-k8s` |
| Email | your email |
| Deployment Type | `on_prem` |

Copy the **Account ID** and **API Key** (shown only once).

**Verify:** Account appears in the Accounts list.

## Phase 2: Deploy Processing Stack

### Step 2 -- Get the Helm charts

```bash
# Clone the installer repo
git clone https://github.com/bytefreezer/installer.git
cd installer/helm
```

### Step 3 -- Create namespace

```bash
kubectl create namespace bytefreezer
```

### Step 4 -- Create values file for processing stack

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
    tag: "latest"
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
    tag: "latest"

# Packer
packer:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-packer
    tag: "latest"

# Connector - reads parquet output, exports to external systems
connector:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-connector
    tag: "latest"
```

Replace `YOUR_API_KEY_HERE` with the key from Step 1.

### Step 5 -- Install processing stack

```bash
helm install bytefreezer ./bytefreezer \
  -n bytefreezer \
  -f stack-values.yaml
```

### Step 6 -- Verify pods are running

```bash
kubectl get pods -n bytefreezer
```

**Expected:** All pods should reach Running/Ready state.

| Pod | Status |
|-----|--------|
| bytefreezer-receiver-* | Running |
| bytefreezer-piper-* | Running |
| bytefreezer-packer-* | Running |
| bytefreezer-connector-* | Running |
| bytefreezer-minio-* | Running |

```bash
# Check logs for registration
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver --tail 20
kubectl logs -n bytefreezer -l app.kubernetes.io/component=piper --tail 20
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer --tail 20
```

**Verify:** Each service logs "Registered with control service" or "Health report sent successfully".

### Step 7 -- Get receiver webhook URL

```bash
kubectl get svc -n bytefreezer
```

Note the receiver webhook service's external IP or ClusterIP. You will need this for the proxy.

For LoadBalancer:
```bash
RECEIVER_URL=$(kubectl get svc bytefreezer-receiver-webhook -n bytefreezer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Receiver URL: http://${RECEIVER_URL}:8080"
```

For ClusterIP (proxy in same cluster):
```bash
echo "Receiver URL: http://bytefreezer-receiver:8080"
```

### Step 8 -- Verify services on dashboard

On bytefreezer.com, go to **Service Status**.

**Verify:** receiver, piper, packer appear under `test-onprem-k8s` account with Healthy status.

### Step 9 -- Check MinIO

Port-forward to access MinIO console:

```bash
kubectl port-forward -n bytefreezer svc/bytefreezer-minio 9001:9001
```

Open http://localhost:9001. Login: `minioadmin` / `minioadmin`.

**Verify:** Buckets exist: `intake`, `piper`, `packer`, `geoip`.

## Phase 3A: Deploy Proxy in Kubernetes

### Step 10A -- Create proxy values file

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
  tag: "latest"

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

### Step 11A -- Install proxy

```bash
helm install proxy ./proxy \
  -n bytefreezer \
  -f proxy-values.yaml
```

### Step 12A -- Verify proxy

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

## Phase 3B: Deploy Proxy on Testhost (Edge Proxy)

Use this if you want the proxy running outside the cluster (edge deployment pattern).

### Step 10B -- Get receiver external URL

The receiver needs to be accessible from testhost. If you used LoadBalancer:

```bash
RECEIVER_IP=$(kubectl get svc bytefreezer-receiver-webhook -n bytefreezer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Receiver URL: http://${RECEIVER_IP}:8080"
```

If using NodePort or no LoadBalancer, use the node IP + NodePort.

**Verify:** From testhost, test connectivity:
```bash
curl -s http://${RECEIVER_IP}:8080
# Should get a response (even if error, confirms network path)
```

### Step 11B -- Deploy proxy on testhost via Docker

SSH to testhost:

```bash
ssh testhost
mkdir -p ~/bytefreezer-proxy/config
cd ~/bytefreezer-proxy
```

Create `docker-compose.yml`:

```bash
cat > docker-compose.yml << 'EOF'
services:
  proxy:
    image: ghcr.io/bytefreezer/bytefreezer-proxy:latest
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
      test: ["CMD-SHELL", "wget -qO- http://localhost:8008/api/v1/health || exit 1"]
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

Create `config/proxy.yaml` (replace `RECEIVER_IP` with the LoadBalancer IP from Step 10B):

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

`PROXY_IP` for fakedata = testhost's IP address.

## Phase 4: Configure Dataset

### Step 13 -- Create tenant

On bytefreezer.com, navigate to **Tenants** (under `test-onprem-k8s` account):

| Field | Value |
|-------|-------|
| Name | `demo` |

### Step 14 -- Create dataset

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

### Step 15 -- Assign to proxy

Edit the dataset. Set **Assigned Proxy** to the proxy instance.

**Verify:** Dataset shows assigned proxy ID.

Wait 1-2 minutes for config sync.

## Phase 5: Generate Test Data and Verify

### Step 16 -- Run fakedata

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

**If proxy is on testhost (Version B):**

On testhost:

```bash
docker run --rm --network host \
  ghcr.io/bytefreezer/bytefreezer-fakedata:latest \
  syslog --host 127.0.0.1 --port 5514 --rate 10
```

### Step 17 -- Verify proxy receives data

```bash
# Version A (k8s)
kubectl logs -n bytefreezer -l app.kubernetes.io/name=proxy --tail 20

# Version B (testhost)
docker compose logs proxy --tail 20
```

**Verify:** Logs show batch activity, forwarding to receiver.

### Step 18 -- Verify receiver stores to S3

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver --tail 20
```

**Verify in MinIO** (port-forward if needed):

```bash
kubectl port-forward -n bytefreezer svc/bytefreezer-minio 9001:9001
```

Open http://localhost:9001 -> `intake` bucket. Files appear with `.jsonl.snappy` extension.

### Step 19 -- Verify piper processes

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=piper --tail 20
```

**Verify:** `piper` bucket in MinIO has `.jsonl` files.

### Step 20 -- Verify packer produces parquet

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer --tail 20
```

**Verify:** `packer` bucket in MinIO has `.parquet` files.

### Step 21 -- Check bytefreezer.com dashboard

**Statistics page:**
- Events flowing through all stages
- All service cards active

**Activity page:**
- Piper processing entries
- Packer accumulation entries

**Service Status page:**
- All services Healthy

**Connector UI** (`http://<your-host>:8090`):
- Run query against `syslog-test` dataset
- Returns rows with fakedata fields

**Verify:** Data visible end-to-end from fakedata to parquet query results.

## Phase 6: Explore Features

### Step 22 -- Add transformations

Go to **Datasets** -> `syslog-test` -> **Pipeline** tab.

Add:
- **Rename:** `source_ip` -> `src`
- **Add field:** `cluster` = `"k8s-test"`

Save. Wait for piper config refresh (up to 5 minutes).

**Verify:** New events in Connector have `src` and `cluster` fields.

### Step 23 -- Test dataset pause

Pause the dataset on bytefreezer.com.

**Verify:**
- Proxy stops forwarding (check logs)
- Statistics stop increasing

Resume. **Verify:** Data flow resumes.

### Step 24 -- Verify parquet output with transformations

After packer cycle completes:

**Verify:** Query returns events with transformed fields in parquet data.

---

# Method B: Deploy with Claude + MCP

Tell Claude what you want in plain English. Claude uses the ByteFreezer MCP tools to create resources on bytefreezer.com, generates Helm values, and runs kubectl/helm from your workstation to deploy to your cluster. No SSH needed for the in-cluster deployment; SSH is used only for the edge proxy variant.

## Claude + MCP Setup

### B1 -- Create a ByteFreezer Account

1. Go to [bytefreezer.com/register](https://bytefreezer.com/register)
2. Create your account with your email and password
3. Log in to the dashboard

### B2 -- Generate an API Key

1. In the dashboard, go to **Settings** -> **API Keys**
2. Click **Generate Key**
3. Copy the API key -- you will need it in the next step. It is shown only once.

### B3 -- Verify Cluster Access

Make sure `kubectl` and `helm` work from your workstation:

```bash
kubectl cluster-info
helm version
```

If you plan to deploy the proxy on a separate host (edge proxy variant), also set up SSH:

```bash
ssh-copy-id testhost
ssh testhost "hostname && docker --version"
```

### B4 -- Connect Claude to ByteFreezer MCP

Run this once to register the MCP server with Claude Code:

```bash
claude mcp add --transport http bytefreezer \
  https://mcp.bytefreezer.com/mcp \
  --header "Authorization: Bearer YOUR_API_KEY"
```

Replace `YOUR_API_KEY` with the API key from Step B2.

**Verify:**

```bash
claude mcp list
```

You should see `bytefreezer` in the list.

### B5 -- Verify MCP Connection

Start Claude Code and run a quick smoke test to confirm the MCP server is reachable and your API key works:

```
Use bf_health_check, bf_list_accounts, and bf_health_summary to verify MCP connectivity.
```

**Expected output:**

| Check | Expected |
|-------|----------|
| Health check | `status: ok`, `service: bytefreezer-control` |
| Health summary | Service counts for control, receiver, piper, packer |
| Accounts | Your account listed |

If any of these fail:
- **"MCP server not responding"** -- check `claude mcp list` shows `bytefreezer`
- **"Unauthorized"** -- your API key is wrong or expired; generate a new one in the dashboard
- **Empty account list** -- your API key may not be associated with an account

## Deploy with Claude

```
Your Workstation                    Remote
+------------------+
| Claude Code      |
|   |               |
|   +-- MCP --------|------> api.bytefreezer.com  (tenant, dataset, config)
|   |               |
|   +-- kubectl ----|------> k8s cluster           (helm install, pods, services)
|   |               |
|   +-- SSH --------|------> testhost              (edge proxy variant only)
+------------------+
```

### Option A: Everything in Kubernetes

Tell Claude what you want:

```
Use bf_runbook name=onprem-full-k8s to deploy a full on-prem ByteFreezer stack
to my Kubernetes cluster with Helm. Create a tenant "demo" and a syslog dataset
on port 5514 with testing=true and local_storage=true. Use bundled MinIO.
Deploy proxy in-cluster, start fakedata, and verify parquet output.
```

**What Claude does behind the scenes:**

1. `bf_whoami` — discovers account context
2. `bf_create_tenant` and `bf_create_dataset` — with full source+destination config
3. `bf_update_dataset` — enables testing mode
4. `bf_generate_helm_values` with `scenario=full` — generates values.yaml
5. Writes values.yaml, runs `helm install` for processing stack + proxy
6. Monitors pods with `kubectl get pods`, waits for Running/Ready
7. `bf_account_services` — verifies all services registered
8. Assigns dataset to proxy, deploys fakedata pod
9. Verifies parquet output via kubectl exec into MinIO pod
10. Runs connector batch query to confirm data is queryable

### Option B: Proxy on Edge Host, Stack in Kubernetes

```
Use bf_runbook name=onprem-full-k8s to deploy the ByteFreezer processing stack
(receiver, piper, packer, connector, minio) to my Kubernetes cluster with Helm,
and the proxy separately on <your-host> via Docker Compose. Create a tenant "demo"
and a syslog dataset on port 5514 with testing=true and local_storage=true. Wire
the proxy to the receiver LoadBalancer in Kubernetes. Start fakedata on <your-host>
and verify parquet output.
```

Claude uses `bf_generate_helm_values` for the cluster stack and `bf_generate_docker_compose` with `scenario=proxy` for the edge proxy, wiring the receiver URL from the Kubernetes LoadBalancer IP. It SSHs into the edge host to deploy the proxy.

## Verify with Claude

Ask Claude to check the pipeline:

```
Use bf_health_summary and bf_account_services to check all service health.
Then use bf_dataset_statistics and bf_dataset_parquet_files to verify data flow.
```

| Check | What Claude does |
|-------|-----------------|
| All services healthy | `bf_account_services` -- proxy, receiver, piper, packer all Healthy |
| Data flowing | `bf_dataset_statistics` -- events_in, events_out, bytes_processed increasing |
| Parquet output | `bf_dataset_parquet_files` -- lists `.parquet` files in packer bucket |

## Explore with Claude

### Transformations

```
Use bf_transformation_schema to show me the schema, then use bf_test_transformation
to test a transformation that renames source_ip to src and adds a field
cluster="k8s-test". If it looks good, use bf_activate_transformation to deploy it.
```

### Kill Switch

```
Use bf_update_dataset to pause the dataset, then use bf_get_proxy_config to verify
the proxy dropped it. After 30 seconds, use bf_update_dataset to resume it.
```

### Query Your Data

Parquet files are in MinIO inside your cluster. Use the [example query project](https://github.com/bytefreezer/query-example) or ask Claude:

```
Use bf_dataset_parquet_files to list my parquet files, then show me how to
query them in my Kubernetes MinIO.
```

### What Else Can Claude Do?

| Ask Claude to... | MCP tool to mention |
|---|---|
| Deploy full stack to Kubernetes | `bf_runbook name=onprem-full-k8s` |
| Deploy full stack via Docker Compose | `bf_runbook name=onprem-full-docker-compose` |
| Remove Kubernetes deployment | `bf_runbook name=onprem-k8s-cleanup` |
| Remove Docker Compose deployment | `bf_runbook name=onprem-cleanup` |
| Show dataset schema | `bf_transformation_schema` |
| Test a transformation | `bf_test_transformation` |
| Activate a transformation | `bf_activate_transformation` |
| Check service health | `bf_health_summary`, `bf_account_services` |
| List parquet files | `bf_dataset_parquet_files` |
| Pause/resume a dataset | `bf_update_dataset` |
| Show available filters | `bf_filter_catalog` |
| Generate systemd install script | `bf_generate_systemd` |

---

## Understanding the Data Pipeline

After a successful deployment, data flows through these stages:

```
Proxy → Receiver → Piper → Packer → Parquet (your MinIO)
                                         ↓
                                    Connector → Elasticsearch / Splunk / webhook / stdout
```

Each stage writes to a separate S3 bucket in your cluster's MinIO:

| Bucket | Contents | Stage |
|--------|----------|-------|
| `intake` | `.ndjson.gz` compressed batches | Receiver stores raw data from proxy |
| `piper` | `.ndjson` processed files | Piper applies transformations and writes output |
| `packer` | `.parquet` columnar files | Packer converts NDJSON to Parquet |

Parquet files are the final output of the processing pipeline. They are stored in a directory structure that enforces tenant and dataset isolation:

```
{tenant_id}/{dataset_id}/data/parquet/year=YYYY/month=MM/day=DD/hour=HH/{filename}.parquet
```

---

## What You Can See on the Dashboard

The dashboard at bytefreezer.com shows control plane data — service registrations, configuration, health status. It does **not** have direct access to your cluster's MinIO or parquet files.

### Service Status Page

Shows all registered services (proxy, receiver, piper, packer, connector) with:
- **Health status** — Healthy, Degraded, Starting, Unhealthy
- **Version** — which build each service is running
- **Metrics** — CPU, memory, disk, uptime
- **Last seen** — when the service last reported in

### Statistics Page

Shows pipeline throughput for your dataset:
- **Events received** — how many records the proxy has forwarded
- **Piper processing** — records transformed and written
- **Packer output** — parquet files produced, total rows, total size

### Activity Page

Shows recent processing events:
- Piper job runs (how many records processed per batch)
- Packer jobs (parquet files created, accumulation status)
- Errors and retries

### Datasets Page

Shows your dataset configuration, assigned proxy, and status. From here you can:
- **Pause/Resume** a dataset (paused datasets are removed from proxy config)
- **Edit** source, destination, and transformation config
- **Test** input and output connectivity

### Audit Log

Every action taken through the API or dashboard is recorded. This includes account/tenant/dataset operations, API key management, configuration changes, and service registrations. Useful for tracking what changed and when.

---

## Connector

The Connector is your "final mile" — it reads parquet files from your MinIO using DuckDB and exports data to external systems (Elasticsearch, Splunk, webhooks, etc.).

### Web UI (Interactive Mode)

Port-forward to access the connector web UI:

```bash
kubectl port-forward -n bytefreezer svc/bytefreezer-connector 8090:8090
```

Open `http://localhost:8090` in your browser.

The interactive mode lets you:
- Browse datasets and see available parquet files
- Write and test SQL queries against your data
- Preview query results
- Configure and test destinations
- Run one-off exports

### Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **interactive** (default) | Web UI at port 8090 | Exploration, ad-hoc queries, testing destinations |
| **batch** | Run a configured query once, export results, exit | One-time data exports, backfills |
| **watch** | Run the query on a timer, continuously exporting new data | Ongoing SIEM feed, streaming to Elasticsearch |

### SQL Queries

Use `PARQUET_PATH` as a placeholder — the connector replaces it with the actual S3 glob path for your dataset.

```sql
-- All records (limited)
SELECT * FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
LIMIT 100

-- Filter by time partition
SELECT * FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
WHERE year = 2026 AND month = 3 AND day = 5

-- Aggregate by hour
SELECT year, month, day, hour, COUNT(*) as count
FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
GROUP BY year, month, day, hour
ORDER BY year, month, day, hour

-- Filter specific fields
SELECT timestamp, source_ip, message
FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
WHERE severity >= 4
LIMIT 1000
```

### Destinations

Built-in destinations:

| Destination | Type | Description |
|-------------|------|-------------|
| **stdout** | `stdout` | JSON lines to stdout (default, useful for testing) |
| **Elasticsearch** | `elasticsearch` | Bulk API to Elasticsearch/OpenSearch |
| **Webhook** | `webhook` | Generic HTTP POST to any endpoint |

### Adding Custom Destinations

The connector has a plugin architecture. Create a new Go file in `destinations/` implementing the `Destination` interface. The `init()` function auto-registers it — no other changes needed. Ask Claude Code: "Add a Splunk HEC destination to the connector" and it will generate the code following the existing pattern.

### Connector Configuration Reference

Key fields in `config/connector.yaml`:

| Key | Required | Description |
|-----|----------|-------------|
| `control.url` | Yes | Control API URL (default: `https://api.bytefreezer.com`) |
| `control.api_key` | Yes | Your API key or service key |
| `control.account_id` | Yes | Your account ID |
| `query.tenant_id` | Batch/Watch | Tenant ID for the dataset to query |
| `query.dataset_id` | Batch/Watch | Dataset ID to query |
| `query.sql` | Batch/Watch | SQL query with `PARQUET_PATH` placeholder |
| `destination.type` | Batch/Watch | `stdout`, `elasticsearch`, or `webhook` |
| `destination.config` | Batch/Watch | Destination-specific config (see examples above) |
| `schedule.interval_seconds` | Watch | How often to poll for new data (default: 60) |
| `schedule.batch_size` | Watch | Records per batch sent to destination (default: 1000) |

---

## What You Can Do Next

### Play with Transformations

Go to **Datasets** → your dataset → **Pipeline** tab.

Transformations modify data as it flows through piper. Changes apply to new data only — existing parquet files are not reprocessed.

You can build transformations manually using the JSON examples below, or use the **Agent** tab next to the Pipeline tab. The AI agent knows your dataset schema, available filters, and current pipeline config — describe what you want in plain English and it will generate the transformation JSON for you.

Examples to try:

**Rename a field:**
```json
{
  "filters": [
    {
      "type": "rename_field",
      "config": { "from": "source_ip", "to": "src_ip" }
    }
  ]
}
```

**Add a static field:**
```json
{
  "filters": [
    {
      "type": "add_field",
      "config": { "field": "environment", "value": "demo" }
    }
  ]
}
```

**Drop a field:**
```json
{
  "filters": [
    {
      "type": "remove_field",
      "config": { "field": "raw_message" }
    }
  ]
}
```

**Filter events (drop matching records):**
```json
{
  "filters": [
    {
      "type": "drop",
      "config": { "condition": "action == 'deny'" }
    }
  ]
}
```

After saving a transformation, wait for the next piper cycle (up to 5 minutes). Then query the data in the Connector — new records will reflect the changes.

Use the **Test Transformation** button to preview changes against sample data before deploying.

### Enable GeoIP Enrichment

If a GeoIP database is available (MaxMind GeoLite2), piper can enrich IP address fields with geographic data.

Add a GeoIP filter to the transformation pipeline:
```json
{
  "type": "geoip",
  "config": { "field": "source_ip" }
}
```

New events will include `source_ip_geo_country`, `source_ip_geo_city`, `source_ip_geo_lat`, `source_ip_geo_lon`, etc.

### Try Different Data Sources

The proxy supports multiple input plugins. Create additional datasets with different source types:

| Plugin | Transport | Example Port | Use Case |
|--------|-----------|-------------|----------|
| `syslog` | UDP | 514, 5514 | System logs, network devices |
| `netflow` | UDP | 2055 | Network flow data (NetFlow v5/v9) |
| `sflow` | UDP | 6343 | sFlow v5/v6 network sampling |
| `ipfix` | UDP | 4739 | IPFIX (RFC 7011) flow data |
| `http` | TCP | 8080 | HTTP webhook / REST API ingestion |
| `kafka` | TCP | 9092 | Apache Kafka consumer |
| `sqs` | AWS API | — | AWS SQS queue consumer |
| `nats` | TCP | 4222 | NATS messaging subscriber |
| `ebpf` | UDP | 2056 | Kernel-level eBPF telemetry |

Each dataset gets its own port and plugin instance. The proxy manages them dynamically — no restart needed. Create the dataset, assign it to the proxy, and the plugin starts on the next config poll (30 seconds).

---

## Demo vs. Production: What's Different

### This Demo Environment

What you have now is a **test pipeline** designed to verify end-to-end data flow:

- **Fakedata** generates synthetic syslog events — not real data.
- **Testing mode** on the dataset bypasses packer accumulation thresholds so you see parquet files quickly (within minutes instead of the normal 20-minute or 128MB threshold).
- **All data stays in your cluster.** On-prem mode means receiver, piper, packer, and MinIO run in your Kubernetes cluster. The control plane on bytefreezer.com only handles configuration and health monitoring — it never sees your data.

### A Production Deployment

In production:

1. **Real data sources.** Replace fakedata with real syslog, netflow, or other inputs from your network devices and servers.

2. **Testing mode disabled.** Packer accumulates data to produce larger, more efficient parquet files (128MB or 20-minute batches).

3. **Connector in watch mode.** Configure the connector with your production destination (Elasticsearch, Splunk, webhook) and run it in watch mode for continuous data export. Only export the fields and events you need — this is where ByteFreezer reduces SIEM costs.

4. **Custom destinations.** Build connector plugins for your specific SIEM or analytics platform. The plugin architecture makes this straightforward.

5. **Retention and lifecycle.** Configure MinIO lifecycle rules to automatically expire old parquet files based on your retention requirements.

### Data Sovereignty Summary

| Aspect | On-Prem (this deployment) |
|--------|--------------------------|
| Proxy | Your cluster |
| Receiver | Your cluster |
| Piper | Your cluster |
| Packer | Your cluster |
| Connector | Your cluster |
| Storage (MinIO) | Your cluster |
| Parquet output | Your MinIO |
| Control plane | bytefreezer.com (config only, no data) |
| Data transit | Cluster network only |

The control plane (bytefreezer.com) only handles configuration, health monitoring, and service registration. It never sees your actual data.

---

## Cleanup

### With Claude + MCP (recommended)

```
Use bf_runbook name=onprem-k8s-cleanup to remove my on-prem ByteFreezer deployment
from Kubernetes. Namespace is "bytefreezer". Proxy is on <your-host> (if Version B).
```

This runs the full cleanup runbook: uninstalls Helm releases, deletes PVCs/namespace, stops proxy on edge host (if applicable), and deletes datasets/tenants/service registrations from the control plane. The account and its API keys are preserved.

### Manual cleanup

#### Stop fakedata

```bash
# Version A (in-cluster)
kubectl delete pod fakedata -n bytefreezer

# Version B (testhost)
# Ctrl+C the docker run command
```

#### Uninstall Helm releases

```bash
helm uninstall proxy -n bytefreezer
helm uninstall bytefreezer -n bytefreezer
```

#### Delete PVCs

```bash
kubectl delete pvc -n bytefreezer --all
```

#### Delete namespace

```bash
kubectl delete namespace bytefreezer
```

#### Stop proxy on testhost (Version B only)

```bash
ssh testhost
cd ~/bytefreezer-proxy
docker compose down -v
```

Manual cleanup only removes infrastructure. You must also clean up control plane resources (tenants, datasets, service registrations) separately using MCP tools or the dashboard.

---

## Troubleshooting

### Kubernetes Issues

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
# docker pull ghcr.io/bytefreezer/bytefreezer-receiver:latest
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
# From testhost:
curl -v http://RECEIVER_IP:8080
# Check LoadBalancer IP is assigned
# Check firewall rules between testhost and cluster
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

### Claude + MCP Issues

**"MCP server not responding":**
```bash
claude mcp list
# Check bytefreezer is listed
curl -s https://mcp.bytefreezer.com/health
# Should return: {"status":"ok","service":"bytefreezer-mcp"}
```

**"Permission denied" on MCP tools:**
- Your API key scope determines what Claude can do
- Account keys: only your account's data

**Claude cannot run kubectl/helm:**
- Make sure `kubectl` and `helm` are in your PATH on your workstation
- Verify cluster access: `kubectl cluster-info`

**SSH connection fails (edge proxy variant):**
```bash
ssh testhost "echo ok"
# If prompted for password, run: ssh-copy-id testhost
```

**Claude cannot run Docker on remote host (edge proxy variant):**
```bash
ssh testhost "docker --version && docker compose version"
# If permission denied: ssh testhost "sudo usermod -aG docker $USER"
```

**Want to disconnect the MCP server:**
```bash
claude mcp remove bytefreezer
```
