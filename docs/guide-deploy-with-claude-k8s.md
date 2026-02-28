# Deploy On-Prem (Kubernetes) with Claude + MCP

Deploy the complete ByteFreezer stack to a Kubernetes cluster using Claude as your deployment assistant. Your data stays in your cluster. No SSH needed — Claude uses `kubectl` and `helm` directly from your workstation.

> **Prefer step-by-step manual instructions?** See [On-Prem Kubernetes Guide](guide-onprem-kubernetes.md).

> **Do not send sensitive or production data to bytefreezer.com.** The control plane is a shared test platform. Your data stays in your cluster, but the control plane is not secured for production use.

---

## What You Need

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on your workstation
- `kubectl` and Helm 3 configured on your workstation
- A running Kubernetes cluster
- **Optional (for edge proxy variant):** A Linux host with Docker and SSH access from your workstation

---

## Step 1: Create a ByteFreezer Account

1. Go to [bytefreezer.com/register](https://bytefreezer.com/register)
2. Create your account with your email and password
3. Log in to the dashboard

## Step 2: Generate an API Key

1. In the dashboard, go to **Settings** → **API Keys**
2. Click **Generate Key**
3. Copy the API key — you will need it in the next step. It is shown only once.

## Step 3: Verify Cluster Access

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

## Step 4: Connect Claude to ByteFreezer MCP

Run this once to register the MCP server with Claude Code:

```bash
claude mcp add --transport http bytefreezer \
  https://mcp.bytefreezer.com/mcp \
  --header "Authorization: Bearer YOUR_API_KEY"
```

Replace `YOUR_API_KEY` with the API key from Step 2.

**Verify:**

```bash
claude mcp list
```

You should see `bytefreezer` in the list.

## Step 5: Verify MCP Connection

Start Claude Code and run a quick smoke test to confirm the MCP server is reachable and your API key works:

```
Check the ByteFreezer health, list all accounts, and show the health summary.
```

**Expected output:**

| Check | Expected |
|-------|----------|
| Health check | `status: ok`, `service: bytefreezer-control` |
| Health summary | Service counts for control, receiver, piper, packer |
| Accounts | Your account listed |

If any of these fail:
- **"MCP server not responding"** — check `claude mcp list` shows `bytefreezer`
- **"Unauthorized"** — your API key is wrong or expired; generate a new one in the dashboard
- **Empty account list** — your API key may not be associated with an account

---

## Step 6: Deploy

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
Deploy ByteFreezer to my Kubernetes cluster with Helm.
Create a tenant "demo" and a syslog dataset on port 5514. Use bundled MinIO.
Generate the Helm values and install the chart.
Then deploy fakedata and verify parquet output.
```

**What Claude does behind the scenes:**

1. `bf_create_tenant` and `bf_create_dataset`
2. `bf_generate_helm_values` with `scenario=full` — generates values.yaml
3. Writes values.yaml locally, runs `helm install`
4. Monitors pods with `kubectl get pods`, waits for healthy
5. `bf_account_services` — verifies all services registered
6. Deploys fakedata pod, assigns dataset to proxy
7. Verifies parquet output

### Option B: Proxy on Edge Host, Stack in Kubernetes

```
Deploy the ByteFreezer processing stack (receiver, piper, packer, minio)
to my Kubernetes cluster with Helm. Deploy the proxy separately on testhost
via SSH with Docker Compose. Create a tenant "demo" and a syslog dataset
on port 5514. Wire the proxy to send data to the receiver in Kubernetes.
Start fakedata on testhost and verify parquet output.
```

Claude uses `bf_generate_helm_values` for the cluster stack and `bf_generate_docker_compose` with `scenario=proxy` for the edge proxy, wiring the receiver URL from the Kubernetes LoadBalancer IP. It SSHs into testhost to deploy the proxy.

---

## Step 7: Verify

Ask Claude to check the pipeline:

```
Check all services are healthy, show dataset statistics, and list parquet files.
```

| Check | What Claude does |
|-------|-----------------|
| All services healthy | `bf_account_services` — proxy, receiver, piper, packer all Healthy |
| Data flowing | `bf_dataset_statistics` — events_in, events_out, bytes_processed increasing |
| Parquet output | `bf_dataset_parquet_files` — lists `.parquet` files in packer bucket |

---

## After Deployment

### Explore Transformations

```
Show me the schema, add a transformation to rename source_ip to src
and add a field cluster="k8s-test". Test first, then activate.
```

### Test the Kill Switch

```
Pause the dataset, verify the proxy config dropped it, then resume.
```

### Query Your Data

Parquet files are in MinIO inside your cluster. Use the [example query project](https://github.com/bytefreezer/query-example) or ask Claude:

```
Show me how to query the parquet files in my Kubernetes MinIO.
```

### What Else Can Claude Do?

| Ask Claude to... | Tools it uses |
|---|---|
| "Add a transformation to rename source_ip to src" | `bf_activate_transformation` |
| "Show me the schema of my dataset" | `bf_transformation_schema` |
| "Test this transformation config before deploying" | `bf_test_transformation` |
| "Check which services are healthy" | `bf_health_status`, `bf_health_summary` |
| "List my parquet files" | `bf_dataset_parquet_files` |
| "Pause the dataset" | `bf_update_dataset` |
| "Show me what filters are available" | `bf_filter_catalog` |
| "Generate a systemd install script for bare metal" | `bf_generate_systemd` |

### Understanding the Pipeline

See **[What Happens After Deployment](guide-post-deployment.md)** for details on the data pipeline, dashboard pages, transformations, GeoIP, and how the demo differs from production.

---

## Troubleshooting

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

**Claude can't run kubectl/helm:**
- Make sure `kubectl` and `helm` are in your PATH on your workstation
- Verify cluster access: `kubectl cluster-info`

**SSH connection fails (edge proxy variant):**
```bash
ssh testhost "echo ok"
# If prompted for password, run: ssh-copy-id testhost
```

**Claude can't run Docker on remote host (edge proxy variant):**
```bash
ssh testhost "docker --version && docker compose version"
# If permission denied: ssh testhost "sudo usermod -aG docker $USER"
```

**Want to disconnect the MCP server:**
```bash
claude mcp remove bytefreezer
```
