# How to Deploy ByteFreezer with Claude + MCP

Use Claude Code as your deployment assistant. Connect it to the ByteFreezer MCP server and tell it what you want — Claude handles account creation, config generation, deployment, and verification.

**Objective:** Instead of following a guide step by step, describe your deployment goal in plain English. Claude uses 63 ByteFreezer MCP tools to create accounts, tenants, datasets, generate deployment configs, and verify everything is working.

> **Do not send sensitive or production data to bytefreezer.com.** The control plane is a shared test platform. For on-prem deployments your data stays on your infrastructure, but the control plane is not secured for production use.

## How It Works

Claude Code runs on **your workstation**. It connects to the ByteFreezer control plane via MCP for account/tenant/dataset management, and uses SSH to deploy services on remote hosts. For Kubernetes deployments, Claude uses `kubectl`/`helm` directly from your workstation (no SSH needed).

```
Your Workstation                    Remote
+------------------+
| Claude Code      |
|   |               |
|   +-- MCP --------|------> api.bytefreezer.com  (account, tenant, dataset, config)
|   |               |
|   +-- SSH --------|------> testhost              (docker compose, files, fakedata)
|   |               |
|   +-- kubectl ----|------> k8s cluster           (helm install, pods, services)
+------------------+
```

## What You Need

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on your workstation
- A ByteFreezer account with an API key (or have Claude create one for you)
- **For managed / Docker Compose deployments:**
  - A Linux target host ("testhost") with Docker and Docker Compose
  - SSH access from your workstation to testhost (key-based, no password prompts)
- **For Kubernetes deployments:**
  - `kubectl` and Helm 3 configured on your workstation
  - A running Kubernetes cluster

## Setting Up SSH Access

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

---

## Step 1: Connect Claude to ByteFreezer MCP

Run this once to register the MCP server with Claude Code:

```bash
claude mcp add --transport http bytefreezer \
  https://mcp.bytefreezer.com/mcp \
  --header "Authorization: Bearer YOUR_API_KEY"
```

Replace `YOUR_API_KEY` with your API key from bytefreezer.com.

**Verify:**

```bash
claude mcp list
```

You should see `bytefreezer` in the list.

---

## Step 2: Tell Claude What You Want

Start Claude Code and describe your deployment. Include the target host so Claude knows where to deploy. Below are example prompts for each path.

---

### Path A: Managed (Proxy Only)

**What this does:** Deploys a single proxy on a remote host. Processing and storage run on bytefreezer.com. This is a proxy test — verify your proxy works and query parquet on the test platform.

**Prompt:**

```
I want to try ByteFreezer managed. Create an account called "my-test",
create a tenant "demo" with a syslog dataset on port 5514,
then generate a docker-compose setup for the proxy and deploy it
on testhost via SSH. After it's running, assign the dataset to the proxy
and send some test data with fakedata to verify the pipeline works.
```

**What Claude does behind the scenes:**

1. `bf_create_account` — creates account, saves account ID and API key
2. `bf_create_tenant` — creates tenant under the account
3. `bf_create_dataset` — creates syslog dataset with managed S3 output
4. `bf_generate_docker_compose` with `scenario=proxy` — generates docker-compose.yml, .env, and proxy config
5. SSHs into testhost, writes the files, runs `docker compose up -d`
6. Waits for the proxy to register, then `bf_update_dataset_proxy_assignment`
7. SSHs into testhost, runs fakedata container to generate test syslog
8. `bf_dataset_statistics` — verifies events are flowing
9. Reports back what happened

**Verify:** Ask Claude:

```
Check my deployment health and show me the dataset statistics.
```

Claude uses `bf_health_status`, `bf_dataset_statistics`, and `bf_dataset_parquet_files` to give you a full status report.

---

### Path B: On-Prem Docker Compose (Full Stack)

**What this does:** Deploys the complete stack (proxy, receiver, piper, packer, MinIO) on a remote host via SSH. Your data stays on that host. Control plane on bytefreezer.com for coordination.

**Prompt:**

```
Deploy a full on-prem ByteFreezer stack with Docker Compose on testhost via SSH.
Create an on_prem account called "my-onprem", a tenant "demo",
and a syslog dataset on port 5514. Include MinIO for storage.
After everything is running, start fakedata and verify data flows
all the way to parquet.
```

**What Claude does behind the scenes:**

1. `bf_create_account` with `type=on_prem`
2. `bf_create_tenant` and `bf_create_dataset`
3. `bf_generate_docker_compose` with `scenario=full` — generates docker-compose.yml with all services, .env, and config files for proxy, receiver, piper, packer
4. SSHs into testhost, writes all files, runs `docker compose up -d`
5. `bf_account_services` — waits for all four services to register healthy
6. Assigns dataset to proxy, starts fakedata via SSH
7. `bf_dataset_statistics` and `bf_dataset_parquet_files` — verifies parquet output

**Query your data:** Your parquet files are in MinIO on testhost. Use the [example query project](https://github.com/bytefreezer/query-example) or ask Claude:

```
Show me how to query the parquet files in my MinIO on testhost.
```

---

### Path C: On-Prem Kubernetes (Helm)

**What this does:** Deploys the full stack to a Kubernetes cluster using Helm. Your data stays in your cluster. No SSH needed — Claude uses `kubectl` and `helm` directly from your workstation.

**Prompt:**

```
Deploy ByteFreezer to my Kubernetes cluster with Helm.
Create an on_prem account called "my-k8s", a tenant "demo",
and a syslog dataset on port 5514. Use bundled MinIO.
Generate the Helm values and install the chart.
Then deploy fakedata and verify parquet output.
```

**What Claude does behind the scenes:**

1. `bf_create_account` with `type=on_prem`
2. `bf_create_tenant` and `bf_create_dataset`
3. `bf_generate_helm_values` with `scenario=full` — generates values.yaml
4. Writes values.yaml locally, runs `helm install`
5. Monitors pods with `kubectl get pods`, waits for healthy
6. `bf_account_services` — verifies all services registered
7. Deploys fakedata pod, assigns dataset to proxy
8. Verifies parquet output

**Variant — proxy on a remote host, stack in Kubernetes:**

```
Same as above, but deploy the proxy on testhost via SSH with Docker Compose
instead of inside the cluster. The rest of the stack stays in Kubernetes.
```

Claude uses `bf_generate_helm_values` for the cluster stack and `bf_generate_docker_compose` with `scenario=proxy` for the edge proxy, wiring the receiver URL from the Kubernetes LoadBalancer IP. It SSHs into testhost to deploy the proxy.

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
