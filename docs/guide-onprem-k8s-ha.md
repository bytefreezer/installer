# ByteFreezer On-Prem HA Deployment (Kubernetes)

Deploy the ByteFreezer processing stack in high-availability mode with 3x replicas for receiver, piper, and packer. Connector and proxy remain single-instance. Control plane runs on bytefreezer.com for coordination.

## Contents

- [What's Different](#whats-different-from-the-standard-deployment)
- [What You Need](#what-you-need)
- [Architecture](#architecture)
- [How HA Works for Each Component](#how-ha-works-for-each-component)
- [Deployment](#deployment)
  - [Phase 1: Account Setup](#phase-1-account-setup)
  - [Phase 2: Prepare External S3](#phase-2-prepare-external-s3)
  - [Phase 3: Create HA Values File](#phase-3-create-ha-values-file)
  - [Phase 4: Install](#phase-4-install)
  - [Phase 5: Verify HA Deployment](#phase-5-verify-ha-deployment)
  - [Phase 6: Deploy Proxy](#phase-6-deploy-proxy)
  - [Phase 7: Create Tenant, Dataset, and Test](#phase-7-create-tenant-dataset-and-test)
- [HA Verification Tests](#ha-verification-tests)
- [Anti-Affinity Modes](#anti-affinity-modes)
- [Resource Sizing](#resource-sizing)
- [Scaling Beyond 3](#scaling-beyond-3)
- [Monitoring HA Health](#monitoring-ha-health)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

---

**What's different from the standard deployment:**

| Component | Standard | HA |
|-----------|----------|-----|
| Receiver | 1 replica | 3 replicas, PDB, anti-affinity |
| Piper | 1 replica | 3 replicas, PDB, anti-affinity |
| Packer | 1 replica | 3 replicas, PDB, anti-affinity |
| Connector | 1 replica | 1 replica (read-only, no HA needed) |
| Proxy | 1 instance | 1 instance (edge, not scaled here) |
| MinIO | Bundled single-instance | External S3 or dedicated MinIO cluster |

---

## What You Need

Everything from the [standard K8s guide](guide-onprem-k8s.md), plus:

- **3+ worker nodes** in your Kubernetes cluster (for pod anti-affinity to spread replicas)
- **External S3-compatible storage** — the bundled MinIO is single-instance and cannot provide HA. Options:
  - AWS S3 / GCS / Azure Blob (cloud)
  - Dedicated MinIO cluster with erasure coding (4+ nodes minimum)
  - Any S3-compatible object store with replication
- MetalLB or cloud LoadBalancer for receiver webhook service

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
|            | connector |            |    LB     |                        |
|            +-----------+            +-----------+                        |
|                                          |                               |
+--------------------------------------------------------------------------+
         |                                 |
         v                                 v
  External S3 / MinIO            Proxy (edge host or K8s)
         |
         v
  bytefreezer.com (control plane)
```

---

## How HA Works for Each Component

### Receiver (3x)

Receivers are stateless HTTP endpoints. The LoadBalancer distributes incoming batches from proxies across all 3 replicas. Each receiver writes independently to S3. No coordination needed between replicas.

**Failure mode:** If 1 receiver dies, the LoadBalancer routes traffic to the remaining 2. PDB ensures at least 2 are always available during rolling updates.

### Piper (3x)

Each piper instance polls the `intake` S3 bucket for new files. Before processing a file, piper acquires a lock via the control API. This prevents two pipers from processing the same file. Multiple pipers process different files in parallel, increasing throughput.

**Failure mode:** If 1 piper dies, its locks expire and the remaining 2 pick up the work. No data loss — unprocessed files stay in S3 until claimed.

### Packer (3x)

Each packer instance runs housekeeping cycles that check for processed data to convert to parquet. The control API's `HasJobForDataset` deduplication prevents multiple packers from scheduling the same job. Each packer handles different datasets or time windows.

**Failure mode:** If 1 packer dies, others continue. In-progress parquet jobs are retried on next housekeeping cycle. Spool and cache are per-pod (emptyDir) — lost on pod death, but packer rebuilds from S3 source data.

### Connector (1x)

Read-only query service using DuckDB. No HA needed — if it dies, queries fail temporarily but no data is lost. Scale to 2+ if you need query availability.

### Proxy (1x)

Proxy runs at the edge (on the host receiving syslog/netflow). Each proxy serves specific network segments. Scale by deploying additional proxy instances on different hosts, not by replicating the same one.

---

## Deployment

### Phase 1: Account Setup

Same as the [standard guide Phase 1](guide-onprem-k8s.md#phase-1-create-account-on-bytefreezercom). Create an account with `deployment_type: on_prem`.

### Phase 2: Prepare External S3

The bundled MinIO is a single Deployment with one PVC — it cannot survive node failure. For HA, use external S3.

**Option A: Dedicated MinIO cluster (on-prem)**

Deploy a separate MinIO cluster with erasure coding. Minimum 4 nodes. See [MinIO documentation](https://min.io/docs/minio/kubernetes/upstream/) for the MinIO Operator.

```bash
# Example: MinIO Operator
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

**Option B: AWS S3**

Create 4 buckets in your AWS account: `intake`, `piper`, `packer`, `geoip`. Use IAM roles for pod authentication or static credentials.

**Option C: Bundled MinIO (not HA)**

If you accept MinIO as a single point of failure (data is recoverable from source), you can still use the bundled MinIO. Set `minio.enabled: true` in your values. Everything else in this guide still applies — you get HA for processing but not for storage.

### Phase 3: Create HA Values File

Create `ha-values.yaml`:

```yaml
global:
  deploymentType: "on_prem"

# Disable bundled MinIO — using external S3
minio:
  enabled: false

# External S3 credentials
s3:
  endpoint: "YOUR_S3_ENDPOINT"       # e.g., "minio.minio-tenant.svc:9000"
  region: "us-east-1"
  accessKey: "YOUR_ACCESS_KEY"
  secretKey: "YOUR_SECRET_KEY"
  useSSL: false                       # true for AWS S3 or TLS-enabled MinIO

controlService:
  enabled: true
  url: "https://api.bytefreezer.com"
  apiKey: "YOUR_API_KEY"
  accountId: "YOUR_ACCOUNT_ID"

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

Replace all `YOUR_*` placeholders.

A pre-built version of this file is available at `installer/helm/bytefreezer/ha-values.yaml`.

### Phase 4: Install

```bash
kubectl create namespace bytefreezer

helm install bytefreezer ./bytefreezer \
  -n bytefreezer \
  -f ha-values.yaml
```

### Phase 5: Verify HA Deployment

#### Check pod distribution

```bash
kubectl get pods -n bytefreezer -o wide
```

**Expected:** 3 receiver pods, 3 piper pods, 3 packer pods, 1 connector pod — spread across different nodes.

```
NAME                                      READY   NODE
bytefreezer-receiver-abc123-x1            1/1     node-1
bytefreezer-receiver-abc123-x2            1/1     node-2
bytefreezer-receiver-abc123-x3            1/1     node-3
bytefreezer-piper-def456-y1              1/1     node-1
bytefreezer-piper-def456-y2              1/1     node-2
bytefreezer-piper-def456-y3              1/1     node-3
bytefreezer-packer-ghi789-z1             1/1     node-1
bytefreezer-packer-ghi789-z2             1/1     node-2
bytefreezer-packer-ghi789-z3             1/1     node-3
bytefreezer-connector-jkl012-a1          1/1     node-1
```

#### Check PodDisruptionBudgets

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

#### Check services registered on control plane

On bytefreezer.com **Service Status** page: you should see 3 receiver instances, 3 piper instances, 3 packer instances, and 1 connector. Each has a unique instance ID (pod hostname).

#### Check LoadBalancer

```bash
kubectl get svc -n bytefreezer
```

The receiver webhook service should have an external IP. All 3 receiver pods serve as backends.

### Phase 6: Deploy Proxy

Same as the [standard guide Phase 3](guide-onprem-k8s.md#phase-3a-deploy-proxy-in-kubernetes). Proxy stays at 1 replica. Point it at the receiver LoadBalancer IP.

### Phase 7: Create Tenant, Dataset, and Test

Same as the standard guide [Phase 4](guide-onprem-k8s.md#phase-4-configure-dataset) and [Phase 5](guide-onprem-k8s.md#phase-5-generate-test-data-and-verify).

---

## HA Verification Tests

### Test 1: Kill a receiver pod

```bash
kubectl delete pod -n bytefreezer -l app.kubernetes.io/component=receiver --field-selector metadata.name=$(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=receiver -o jsonpath='{.items[0].metadata.name}')
```

**Expected:** Data continues flowing. Kubernetes recreates the pod. No data loss. The remaining 2 receivers handle all traffic during the gap.

### Test 2: Kill a piper pod

```bash
kubectl delete pod -n bytefreezer -l app.kubernetes.io/component=piper --field-selector metadata.name=$(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=piper -o jsonpath='{.items[0].metadata.name}')
```

**Expected:** Processing continues on the other 2 pipers. Locks held by the dead pod expire. Files it was processing get picked up by another piper on retry.

### Test 3: Kill a packer pod

```bash
kubectl delete pod -n bytefreezer -l app.kubernetes.io/component=packer --field-selector metadata.name=$(kubectl get pods -n bytefreezer -l app.kubernetes.io/component=packer -o jsonpath='{.items[0].metadata.name}')
```

**Expected:** Parquet generation continues. In-progress jobs are retried on next housekeeping cycle.

### Test 4: Drain a node

```bash
kubectl drain node-2 --ignore-daemonsets --delete-emptydir-data
```

**Expected:** PDB prevents more than 1 pod per component from being evicted simultaneously. Pods reschedule to remaining nodes. Data flow is not interrupted.

```bash
# Restore after test
kubectl uncordon node-2
```

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

## Cleanup

```bash
helm uninstall bytefreezer -n bytefreezer
kubectl delete pvc -n bytefreezer --all
kubectl delete namespace bytefreezer
```

If using the proxy on an edge host, stop it separately:
```bash
ssh testhost "cd ~/bytefreezer-proxy && docker compose down -v"
```

With Claude + MCP:
```
Use bf_runbook name=onprem-k8s-cleanup to remove the HA deployment from Kubernetes.
Namespace is "bytefreezer". Proxy is on <your-host>.
```

---

## Troubleshooting

### Pods stuck in Pending (hard anti-affinity)

```bash
kubectl describe pod <pending-pod> -n bytefreezer
```

If you see `FailedScheduling: 0/3 nodes are available: 3 node(s) didn't match pod anti-affinity rules`, switch from `"hard"` to `"soft"` anti-affinity or add more nodes.

### Multiple pipers processing same file

This should not happen — control API file locking prevents it. If you see duplicate processing in activity logs, check that all pipers can reach the control API:

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

Increase `housekeeping.intervalSeconds` or reduce `testingIntervalSeconds` for testing datasets.

### Uneven load distribution

Check which piper/packer instances are doing work:

On bytefreezer.com **Activity** page, look at the instance IDs on processing entries. If one instance handles most work, the others may have connectivity issues to S3 or the control API.
