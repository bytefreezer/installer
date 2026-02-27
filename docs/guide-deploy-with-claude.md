# How to Deploy ByteFreezer with Claude + MCP

Use Claude Code as your deployment assistant. Connect it to the ByteFreezer MCP server and tell it what you want — Claude handles account creation, config generation, deployment, and verification.

**Objective:** Instead of following a guide step by step, describe your deployment goal in plain English. Claude uses 63 ByteFreezer MCP tools to create accounts, tenants, datasets, generate deployment configs, and verify everything is working.

> **Do not send sensitive or production data to bytefreezer.com.** The control plane is a shared test platform. For on-prem deployments your data stays on your infrastructure, but the control plane is not secured for production use.

## What You Need

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A ByteFreezer account with an API key (or have Claude create one for you)
- A Linux host with Docker and Docker Compose (for managed or on-prem Docker Compose)
- Or a Kubernetes cluster with Helm 3 (for on-prem Kubernetes)

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

Start Claude Code and describe your deployment. Below are example prompts for each path.

---

### Path A: Managed (Proxy Only)

**What this does:** Deploys a single proxy on your host. Processing and storage run on bytefreezer.com. This is a proxy test — verify your proxy works and query parquet on the test platform.

**Prompt:**

```
I want to try ByteFreezer managed. Create an account called "my-test",
create a tenant "demo" with a syslog dataset on port 5514,
then generate a docker-compose setup for the proxy and deploy it on this host.
After it's running, assign the dataset to the proxy and send some test data
with fakedata to verify the pipeline works.
```

**What Claude does behind the scenes:**

1. `bf_create_account` — creates account, saves account ID and API key
2. `bf_create_tenant` — creates tenant under the account
3. `bf_create_dataset` — creates syslog dataset with managed S3 output
4. `bf_generate_docker_compose` with `scenario=proxy` — generates docker-compose.yml, .env, and proxy config
5. Writes the files to disk, runs `docker compose up -d`
6. Waits for the proxy to register, then `bf_update_dataset_proxy_assignment`
7. Runs fakedata container to generate test syslog
8. `bf_dataset_statistics` — verifies events are flowing
9. Reports back what happened

**Verify:** Ask Claude:

```
Check my deployment health and show me the dataset statistics.
```

Claude uses `bf_health_status`, `bf_dataset_statistics`, and `bf_dataset_parquet_files` to give you a full status report.

---

### Path B: On-Prem Docker Compose (Full Stack)

**What this does:** Deploys the complete stack (proxy, receiver, piper, packer, MinIO) on a single host. Your data stays on your host. Control plane on bytefreezer.com for coordination.

**Prompt:**

```
Deploy a full on-prem ByteFreezer stack with Docker Compose on this host.
Create an on_prem account called "my-onprem", a tenant "demo",
and a syslog dataset on port 5514. Include MinIO for storage.
After everything is running, start fakedata and verify data flows
all the way to parquet.
```

**What Claude does behind the scenes:**

1. `bf_create_account` with `type=on_prem`
2. `bf_create_tenant` and `bf_create_dataset`
3. `bf_generate_docker_compose` with `scenario=full` — generates docker-compose.yml with all services, .env, and config files for proxy, receiver, piper, packer
4. Writes all files, runs `docker compose up -d`
5. `bf_account_services` — waits for all four services to register healthy
6. Assigns dataset to proxy, starts fakedata
7. `bf_dataset_statistics` and `bf_dataset_parquet_files` — verifies parquet output

**Query your data:** Your parquet files are in your local MinIO. Use the [example query project](https://github.com/bytefreezer/query-example) or ask Claude:

```
Show me how to query the parquet files in my local MinIO.
```

---

### Path C: On-Prem Kubernetes (Helm)

**What this does:** Deploys the full stack to a Kubernetes cluster using Helm. Your data stays in your cluster.

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
4. Writes values.yaml, runs `helm install`
5. Monitors pods with `kubectl get pods`, waits for healthy
6. `bf_account_services` — verifies all services registered
7. Deploys fakedata pod, assigns dataset to proxy
8. Verifies parquet output

**Variant — proxy outside the cluster:**

```
Same as above, but deploy the proxy on this host with Docker Compose
instead of inside the cluster. The rest of the stack stays in Kubernetes.
```

Claude uses `bf_generate_helm_values` for the cluster stack and `bf_generate_docker_compose` with `scenario=proxy` for the edge proxy, wiring the receiver URL from the Kubernetes LoadBalancer IP.

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

**Claude can't run Docker/kubectl:**
- Claude Code needs shell access to deploy on your host
- Make sure Docker and kubectl are available in your PATH
- Grant Claude permission to run shell commands when prompted

**Want to disconnect the MCP server:**
```bash
claude mcp remove bytefreezer
```
