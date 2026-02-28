# Deploy On-Prem (Docker Compose) with Claude + MCP

Deploy the complete ByteFreezer stack on a single host using Claude as your deployment assistant. Your data stays on your host. Control plane on bytefreezer.com for coordination.

> **Prefer step-by-step manual instructions?** See [On-Prem Docker Compose Guide](guide-onprem-docker-compose.md).

> **Do not send sensitive or production data to bytefreezer.com.** The control plane is a shared test platform. Your data stays on your host, but the control plane is not secured for production use.

---

## What You Need

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on your workstation
- A Linux target host ("testhost") with Docker and Docker Compose
- SSH access from your workstation to testhost (key-based, no password prompts)

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

Claude will SSH into your target host to write config files and run Docker commands. Set up key-based SSH so Claude can connect without password prompts:

```bash
# If you don't have an SSH key yet
ssh-keygen -t ed25519

# Copy your key to the target host
ssh-copy-id testhost

# Verify passwordless access
ssh testhost "hostname && docker --version && docker compose version"
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
|   +-- SSH --------|------> testhost              (full stack: proxy, receiver,
+------------------+                                piper, packer, minio)
```

Tell Claude what you want. Include the target host so Claude knows where to deploy:

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

---

## Step 7: Verify

Ask Claude to check the full pipeline:

```
Check all service health, show dataset statistics, and list parquet files.
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
Show me the schema of my dataset, then create a transformation to
rename source_ip to src, add a field environment="docker-test",
and filter out events where action is "heartbeat".
Test it first, then activate it.
```

```
Show me what filters are available in the transformation catalog.
```

### Test the Kill Switch

```
Pause the dataset, wait 30 seconds, then resume it. Show me the proxy
config before and after to confirm the kill switch works.
```

### Query Your Data

Parquet files are in MinIO on testhost. Use the [example query project](https://github.com/bytefreezer/query-example) or ask Claude:

```
Show me how to query the parquet files in my MinIO on testhost.
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

**SSH connection fails:**
```bash
ssh testhost "echo ok"
# If prompted for password, run: ssh-copy-id testhost
```

**Claude can't run Docker on remote host:**
```bash
ssh testhost "docker --version && docker compose version"
# If permission denied: ssh testhost "sudo usermod -aG docker $USER"
```

**Want to disconnect the MCP server:**
```bash
claude mcp remove bytefreezer
```
