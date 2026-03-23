# ByteFreezer On-Prem HA Deployment (Kubernetes)

Deploy the ByteFreezer processing stack in high-availability mode with 3x replicas for receiver, piper, and packer. Connector and proxy remain single-instance. Control plane runs on bytefreezer.com for coordination. Processing, storage, and proxy are self-hosted in your cluster -- your data stays on your infrastructure.

**Objective:** Deploy and verify a fault-tolerant on-prem stack on Kubernetes. Confirm that killing any single pod does not interrupt data flow.

**Time to complete:** 30-40 minutes (manual), 15-20 minutes (Claude + MCP).

> **Do not send sensitive or production data to bytefreezer.com.** The control plane on bytefreezer.com is a shared test platform. Your data stays in your cluster, but the control plane is not secured for production use.

## Contents

- [What's Different from Standard K8s](#whats-different-from-standard-k8s)
- [What You Need](#what-you-need)
- [Architecture](#architecture)
- [How HA Works for Each Component](#how-ha-works-for-each-component)
- [Choose Your Deployment Method](#choose-your-deployment-method)
- [Method A: Step-by-Step Manual](#method-a-step-by-step-manual)
  - [Phase 1: Create Account](#phase-1-create-account-on-bytefreezercom)
  - [Phase 2: Prepare S3 Storage](#phase-2-prepare-s3-storage)
  - [Phase 3: Deploy HA Processing Stack](#phase-3-deploy-ha-processing-stack)
  - [Phase 4A: Deploy Proxy in Kubernetes](#phase-4a-deploy-proxy-in-kubernetes)
  - [Phase 4B: Deploy Proxy on Testhost](#phase-4b-deploy-proxy-on-testhost-edge-proxy)
  - [Phase 5: Configure Dataset](#phase-5-configure-dataset)
  - [Phase 6: Generate Test Data and Verify](#phase-6-generate-test-data-and-verify)
  - [Phase 7: HA Failure Tests](#phase-7-ha-failure-tests)
  - [Phase 8: Explore Features](#phase-8-explore-features)
- [Method B: Deploy with Claude + MCP](#method-b-deploy-with-claude--mcp)
- [Anti-Affinity Modes](#anti-affinity-modes)
- [Resource Sizing](#resource-sizing)
- [Scaling Beyond 3](#scaling-beyond-3)
- [Monitoring HA Health](#monitoring-ha-health)
- [What You Can See on the Dashboard](#what-you-can-see-on-the-dashboard)
- [Connector](#connector)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

---

## What's Different from Standard K8s

This guide builds on the [standard K8s guide](guide-onprem-k8s.md). If you haven't deployed the standard version yet, start there first.

| Component | Standard | HA |
|-----------|----------|-----|
| Receiver | 1 replica | 3 replicas, PDB, anti-affinity |
| Piper | 1 replica | 3 replicas, PDB, anti-affinity |
| Packer | 1 replica | 3 replicas, PDB, anti-affinity |
| Connector | 1 replica | 1 replica (read-only, no HA needed) |
| Proxy | 1 instance | 1 instance (edge, not scaled here) |
| MinIO | Bundled single-instance | Bundled or external S3 |

New Helm features used:
- **`podAntiAffinity`**: `"soft"` or `"hard"` -- spreads replicas across nodes
- **`podDisruptionBudget`**: Prevents too many pods from being evicted at once
- **`replicaCount: 3`**: For receiver, piper, packer

---

## What You Need

**Both methods:**

- A Kubernetes cluster with **3+ worker nodes** (for anti-affinity to spread replicas)
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

```
                          Kubernetes Cluster (3+ nodes)
+--------------------------------------------------------------------------+
|                                                                          |
|  Node 1                  Node 2                  Node 3                  |
|  +-----------+           +-----------+           +-----------+           |
|  | receiver  |           | receiver  |           | receiver  |           |
|  | piper     |           | piper     |           | piper     |           |
|  | packer    |           | packer    |           | packer    |           |
|  +-----------+           +-----------+           +-----------+           |
|        |                       |                       |                 |
|        +----------+------------+-----------+-----------+                 |
|                   |                        |                             |
|            +-----------+            +-----------+                        |
|            | connector |            | MinIO/S3  |                        |
|            +-----------+            +-----------+                        |
|                                          |                               |
+--------------------------------------------------------------------------+
         |                                 |
         v                                 v
  bytefreezer.com              Proxy (edge host or K8s)
  (control plane)                     |
                                 fakedata
```

---

## How HA Works for Each Component

### Receiver (3x)

Receivers are stateless HTTP endpoints. The LoadBalancer distributes incoming batches from proxies across all 3 replicas. Each receiver writes independently to S3. No coordination needed between replicas.

**Failure mode:** If 1 receiver dies, the LoadBalancer routes traffic to the remaining 2. PDB ensures at least 2 are always available during rolling updates.

### Piper (3x)

Each piper instance polls the `intake` S3 bucket for new files. Before processing a file, piper acquires a lock via the control API. This prevents two pipers from processing the same file. Multiple pipers process different files in parallel, increasing throughput.

**Failure mode:** If 1 piper dies, its locks expire and the remaining 2 pick up the work. No data loss -- unprocessed files stay in S3 until claimed.

### Packer (3x)

Each packer instance runs housekeeping cycles that check for processed data to convert to parquet. The control API's `HasJobForDataset` deduplication prevents multiple packers from scheduling the same job. Each packer handles different datasets or time windows.

**Failure mode:** If 1 packer dies, others continue. In-progress parquet jobs are retried on next housekeeping cycle. Spool and cache are per-pod (emptyDir) -- lost on pod death, but packer rebuilds from S3 source data.

### Connector (1x)

Read-only query service using DuckDB. No HA needed -- if it dies, queries fail temporarily but no data is lost. Scale to 2+ if you need query availability.

### Proxy (1x)

Proxy runs at the edge (on the host receiving syslog/netflow). Each proxy serves specific network segments. Scale by deploying additional proxy instances on different hosts, not by replicating the same one.

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
| Name | `test-ha-k8s` |
| Email | your email |
| Deployment Type | `on_prem` |

Copy the **Account ID** and **API Key** (shown only once).

**Verify:** Account appears in the Accounts list.

## Phase 2: Prepare S3 Storage

### Option A: Bundled MinIO (single-instance, acceptable for testing)

No preparation needed. The Helm chart deploys MinIO and creates buckets automatically. MinIO is a single point of failure -- if the MinIO pod dies, all services lose S3 access until it restarts. Data is preserved on the PVC.

### Option B: Dedicated MinIO cluster (on-prem HA)

Deploy a separate MinIO cluster with erasure coding. Minimum 4 nodes. See [MinIO documentation](https://min.io/docs/minio/kubernetes/upstream/) for the MinIO Operator.

```bash
kubectl krew install minio
kubectl minio init
kubectl minio tenant create bytefreezer-storage \
  --servers 4 \
  --volumes 4 \
  --capacity 200Gi \
  --namespace minio-tenant
```

After setup, note the endpoint (e.g., `minio.minio-tenant.svc:443`) and credentials.

Create buckets:
```bash
mc alias set bfminio https://minio.minio-tenant.svc:443 ACCESS_KEY SECRET_KEY
mc mb bfminio/intake
mc mb bfminio/piper
mc mb bfminio/packer
mc mb bfminio/geoip
```

### Option C: AWS S3

Create 4 buckets: `intake`, `piper`, `packer`, `geoip`. Use IAM roles or static credentials.

## Phase 3: Deploy HA Processing Stack

### Step 2 -- Get the Helm charts

```bash
git clone https://github.com/bytefreezer/installer.git
cd installer/helm
```

### Step 3 -- Create namespace

```bash
kubectl create namespace bytefreezer
```

### Step 4 -- Create HA values file

Create `ha-values.yaml`. A pre-built version is available at `installer/helm/bytefreezer/ha-values.yaml`.

**With bundled MinIO:**

```yaml
global:
  deploymentType: "on_prem"

minio:
  enabled: true
  rootUser: "minioadmin"
  rootPassword: "minioadmin"
  persistence:
    enabled: true
    size: 50Gi
  createBuckets: true

s3:
  endpoint: "bytefreezer-minio:9000"
  region: "us-east-1"
  accessKey: "minioadmin"
  secretKey: "minioadmin"
  useSSL: false

controlService:
  enabled: true
  url: "https://api.bytefreezer.com"
  apiKey: "YOUR_API_KEY_HERE"
  accountId: "YOUR_ACCOUNT_ID_HERE"

# --- Receiver: 3 replicas ---
receiver:
  enabled: true
  replicaCount: 3
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-receiver
    tag: "latest"
  webhookService:
    enabled: true
    type: LoadBalancer
    port: 8080
    annotations:
      metallb.universe.tf/address-pool: "default"
  podAntiAffinity: "soft"
  podDisruptionBudget:
    enabled: true
    minAvailable: 2
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi

# --- Piper: 3 replicas ---
piper:
  enabled: true
  replicaCount: 3
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-piper
    tag: "latest"
  processing:
    maxConcurrentJobs: 10
    jobTimeoutSeconds: 600
  podAntiAffinity: "soft"
  podDisruptionBudget:
    enabled: true
    minAvailable: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 4000m
      memory: 4Gi

# --- Packer: 3 replicas ---
packer:
  enabled: true
  replicaCount: 3
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-packer
    tag: "latest"
  housekeeping:
    enabled: true
    intervalSeconds: 300
    testingIntervalSeconds: 15
  podAntiAffinity: "soft"
  podDisruptionBudget:
    enabled: true
    minAvailable: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 4000m
      memory: 4Gi

# --- Connector: 1 replica ---
connector:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/bytefreezer/bytefreezer-connector
    tag: "latest"
  service:
    type: LoadBalancer
    apiPort: 8090
```

Replace `YOUR_API_KEY_HERE` and `YOUR_ACCOUNT_ID_HERE`.

**With external S3:** Set `minio.enabled: false` and update the `s3:` section with your external endpoint and credentials.

### Step 5 -- Install HA processing stack

```bash
helm install bytefreezer ./bytefreezer \
  -n bytefreezer \
  -f ha-values.yaml
```

### Step 6 -- Verify pods are running

```bash
kubectl get pods -n bytefreezer -o wide
```

**Expected:** 10 pods total, spread across 3 nodes:

| Pod | Count | Status |
|-----|-------|--------|
| bytefreezer-receiver-* | 3 | Running |
| bytefreezer-piper-* | 3 | Running |
| bytefreezer-packer-* | 3 | Running |
| bytefreezer-connector-* | 1 | Running |
| bytefreezer-minio-* | 1 | Running |

Verify node distribution:
```bash
kubectl get pods -n bytefreezer -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase
```

With soft anti-affinity, each node should have ~1 receiver + 1 piper + 1 packer.

### Step 7 -- Verify PodDisruptionBudgets

```bash
kubectl get pdb -n bytefreezer
```

**Expected:**
```
NAME                      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
bytefreezer-receiver      2               N/A                1
bytefreezer-piper         2               N/A                1
bytefreezer-packer        2               N/A                1
```

### Step 8 -- Get receiver webhook URL

```bash
RECEIVER_URL=$(kubectl get svc bytefreezer-receiver-webhook -n bytefreezer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Receiver URL: http://${RECEIVER_URL}:8080"
```

The LoadBalancer distributes traffic across all 3 receiver pods.

### Step 9 -- Verify services on dashboard

On bytefreezer.com, go to **Service Status**.

**Verify:** 3 receivers, 3 pipers, 3 packers, 1 connector appear under your account with Healthy status. **10 service instances total** (each pod registers separately).

### Step 10 -- Check MinIO

Port-forward to access MinIO console:

```bash
kubectl port-forward -n bytefreezer svc/bytefreezer-minio 9001:9001
```

Open http://localhost:9001. Login: `minioadmin` / `minioadmin`.

**Verify:** Buckets exist: `intake`, `piper`, `packer`, `geoip`.

## Phase 4A: Deploy Proxy in Kubernetes

### Step 11A -- Create proxy values file

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

### Step 12A -- Install proxy

```bash
helm install proxy ./proxy \
  -n bytefreezer \
  -f proxy-values.yaml
```

### Step 13A -- Verify proxy

```bash
kubectl get pods -n bytefreezer -l app.kubernetes.io/name=proxy
kubectl logs -n bytefreezer -l app.kubernetes.io/name=proxy --tail 20
```

**Verify:** Proxy pod is Running. Logs show "Registered with control service".

On bytefreezer.com **Service Status**: proxy appears with Healthy status. **Total services: 11.**

**Get proxy address for fakedata:**

```bash
PROXY_IP=$(kubectl get pod -n bytefreezer -l app.kubernetes.io/name=proxy -o jsonpath='{.items[0].status.hostIP}')
echo "Proxy IP: ${PROXY_IP}"
```

Skip to **Phase 5**.

## Phase 4B: Deploy Proxy on Testhost (Edge Proxy)

Use this if you want the proxy running outside the cluster (edge deployment pattern).

### Step 11B -- Get receiver external URL

```bash
RECEIVER_IP=$(kubectl get svc bytefreezer-receiver-webhook -n bytefreezer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Receiver URL: http://${RECEIVER_IP}:8080"
```

**Verify:** From testhost, test connectivity:
```bash
curl -s http://${RECEIVER_IP}:8080
```

### Step 12B -- Deploy proxy on testhost via Docker

SSH to testhost and follow the same proxy Docker setup as the [standard guide Phase 3B](guide-onprem-k8s.md#phase-3b-deploy-proxy-on-testhost-edge-proxy). Use the receiver LoadBalancer IP from step 11B.

**Verify:** Proxy appears on bytefreezer.com Service Status page.

`PROXY_IP` for fakedata = testhost's IP address.

## Phase 5: Configure Dataset

### Step 14 -- Create tenant

On bytefreezer.com, navigate to **Tenants** (under your account):

| Field | Value |
|-------|-------|
| Name | `demo` |

### Step 15 -- Create dataset

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

### Step 16 -- Assign to proxy

Edit the dataset. Set **Assigned Proxy** to the proxy instance.

**Verify:** Dataset shows assigned proxy ID.

Wait 1-2 minutes for config sync.

## Phase 6: Generate Test Data and Verify

### Step 17 -- Run fakedata

**If proxy is in Kubernetes (Version A):**

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
    command: ["/bytefreezer-fakedata", "syslog", "--host", "PROXY_IP_HERE", "--port", "5514", "--rate", "20"]
  restartPolicy: Always
EOF
```

Replace `PROXY_IP_HERE` with the proxy IP from Phase 4A.

**If proxy is on testhost (Version B):**

On testhost:
```bash
docker run -d --name fakedata --network host \
  ghcr.io/bytefreezer/bytefreezer-fakedata:latest \
  syslog --host 127.0.0.1 --port 5514 --rate 20
```

### Step 18 -- Verify pipeline

Check each stage in order:

```bash
# Proxy forwarding
kubectl logs -n bytefreezer -l app.kubernetes.io/name=proxy --tail 10

# Receiver storing to S3 (check all 3 receivers)
kubectl logs -n bytefreezer -l app.kubernetes.io/component=receiver --tail 10

# Piper processing (check all 3 pipers)
kubectl logs -n bytefreezer -l app.kubernetes.io/component=piper --tail 10

# Packer producing parquet (check all 3 packers)
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer --tail 10
```

**Verify in MinIO** (port-forward if needed):

```bash
kubectl exec -n bytefreezer deploy/bytefreezer-minio -- mc alias set local http://localhost:9000 minioadmin minioadmin
kubectl exec -n bytefreezer deploy/bytefreezer-minio -- mc ls local/intake/ --recursive | head -5
kubectl exec -n bytefreezer deploy/bytefreezer-minio -- mc ls local/piper/ --recursive | head -5
kubectl exec -n bytefreezer deploy/bytefreezer-minio -- mc ls local/packer/ --recursive | grep parquet
```

**Verify on dashboard:**
- **Statistics page:** Events flowing through all stages
- **Activity page:** Piper and packer processing entries
- **Service Status:** All 10-11 services Healthy

## Phase 7: HA Failure Tests

**Do not skip this phase.** The point of HA is fault tolerance -- verify it works.

### Test 1 -- Kill a receiver pod

```bash
POD=$(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=receiver -o jsonpath='{.items[0].metadata.name}')
echo "Killing receiver: $POD"
kubectl delete pod -n bytefreezer $POD
```

Wait 30s. Check:
- `kubectl get pods -n bytefreezer -l app.kubernetes.io/component=receiver` -- 3 pods again (replacement created)
- Proxy logs still show forwarding
- **Expected:** No data loss. LoadBalancer routes to remaining 2 receivers.

### Test 2 -- Kill a piper pod

```bash
POD=$(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=piper -o jsonpath='{.items[0].metadata.name}')
echo "Killing piper: $POD"
kubectl delete pod -n bytefreezer $POD
```

Wait 30s. Check:
- Remaining 2 pipers continue processing
- **Expected:** Locks held by dead pod expire. Files picked up by another piper.

### Test 3 -- Kill a packer pod

```bash
POD=$(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=packer -o jsonpath='{.items[0].metadata.name}')
echo "Killing packer: $POD"
kubectl delete pod -n bytefreezer $POD
```

Wait 60s. Check:
- Remaining 2 packers continue parquet generation
- **Expected:** In-progress jobs retried on next housekeeping cycle.

### Test 4 -- Drain a node

```bash
kubectl drain node-2 --ignore-daemonsets --delete-emptydir-data
```

**Expected:** PDB prevents more than 1 pod per component from being evicted simultaneously. Pods reschedule to remaining nodes. Data flow is not interrupted.

```bash
# Restore after test
kubectl uncordon node-2
```

### Verify after HA tests

```bash
# All pods back to 3 replicas each
kubectl get pods -n bytefreezer -o wide

# All services healthy on dashboard
# (Note: killed pods may leave orphaned service registrations -- clean up stale ones)
```

## Phase 8: Explore Features

Same as the [standard guide Phase 6](guide-onprem-k8s.md#phase-6-explore-features). Try transformations, dataset pause/resume, and different data sources.

---

# Method B: Deploy with Claude + MCP

Tell Claude what you want in plain English. Claude uses the ByteFreezer MCP tools to create resources on bytefreezer.com, generates Helm values, and runs kubectl/helm from your workstation.

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
kubectl get nodes    # Must have 3+ worker nodes for HA
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

Start Claude Code and run a quick smoke test:

```
Use bf_health_check, bf_list_accounts, and bf_health_summary to verify MCP connectivity.
```

## Deploy HA with Claude

### Option A: Everything in Kubernetes

```
Use bf_runbook name=onprem-ha-k8s to deploy a high-availability ByteFreezer stack
to my Kubernetes cluster with Helm. 3x receiver, 3x piper, 3x packer. Create a
tenant "demo" and a syslog dataset on port 5514 with testing=true and
local_storage=true. Use bundled MinIO. Deploy proxy in-cluster, start fakedata,
verify parquet output, and run HA failure tests.
```

**What Claude does behind the scenes:**

1. `bf_whoami` -- discovers account context
2. `bf_create_tenant` and `bf_create_dataset` -- with full source+destination config
3. `bf_update_dataset` -- enables testing mode
4. Writes HA values file with 3x replicas, anti-affinity, PDBs
5. Runs `helm install` for processing stack + proxy
6. Monitors pods with `kubectl get pods -o wide`, verifies spread across nodes
7. Checks PDBs with `kubectl get pdb`
8. `bf_account_services` -- verifies all 10-11 service instances registered
9. Assigns dataset to proxy, deploys fakedata
10. Verifies parquet output via kubectl exec into MinIO pod
11. Runs HA failure tests: kills one receiver, piper, packer pod each
12. Verifies data flow continued during each failure
13. Runs connector query to confirm data is queryable

### Option B: Proxy on Edge Host, Stack in Kubernetes

```
Use bf_runbook name=onprem-ha-k8s to deploy an HA ByteFreezer processing stack
(3x receiver, 3x piper, 3x packer, connector, minio) to my Kubernetes cluster
with Helm, and the proxy separately on <your-host> via Docker Compose. Create a
tenant "demo" and a syslog dataset on port 5514 with testing=true and
local_storage=true. Wire the proxy to the receiver LoadBalancer. Start fakedata,
verify parquet output, and run HA failure tests.
```

## Verify with Claude

```
Use bf_health_summary and bf_account_services to check all service health.
I should see 3x receiver, 3x piper, 3x packer all Healthy.
Then use bf_dataset_statistics to verify data flow.
```

| Check | What Claude does |
|-------|-----------------|
| All services healthy | `bf_account_services` -- 10-11 instances, all Healthy |
| Pod distribution | `kubectl get pods -o wide` -- spread across 3 nodes |
| PDBs active | `kubectl get pdb` -- 3 PDBs with ALLOWED DISRUPTIONS > 0 |
| Data flowing | `bf_dataset_statistics` -- events increasing |
| Parquet output | MinIO packer bucket -- `.parquet` files |

## HA Tests with Claude

```
Kill one receiver pod, one piper pod, and one packer pod (one at a time, 30s apart).
After each kill, verify data continues flowing. Then confirm all pods are back to 3
replicas and clean up orphaned service registrations.
```

## Explore with Claude

Same as the [standard guide](guide-onprem-k8s.md#explore-with-claude). Transformations, kill switch, query your data.

### What Else Can Claude Do?

| Ask Claude to... | MCP tool to mention |
|---|---|
| Deploy HA stack to Kubernetes | `bf_runbook name=onprem-ha-k8s` |
| Deploy standard stack to Kubernetes | `bf_runbook name=onprem-full-k8s` |
| Deploy full stack via Docker Compose | `bf_runbook name=onprem-full-docker-compose` |
| Remove Kubernetes deployment | `bf_runbook name=onprem-k8s-cleanup` |
| Remove Docker Compose deployment | `bf_runbook name=onprem-cleanup` |
| Show dataset schema | `bf_transformation_schema` |
| Test a transformation | `bf_test_transformation` |
| Activate a transformation | `bf_activate_transformation` |
| Check service health | `bf_health_summary`, `bf_account_services` |
| List parquet files | `bf_dataset_parquet_files` |
| Pause/resume a dataset | `bf_update_dataset` |
| Generate systemd install script | `bf_generate_systemd` |

---

## Anti-Affinity Modes

| Mode | Behavior | When to use |
|------|----------|-------------|
| `""` (empty) | No anti-affinity. Pods may land on same node. | Dev/test, single-node clusters |
| `"soft"` | Prefer different nodes, but allow same node if needed. | Production with 3 nodes. Tolerates uneven clusters. |
| `"hard"` | Require different nodes. Pod stays Pending if no eligible node. | Production with 3+ nodes and strict fault isolation. |

Use `"soft"` unless you have exactly 1 pod per node per component and can guarantee node availability. `"hard"` will leave pods in Pending state if there aren't enough nodes.

---

## Resource Sizing

### Minimum (3-node cluster, low throughput)

| Component | CPU request | Memory request | CPU limit | Memory limit |
|-----------|-------------|---------------|-----------|-------------|
| Receiver (x3) | 100m | 256Mi | 1000m | 1Gi |
| Piper (x3) | 200m | 512Mi | 2000m | 2Gi |
| Packer (x3) | 200m | 512Mi | 2000m | 2Gi |
| Connector (x1) | 100m | 256Mi | 1000m | 1Gi |
| **Total** | 1.9 CPU | 4.3Gi | 19 CPU | 19Gi |

### Production (3-node cluster, high throughput)

| Component | CPU request | Memory request | CPU limit | Memory limit |
|-----------|-------------|---------------|-----------|-------------|
| Receiver (x3) | 500m | 1Gi | 4000m | 4Gi |
| Piper (x3) | 1000m | 2Gi | 8000m | 8Gi |
| Packer (x3) | 1000m | 2Gi | 8000m | 8Gi |
| Connector (x1) | 200m | 512Mi | 2000m | 2Gi |
| **Total** | 7.7 CPU | 16.5Gi | 62 CPU | 62Gi |

---

## Scaling Beyond 3

The same pattern works for any replica count. Change `replicaCount` and adjust PDB `minAvailable` accordingly:

| Replicas | Recommended minAvailable | Tolerated failures |
|----------|-------------------------|-------------------|
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 5 | 2 |

```yaml
# Example: 5x piper
piper:
  replicaCount: 5
  podDisruptionBudget:
    enabled: true
    minAvailable: 3
```

---

## Monitoring HA Health

### All service instances on dashboard

On bytefreezer.com **Service Status**, filter by your account. Each pod registers as a separate service instance. All should show Healthy.

### Pod restart count

```bash
kubectl get pods -n bytefreezer -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase
```

Restarts > 0 indicate crashes. Check logs: `kubectl logs -n bytefreezer <pod-name> --previous`

### PDB status

```bash
kubectl get pdb -n bytefreezer -o wide
```

`ALLOWED DISRUPTIONS` should be > 0 during normal operation. If it's 0, the cluster cannot safely evict any pod (all replicas are at minimum).

---

## What You Can See on the Dashboard

Same as the [standard guide](guide-onprem-k8s.md#what-you-can-see-on-the-dashboard). The difference in HA: the **Service Status** page shows 3 instances per component (receiver, piper, packer) instead of 1. Each instance has its own health status, metrics, and last-seen timestamp.

---

## Connector

Same as the [standard guide](guide-onprem-k8s.md#connector). The connector runs as 1 replica and reads parquet files from MinIO via DuckDB. Port-forward or use the LoadBalancer IP to access the web UI on port 8090.

---

## Cleanup

### With Claude + MCP (recommended)

```
Use bf_runbook name=onprem-k8s-cleanup to remove my HA ByteFreezer deployment
from Kubernetes. Namespace is "bytefreezer". Proxy is on <your-host> (if edge variant).
```

This runs the full cleanup runbook: uninstalls Helm releases, deletes PVCs/namespace, stops proxy on edge host (if applicable), and deletes datasets/tenants/service registrations from the control plane. The account and its API keys are preserved.

**Note:** HA deployments have more service registrations to clean up (10-11 vs 4-5). The cleanup runbook handles this automatically.

### Manual cleanup

#### Stop fakedata

```bash
# Version A (in-cluster)
kubectl delete pod fakedata -n bytefreezer

# Version B (testhost)
# Ctrl+C the docker run command, or:
docker rm -f fakedata
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

#### Clean up control plane resources

Manual cleanup only removes infrastructure. You must also clean up control plane resources (tenants, datasets, service registrations) separately using MCP tools or the dashboard. With HA, expect 10-11 service registrations to delete.

---

## Troubleshooting

### Pods stuck in Pending (hard anti-affinity)

```bash
kubectl describe pod <pending-pod> -n bytefreezer
```

If you see `FailedScheduling: 0/3 nodes are available: 3 node(s) didn't match pod anti-affinity rules`, switch from `"hard"` to `"soft"` anti-affinity or add more nodes.

### PDB blocks kubectl drain

With `minAvailable: 2` and 3 replicas, only 1 pod can be evicted at a time. If a node is already down (1 pod missing), drain on a second node will hang. Solutions:
- Temporarily edit PDB: `kubectl edit pdb -n bytefreezer`
- Or use `maxUnavailable: 1` instead of `minAvailable: 2` in values

### Multiple pipers processing same file

This should not happen -- control API file locking prevents it. If you see duplicate processing in activity logs, check that all pipers can reach the control API:

```bash
for pod in $(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=piper -o name); do
  echo "--- $pod ---"
  kubectl exec -n bytefreezer $pod -- wget -qO- https://api.bytefreezer.com/api/v1/health
done
```

### Packer job queue growing

With 3 packers and testing mode (15s interval), job scheduling can outpace processing. If you see retries growing in logs:

```bash
kubectl logs -n bytefreezer -l app.kubernetes.io/component=packer | grep -c "retry"
```

Increase `housekeeping.intervalSeconds` or reduce `testingIntervalSeconds`.

### Orphaned service registrations after pod restarts

Each killed/restarted pod registers a new instance. The old registration lingers as Unhealthy. Clean up via dashboard or MCP:

```
Use bf_account_services to list all services. Delete any instances whose pod
name no longer exists in kubectl get pods output.
```

### Uneven load distribution

Check which piper/packer instances are doing work:

On bytefreezer.com **Activity** page, look at the instance IDs on processing entries. If one instance handles most work, the others may have connectivity issues to S3 or the control API.

### Kubernetes-specific issues

See the [standard guide troubleshooting](guide-onprem-k8s.md#troubleshooting) for image pull errors, MinIO issues, UDP problems, and Claude + MCP issues.
