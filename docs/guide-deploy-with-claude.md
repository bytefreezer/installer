# How to Deploy ByteFreezer with Claude + MCP

Use Claude Code as your deployment assistant. Connect it to the ByteFreezer MCP server and tell it what you want — Claude handles tenant creation, dataset configuration, config generation, deployment, and verification.

**Objective:** Instead of following a guide step by step, describe your deployment goal in plain English. Claude uses 78 ByteFreezer MCP tools to create tenants, datasets, generate deployment configs, and verify everything is working.

> **Do not send sensitive or production data to bytefreezer.com.** The control plane is a shared test platform. For on-prem deployments your data stays on your infrastructure, but the control plane is not secured for production use.

## How It Works

Claude Code runs on **your workstation**. It connects to the ByteFreezer control plane via MCP for tenant/dataset/config management, and uses SSH to deploy services on remote hosts. For Kubernetes deployments, Claude uses `kubectl`/`helm` directly from your workstation (no SSH needed).

```
Your Workstation                    Remote
+------------------+
| Claude Code      |
|   |               |
|   +-- MCP --------|------> api.bytefreezer.com  (tenant, dataset, config generation)
|   |               |
|   +-- SSH --------|------> testhost              (docker compose, files, fakedata)
|   |               |
|   +-- kubectl ----|------> k8s cluster           (helm install, pods, services)
+------------------+
```

## What You Need

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on your workstation
- **For managed / Docker Compose deployments:**
  - A Linux target host ("testhost") with Docker and Docker Compose
  - SSH access from your workstation to testhost (key-based, no password prompts)
- **For Kubernetes deployments:**
  - `kubectl` and Helm 3 configured on your workstation
  - A running Kubernetes cluster

---

## Step 1: Create a ByteFreezer Account

