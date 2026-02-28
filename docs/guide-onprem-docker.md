# ByteFreezer On-Prem Deployment (Docker Compose)

Deploy the complete ByteFreezer processing stack on a single host. Control plane runs on bytefreezer.com for coordination. Processing, storage, and proxy are all self-hosted -- your data stays on your host.

**Objective:** End-to-end test of the full on-prem stack. Verify all services register, data flows from proxy through receiver/piper/packer, and parquet files land in your local MinIO. To query your parquet data, use the [example query project](https://github.com/bytefreezer/query-example) or build your own using AI and [ByteFreezer MCP](https://github.com/bytefreezer/mcp).

**Time to complete:** 15-20 minutes (manual), 10-15 minutes (Claude + MCP).

> **Do not send sensitive or production data to bytefreezer.com.** The control plane on bytefreezer.com is a shared test platform. Your data stays on your host, but the control plane is not secured for production use.

---

## What You Need

**Both methods:**

- A Linux host with Docker and Docker Compose ("testhost")
  - Minimum: 4 GB RAM, 20 GB disk
- Network access from testhost to api.bytefreezer.com on HTTPS (control API)
- A web browser

**Additional for Method B (Claude + MCP):**

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed on your workstation
- SSH access from your workstation to testhost (key-based, no password prompts)

---

## Architecture

```
testhost (self-hosted)
+----------+    UDP     +-----------+    HTTP     +----------+     +-------+
| fakedata | ---------> |   Proxy   | ---------> | Receiver |     | MinIO |
+----------+  syslog    +-----------+   POST     +----+-----+     +---+---+
                                                      |               |
                                              writes to S3       all buckets
                                                      |               |
                                                      v               v
                                                 +----+----+    +---------+
                                                 |  Piper  |--->|  intake |
                                                 +----+----+    |  piper  |
                                                      |         |  packer |
                                                      v         |  geoip  |
                                                 +----+----+    +---------+
                                                 | Packer  |
                                                 +---------+
                                                      |
                                                      v
                                                 .parquet files

bytefreezer.com (control plane only)
+------------------------------------------+
| Control API: config, health, coordination |
+------------------------------------------+
```

---

## Choose Your Deployment Method

- **[Method A: Step-by-Step Manual](#method-a-step-by-step-manual)** -- Follow the instructions yourself using the dashboard and terminal.
- **[Method B: Deploy with Claude + MCP](#method-b-deploy-with-claude--mcp)** -- Tell Claude what you want in plain English; it handles the API calls, file creation, and deployment.

---

# Method A: Step-by-Step Manual

Follow each step yourself using the bytefreezer.com dashboard and SSH to your testhost.

## Phase 1: Create Account on bytefreezer.com

### Step 1 -- Log in to bytefreezer.com

Open https://bytefreezer.com. Log in as system administrator.

### Step 2 -- Create a new account

Navigate to **Accounts** and create:

| Field | Value |
|-------|-------|
| Name | `test-onprem-docker` |
| Email | your email |
| Deployment Type | `on_prem` |

Copy the **Account ID** and **API Key** (shown only once).

**Verify:** Account appears in the Accounts list.

## Phase 2: Deploy the Stack on Testhost

### Step 3 -- Clone or copy the installer

SSH to testhost:

```bash
ssh testhost

# Option A: Clone the repo
git clone https://github.com/bytefreezer/installer.git
cd installer/docker/quick-start

# Option B: Or just create the files manually (see below)
```

### Step 4 -- Configure .env

Edit the `.env` file:

```bash
cp .env .env.backup  # if cloned

cat > .env << 'EOF'
IMAGE_REGISTRY=ghcr.io/bytefreezer
IMAGE_TAG=latest

CONTROL_URL=https://api.bytefreezer.com
CONTROL_API_KEY=YOUR_API_KEY_HERE
ACCOUNT_ID=YOUR_ACCOUNT_ID_HERE

S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
EOF
```

Replace `YOUR_API_KEY_HERE` and `YOUR_ACCOUNT_ID_HERE` with values from Step 2.

### Step 5 -- Verify config files

The quick-start directory should contain these config files:

```
config/
  proxy.yaml      # receiver.url = http://receiver:8080
  receiver.yaml   # s3.endpoint = minio:9000
  piper.yaml      # s3 endpoints = minio:9000
  packer.yaml     # s3source.endpoint = minio:9000
```

**Verify:** All configs point S3 to `minio:9000` (Docker network name).
**Verify:** proxy.yaml has `receiver.url: "http://receiver:8080"`.

### Step 6 -- Start the stack

```bash
docker compose up -d
```

### Step 7 -- Verify all services are running

```bash
docker compose ps
```

**Expected output (all healthy):**

| Container | Ports | Status |
|-----------|-------|--------|
| bf-minio | 9000, 9001 | healthy |
| bf-receiver | 8080, 8081 | healthy |
| bf-piper | 8082 | healthy |
| bf-packer | 8083 | healthy |
| bf-proxy | 8008, 5514/udp | healthy |
| bf-fakedata | -- | running (restarts until dataset configured) |

Note: bf-fakedata will restart repeatedly until a dataset is configured and proxy starts accepting syslog. This is expected.

### Step 8 -- Verify MinIO buckets

Open http://testhost:9001 in your browser (or replace `testhost` with the host IP).
Login: `minioadmin` / `minioadmin`.

**Verify:** Four buckets exist: `intake`, `piper`, `packer`, `geoip`.

### Step 9 -- Verify services registered with control

On bytefreezer.com, go to **Service Status** page.

**Verify:** All four services appear under your `test-onprem-docker` account:
- bytefreezer-proxy (Healthy)
- bytefreezer-receiver (Healthy)
- bytefreezer-piper (Healthy)
- bytefreezer-packer (Healthy)

If services don't appear after 60 seconds, check logs:

```bash
docker compose logs receiver | grep -i "control\|register"
docker compose logs proxy | grep -i "control\|register"
```

## Phase 3: Configure Dataset

### Step 10 -- Create a tenant

On bytefreezer.com, navigate to **Tenants** (under `test-onprem-docker` account) and create:

| Field | Value |
|-------|-------|
| Name | `demo` |

### Step 11 -- Create a dataset

Navigate to **Datasets** (under `demo` tenant) and create:

| Field | Value |
|-------|-------|
| Name | `syslog-test` |
| Active | Yes |

Configure the dataset:

**Input:**
- Type: syslog
- Port: `5514`

**Output S3:**
- Endpoint: `minio:9000` (this is from packer's perspective inside Docker network)
- Bucket: `packer`
- Access Key: `minioadmin`
- Secret Key: `minioadmin`
- SSL: off
- Region: `us-east-1`

### Step 12 -- Assign to proxy

Edit the dataset and set **Assigned Proxy** to the proxy instance that registered.

**Verify:** Dataset shows assigned proxy ID.

### Step 13 -- Wait for config sync

The proxy polls control every 30 seconds. Wait 1-2 minutes.

**Verify:**

```bash
docker compose logs proxy --tail 20
# Look for: plugin configuration received, syslog listener started on 5514
```

## Phase 4: Verify Data Flow

### Step 14 -- Check fakedata is sending

```bash
docker compose logs fakedata --tail 10
# Should show: "Sending syslog data to proxy:5514 at 10 msg/s"
```

If fakedata was previously crashing (before dataset was configured), it should now be running steadily.

### Step 15 -- Check proxy receives data

```bash
docker compose logs proxy --tail 20
# Look for: batch activity, forwarding to receiver
```

### Step 16 -- Check receiver stores to S3

```bash
docker compose logs receiver --tail 20
# Look for: "stored to S3", file writes to intake bucket
```

**Verify in MinIO:** Open http://testhost:9001 -> `intake` bucket.
Files should appear with `.jsonl.snappy` extension within 30-60 seconds.

### Step 17 -- Check piper processes data

```bash
docker compose logs piper --tail 20
# Look for: processing files from intake, writing to piper bucket
```

**Verify in MinIO:** `piper` bucket should have `.jsonl` files.

### Step 18 -- Check packer produces parquet

```bash
docker compose logs packer --tail 20
# Look for: packing, parquet file written
```

**Verify in MinIO:** `packer` bucket should have `.parquet` files.
This may take a few minutes depending on packer's housekeeping interval.

### Step 19 -- Check Statistics page

On bytefreezer.com, navigate to **Statistics** (under your account).

**Verify:**
- Events received counter increasing
- All four service cards show activity
- No error indicators

### Step 20 -- Check Activity page

Navigate to **Activity**.

**Verify:**
- Piper processing entries visible
- Packer accumulation entries visible

### Step 21 -- Query parquet data

Navigate to **Query** page on bytefreezer.com.

Run a query against your dataset. You should see fake syslog events.

**Verify:** Query returns rows with fields like `source_ip`, `dest_ip`, `action`, `username`, `bytes_sent`, etc.

## Phase 5: Explore Features

### Step 22 -- Add transformations

Go to **Datasets** -> `syslog-test` -> **Pipeline** tab.

Add transformations:
- **Rename:** `source_ip` -> `src`
- **Add field:** `environment` = `"test-docker"`
- **Filter:** keep only events where `action` = `"login"`

Save. Wait for piper to refresh config (up to 5 minutes).

**Verify:** Query new events -- renamed fields and added fields present. Filtered events excluded.

### Step 23 -- Enable GeoIP (optional)

If GeoIP databases are available in the `geoip` MinIO bucket:

1. Upload `GeoLite2-City.mmdb` and `GeoLite2-Country.mmdb` to `geoip` bucket
2. Enable GeoIP on `source_ip` in dataset pipeline config
3. Wait for piper to refresh

**Verify:** New events include `source_ip_geo_country`, `source_ip_geo_city`.

### Step 24 -- Test dataset pause (kill switch)

On bytefreezer.com, go to **Datasets** -> `syslog-test`.
Click the pause button.

**Verify:**
- Dataset shows "Paused" badge
- Proxy stops forwarding data for this dataset (check proxy logs)
- Statistics stop increasing

Resume the dataset.

**Verify:** Data flow resumes.

### Step 25 -- Verify end-to-end with parquet

After transformations are applied and packer has run:

1. Check `packer` bucket in MinIO for new `.parquet` files
2. Query the data on bytefreezer.com
3. Confirm transformed fields are in the parquet output

**Verify:** Parquet files contain transformed data.

---

# Method B: Deploy with Claude + MCP

Tell Claude what you want in plain English. Claude uses the ByteFreezer MCP tools to create resources on bytefreezer.com and SSH to deploy the full stack on your testhost.

## Claude + MCP Setup

### B1 -- Create a ByteFreezer Account

1. Go to [bytefreezer.com/register](https://bytefreezer.com/register)
2. Create your account with your email and password
3. Log in to the dashboard

### B2 -- Generate an API Key

1. In the dashboard, go to **Settings** -> **API Keys**
2. Click **Generate Key**
3. Copy the API key -- you will need it in the next step. It is shown only once.

### B3 -- Set Up SSH Access

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
Check the ByteFreezer health, list all accounts, and show the health summary.
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
2. `bf_generate_docker_compose` with `scenario=full` -- generates docker-compose.yml with all services, .env, and config files for proxy, receiver, piper, packer
3. SSHs into testhost, writes all files, runs `docker compose up -d`
4. `bf_account_services` -- waits for all four services to register healthy
5. Assigns dataset to proxy, starts fakedata via SSH
6. `bf_dataset_statistics` and `bf_dataset_parquet_files` -- verifies parquet output

## Verify with Claude

Ask Claude to check the full pipeline:

```
Check all service health, show dataset statistics, and list parquet files.
```

| Check | What Claude does |
|-------|-----------------|
| All services healthy | `bf_account_services` -- proxy, receiver, piper, packer all Healthy |
| Data flowing | `bf_dataset_statistics` -- events_in, events_out, bytes_processed increasing |
| Parquet output | `bf_dataset_parquet_files` -- lists `.parquet` files in packer bucket |

## Explore with Claude

### Transformations

```
Show me the schema of my dataset, then create a transformation to
rename source_ip to src, add a field environment="docker-test",
and filter out events where action is "heartbeat".
Test it first, then activate it.
```

```
Show me what filters are available in the transformation catalog.
```

### Kill Switch

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

---

## After Deployment

See **[What Happens After Deployment](guide-post-deployment.md)** for details on:
- What you are looking at on the dashboard
- How to play with transformations and GeoIP enrichment
- How data flows through each pipeline stage
- How to connect parquet output to your SIEM

---

## Cleanup

### Stop the stack

```bash
cd installer/docker/quick-start  # or wherever you set up
docker compose down -v
```

The `-v` flag removes all volumes (MinIO data, spool directories).

### Remove test account (optional)

On bytefreezer.com, delete the `test-onprem-docker` account.

---

## Troubleshooting

### Manual Deployment Issues

**Services not registering:**
```bash
docker compose logs <service> | grep -i "control\|register\|error"
# Check CONTROL_API_KEY and ACCOUNT_ID in .env
# Check control_url is set (env var CONTROL_URL should propagate)
```

**No data in intake bucket:**
```bash
docker compose logs receiver | grep -i "error\|s3\|store"
# Check S3 credentials match MinIO root user/password
# Check receiver can reach minio:9000 on Docker network
```

**Piper not processing:**
```bash
docker compose logs piper | grep -i "error\|poll\|process"
# Verify intake bucket has files
# Check dataset is active and has processing enabled
```

**Packer not producing parquet:**
```bash
docker compose logs packer | grep -i "error\|pack\|parquet"
# Verify piper bucket has files
# Check packer's housekeeping interval (default 60s in quick-start)
# Wait for at least one full cycle
```

**fakedata keeps crashing:**
```bash
docker compose logs fakedata
# Expected: restarts until dataset is configured and proxy accepts syslog
# If still crashing after dataset config: check proxy logs for plugin/listener status
```

**Port conflicts:**
```bash
# Check if ports are in use
ss -tlnp | grep -E '8080|8081|8082|8083|8008|5514|9000|9001'
# Stop conflicting services or change port mappings in docker-compose.yml
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

**SSH connection fails:**
```bash
ssh testhost "echo ok"
# If prompted for password, run: ssh-copy-id testhost
```

**Claude cannot run Docker on remote host:**
```bash
ssh testhost "docker --version && docker compose version"
# If permission denied: ssh testhost "sudo usermod -aG docker $USER"
```

**Want to disconnect the MCP server:**
```bash
claude mcp remove bytefreezer
```
