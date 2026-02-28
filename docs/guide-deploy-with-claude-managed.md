# Deploy Managed Proxy with Claude + MCP

Deploy a single proxy on your host using Claude as your deployment assistant. Processing and storage run on bytefreezer.com — you only install the proxy.

> **Prefer step-by-step manual instructions?** See [Managed Quickstart Guide](guide-managed-quickstart.md).

> **Do not send sensitive or production data to bytefreezer.com.** The control plane is a shared test platform.

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
|   +-- SSH --------|------> testhost              (docker compose, fakedata)
+------------------+
```

Tell Claude what you want. Include the target host so Claude knows where to deploy:

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

---

## Step 7: Verify

Ask Claude to check the pipeline:

```
Check my deployment health and show me the dataset statistics.
```

| Check | What Claude does |
|-------|-----------------|
| Service health | `bf_health_summary` + `bf_account_services` — proxy healthy |
| Dataset stats | `bf_dataset_statistics` — events received count increasing |
| Parquet files | `bf_dataset_parquet_files` — `.parquet` files exist in output bucket |

---

## After Deployment

### Explore Transformations

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

New events will have `src` instead of `source_ip`, and include `environment: "test"`.

### Test the Kill Switch

```
Pause my syslog-test dataset, then check proxy config to confirm it stopped.
After 30 seconds, resume it.
```

Claude uses `bf_update_dataset` to toggle status, and `bf_get_proxy_config` to confirm the proxy dropped the dataset from its active config.

### What Else Can Claude Do?

| Ask Claude to... | Tools it uses |
|---|---|
| "Show me the schema of my dataset" | `bf_transformation_schema` |
| "Test this transformation config before deploying" | `bf_test_transformation` |
| "Check which services are healthy" | `bf_health_status`, `bf_health_summary` |
| "List my parquet files" | `bf_dataset_parquet_files` |
| "Pause the dataset" | `bf_update_dataset` |
| "Show me what filters are available" | `bf_filter_catalog` |

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