1. Go to [bytefreezer.com/register](https://bytefreezer.com/register)
2. Create your account with your email and password
3. Log in to the dashboard

## Step 2: Generate an API Key

1. In the dashboard, go to **Settings** → **API Keys**
2. Click **Generate Key**
3. Copy the API key — you will need it in the next step. It is shown only once.

## Step 3: Set Up SSH Access

Skip this step if you are only deploying to Kubernetes.

Claude will SSH into your target host to write config files and run Docker commands. Set up key-based SSH so Claude can connect without password prompts:

```bash
# If you don't have an SSH key yet
ssh-keygen -t ed25519

# Copy your key to the target host
ssh-copy-id testhost

# Verify passwordless access
ssh testhost "hostname && docker --version"
```

Replace `testhost` with your host's IP or hostname. Claude will use this same SSH target in its commands.

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

**What Claude does:**

1. `bf_health_check` — confirms the control API is reachable, returns service version and uptime
2. `bf_health_summary` — shows healthy/unhealthy service counts
3. `bf_list_accounts` — lists accounts visible to your API key (account keys see only their own account; system admin keys see all)

**Expected output:**

| Check | Expected |
|-------|----------|
| Health check | `status: ok`, `service: bytefreezer-control` |
| Health summary | Service counts for control, receiver, piper, packer |
| Accounts | Your account (and system account if system admin key) |

If any of these fail:
- **"MCP server not responding"** — check `claude mcp list` shows `bytefreezer`
- **"Unauthorized"** — your API key is wrong or expired; generate a new one in the dashboard
- **Empty account list** — your API key may not be associated with an account

---

## Step 6: Tell Claude What You Want

Start Claude Code and describe your deployment. Include the target host so Claude knows where to deploy. Below are example prompts for each path.

---

### Path A: Managed (Proxy Only)

**What this does:** Deploys a single proxy on a remote host. Processing and storage run on bytefreezer.com. This is a proxy test — verify your proxy works and query parquet on the test platform.

**Prompt:**

```
I want to try ByteFreezer managed. Create a tenant "demo" with a syslog
dataset on port 5514, then generate a docker-compose setup for the proxy
and deploy it on testhost via SSH. After it's running, assign the dataset
to the proxy and send some test data with fakedata to verify the pipeline works.
```

**What Claude does behind the scenes:**

1. `bf_create_tenant` — creates tenant under your account
2. `bf_create_dataset` — creates syslog dataset with managed S3 output
3. `bf_generate_docker_compose` with `scenario=proxy` — generates docker-compose.yml, .env, and proxy config
4. SSHs into testhost, writes the files, runs `docker compose up -d`
5. Waits for the proxy to register, then `bf_update_dataset_proxy_assignment`
6. SSHs into testhost, runs fakedata container to generate test syslog
7. `bf_dataset_statistics` — verifies events are flowing
8. Reports back what happened

**Verify the pipeline — ask Claude step by step:**

```
Check my deployment health and show me the dataset statistics.
```

Claude uses `bf_health_status`, `bf_dataset_statistics`, and `bf_dataset_parquet_files` to show:

| Check | What Claude does |
|-------|-----------------|
| Service health | `bf_health_summary` + `bf_account_services` — all services healthy |
| Dataset stats | `bf_dataset_statistics` — events received count increasing |
| Parquet files | `bf_dataset_parquet_files` — `.parquet` files exist in output bucket |

Then explore transformations:

```
Show me the schema of my syslog-test dataset, then add a transformation
to rename source_ip to src and add a field environment="test".
Test it first, then activate it.
```

Claude runs:
1. `bf_transformation_schema` — shows discovered field names and types
2. `bf_test_transformation` — dry-run against sample data, shows before/after
3. `bf_activate_transformation` — deploys the config (piper picks it up within 5 minutes)

After new data flows through, verify:

```
Show me the dataset statistics and query the latest parquet files
to confirm the transformation is applied.
```

**Verify:** New events have `src` instead of `source_ip`, and include `environment: "test"`.

To test the pause/resume kill switch:

```
Pause my syslog-test dataset, then check proxy config to confirm it stopped.
After 30 seconds, resume it.
```

Claude uses `bf_update_dataset` to toggle status, and `bf_get_proxy_config` to confirm the proxy dropped the dataset from its active config.

---

### Path B: On-Prem Docker Compose (Full Stack)

**What this does:** Deploys the complete stack (proxy, receiver, piper, packer, MinIO) on a remote host via SSH. Your data stays on that host. Control plane on bytefreezer.com for coordination.

**Prompt:**

```
Deploy a full on-prem ByteFreezer stack with Docker Compose on testhost via SSH.
Create a tenant "demo" and a syslog dataset on port 5514. Include MinIO
for storage. After everything is running, start fakedata and verify data
flows all the way to parquet.
```

**What Claude does behind the scenes:**

1. `bf_create_tenant` and `bf_create_dataset`
2. `bf_generate_docker_compose` with `scenario=full` — generates docker-compose.yml with all services, .env, and config files for proxy, receiver, piper, packer
3. SSHs into testhost, writes all files, runs `docker compose up -d`
4. `bf_account_services` — waits for all four services to register healthy
5. Assigns dataset to proxy, starts fakedata via SSH
6. `bf_dataset_statistics` and `bf_dataset_parquet_files` — verifies parquet output

**Verify the full pipeline:**

```
Check all service health, show dataset statistics, and list parquet files.
```

Claude verifies:

| Check | What Claude does |
|-------|-----------------|
| All services healthy | `bf_account_services` — proxy, receiver, piper, packer all Healthy |
| Data flowing | `bf_dataset_statistics` — events_in, events_out, bytes_processed increasing |
| Parquet output | `bf_dataset_parquet_files` — lists `.parquet` files in packer bucket |

Then explore transformations and features:

```
Show me the schema of my dataset, then create a transformation to
rename source_ip to src, add a field environment="docker-test",
and filter out events where action is "heartbeat".
Test it first, then activate it.
```

```
Show me what filters are available in the transformation catalog.
```

```
Pause the dataset, wait 30 seconds, then resume it. Show me the proxy
config before and after to confirm the kill switch works.
```

**Query your data:** Parquet files are in MinIO on testhost. Use the [example query project](https://github.com/bytefreezer/query-example) or ask Claude:

```
Show me how to query the parquet files in my MinIO on testhost.
```

---

### Path C: On-Prem Kubernetes (Helm)

**What this does:** Deploys the full stack to a Kubernetes cluster using Helm. Your data stays in your cluster. No SSH needed — Claude uses `kubectl` and `helm` directly from your workstation.

**Prompt:**

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

**Variant — proxy on a remote host, stack in Kubernetes:**

```
Same as above, but deploy the proxy on testhost via SSH with Docker Compose
instead of inside the cluster. The rest of the stack stays in Kubernetes.
```

Claude uses `bf_generate_helm_values` for the cluster stack and `bf_generate_docker_compose` with `scenario=proxy` for the edge proxy, wiring the receiver URL from the Kubernetes LoadBalancer IP. It SSHs into testhost to deploy the proxy.

**Verify the pipeline:**

```
Check all services are healthy, show dataset statistics, and list parquet files.
```

Same verification as Path B — Claude checks `bf_account_services`, `bf_dataset_statistics`, and `bf_dataset_parquet_files`.

**Explore transformations:**

```
Show me the schema, add a transformation to rename source_ip to src
and add a field cluster="k8s-test". Test first, then activate.
```

**Test the kill switch:**

```
Pause the dataset, verify the proxy config dropped it, then resume.
```

---

## What Else Can Claude Do?

Once connected to the MCP server, Claude can manage your entire ByteFreezer deployment:

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

---

## Troubleshooting

**"MCP server not responding":**
```bash
claude mcp list
# Check bytefreezer is listed
# Test manually:
curl -s https://mcp.bytefreezer.com/health
# Should return: {"status":"ok","service":"bytefreezer-mcp"}
```

**"Permission denied" on MCP tools:**
- Your API key scope determines what Claude can do
- System admin keys: full access
- Account keys: only your account's data

**SSH connection fails:**
```bash
# Verify key-based SSH works without password prompt
ssh testhost "echo ok"
# If prompted for password, run: ssh-copy-id testhost
# If host key not trusted, run: ssh testhost once manually and accept
```

**Claude can't run Docker on remote host:**
```bash
# Verify Docker is accessible via SSH
ssh testhost "docker --version && docker compose version"
# If permission denied, add user to docker group on testhost:
# ssh testhost "sudo usermod -aG docker \$USER"
```

**Claude can't run kubectl/helm:**
- Make sure `kubectl` and `helm` are in your PATH on your workstation
- Verify cluster access: `kubectl cluster-info`

**Want to disconnect the MCP server:**
```bash
claude mcp remove bytefreezer
```
