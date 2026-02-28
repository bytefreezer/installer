# How to Try ByteFreezer with a Managed Account

Deploy a single proxy on your host and use the managed platform for everything else.
All processing and storage runs on bytefreezer.com — you only install the proxy.

> **Prefer AI-assisted deployment?** See [Deploy Managed Proxy with Claude + MCP](guide-deploy-with-claude-managed.md) — describe what you want in plain English and Claude handles the rest.

**Objective:** End-to-end test on the managed test platform. Verify your proxy is working, data flows through the pipeline, and you can see and query parquet files directly on bytefreezer.com.

**Time to complete:** 10-15 minutes.

> **Do not send sensitive or production data.** This is a shared test platform and is not secured for production use. Use fakedata or non-sensitive test logs only.

## What You Need

- A Linux host with Docker and Docker Compose ("testhost")
- Network access from testhost to bytefreezer.com on HTTPS (receiver and control API)
- A web browser

## Architecture

```
testhost                              bytefreezer.com (managed)
+-----------+    HTTPS POST       +----------+     +-------+     +-------+     +--------+
|   Proxy   | -----------------> | Receiver | --> | Piper | --> | Packer | --> | MinIO  |
+-----------+                    +----------+     +-------+     +-------+     +--------+
      ^                                                                            |
      |                                                                            v
 fakedata                                                                    Parquet files
 (syslog)                                                              (query via dashboard)
```

---

## Phase 1: Create Account and Configure

### Step 1 — Log in to bytefreezer.com

Open https://bytefreezer.com in your browser. Log in as system administrator.

### Step 2 — Create a new account

Navigate to **Accounts** and create a new account:

| Field | Value |
|-------|-------|
| Name | `test-managed` |
| Email | your email |
| Deployment Type | `managed` |

Note the **Account ID** from the response.

### Step 3 — Generate an API key

Navigate to **API Keys** for the new account and generate one.
Copy the **API Key** — it is shown only once. You will use this in the proxy config.

### Step 4 — Create a tenant

Navigate to **Tenants** (under the new account) and create:

| Field | Value |
|-------|-------|
| Name | `demo` |

Note the **Tenant ID**.

### Step 5 — Create a dataset

Navigate to **Datasets** (under the new tenant) and create with the following config:

| Field | Value |
|-------|-------|
| Name | `syslog-test` |
| Active | Yes |
| Testing | Yes |

> **Testing mode** tells the packer to process data immediately instead of waiting for
> accumulation thresholds (128MB or 20 minutes). Enable it to see parquet output within minutes.
> Turn it off for production use.

Configure the dataset source and destination:

**Source config:**
```json
{
  "type": "syslog",
  "custom": {
    "port": 5514,
    "host": "0.0.0.0"
  }
}
```

**Destination config (S3/MinIO output):**

For managed accounts using bytefreezer.com storage:

```json
{
  "type": "s3",
  "connection": {
    "endpoint": "localhost:9000",
    "bucket": "packer",
    "region": "us-east-1",
    "ssl": false,
    "credentials": {
      "type": "static",
      "access_key": "YOUR_MINIO_ACCESS_KEY",
      "secret_key": "YOUR_MINIO_SECRET_KEY"
    }
  }
}
```

> **Important:** Both source AND destination must be configured at creation time. If you
> update them later, send both together — config sub-objects are replaced entirely on update.

Do NOT assign a proxy yet — we will do that after the proxy registers.

**Verify:** Dataset appears in the Datasets list. Run "Test Dataset" — input should show
"Plugin configured" and output should show "S3 connection successful".

---

## Phase 2: Deploy Proxy on Testhost

### Step 6 — Prepare the host

SSH to testhost and set up UDP buffer size for syslog:

```bash
ssh testhost

# Increase UDP buffer size (prevents "UDP buffer limited by kernel" warnings)
sudo sysctl -w net.core.rmem_max=16777216
# Make persistent across reboots:
echo "net.core.rmem_max=16777216" | sudo tee -a /etc/sysctl.conf

mkdir -p ~/bytefreezer-proxy/config
cd ~/bytefreezer-proxy
```

### Step 7 — Create proxy config

Replace `YOUR_ACCOUNT_ID` and `YOUR_API_KEY` with values from Steps 2-3:

```bash
cat > config/proxy.yaml << 'EOF'
app:
  name: "bytefreezer-proxy"
  version: "1.0.0"

account_id: "YOUR_ACCOUNT_ID"
bearer_token: "YOUR_API_KEY"
control_url: "https://api.bytefreezer.com"
config_mode: "control-only"

server:
  api_port: 8008

receiver:
  base_url: "https://receiver.bytefreezer.com"

config_polling:
  enabled: true
  interval_seconds: 30
  timeout_seconds: 10
  retry_on_error: true

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

error_tracking:
  enabled: true
EOF
```

> **Config field reference:**
> - `account_id` — required, from Step 2
> - `bearer_token` — required, the API key from Step 3
> - `control_url` — the control API, always `https://api.bytefreezer.com`
> - `config_mode: "control-only"` — proxy fetches dataset config from control API
> - `receiver.base_url` — where proxy sends data, always `https://receiver.bytefreezer.com`

### Step 8 — Create docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
services:
  proxy:
    image: ghcr.io/bytefreezer/bytefreezer-proxy:latest
    container_name: bytefreezer-proxy
    ports:
      - "8008:8008"
      - "5514:5514/udp"
    volumes:
      - ./config/proxy.yaml:/etc/bytefreezer-proxy/config.yaml:ro
      - proxy-spool:/var/spool/bytefreezer-proxy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8008/api/v1/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  fakedata:
    image: ghcr.io/bytefreezer/bytefreezer-fakedata:latest
    container_name: bytefreezer-fakedata
    network_mode: host
    command: ["syslog", "--host", "127.0.0.1", "--port", "5514", "--rate", "10"]
    restart: unless-stopped
    depends_on:
      proxy:
        condition: service_started

volumes:
  proxy-spool:
EOF
```

> **Notes:**
> - Config mounts to `/etc/bytefreezer-proxy/config.yaml` (the image default path)
> - Healthcheck uses `wget` (not `curl`) — the minimal image may not have curl
> - Fakedata uses `network_mode: host` to reach the proxy's published UDP port

### Step 9 — Start everything

```bash
docker compose up -d
```

**Verify:**

```bash
docker compose ps
# Should show both containers running

docker compose logs proxy --tail 20
# Look for: "Health report sent successfully"
# Look for: "Registered with control service"
# Look for: "Config polling" — dataset config received from control

docker compose logs fakedata --tail 5
# Should show syslog messages being sent
```

### Step 10 — Verify proxy appears on dashboard

Go to bytefreezer.com **Service Status** page.

**Verify:** The proxy instance appears with status "Healthy" under your account.

### Step 11 — Assign dataset to proxy

Go to **Datasets** → `syslog-test` → Edit.
Set **Assigned Proxy** to the proxy instance that just registered.
Save.

**Verify:** Dataset shows the assigned proxy ID. Within 30 seconds (next config poll), the proxy picks up the dataset and starts the syslog plugin.

Check proxy logs:
```bash
docker compose logs proxy | grep -i "syslog\|plugin\|listening"
# Should show: syslog plugin started, listening on 0.0.0.0:5514
```

> **Deployment is complete.** Your proxy is running and assigned to a dataset. Data will
> begin flowing within 30 seconds. Continue below to verify the pipeline and explore features,
> or go directly to [Statistics](https://bytefreezer.com/dashboard/statistics) and
> [Audit Log](https://bytefreezer.com/dashboard/audit-logs) on the dashboard.

---

## Phase 3: Verify the Pipeline

### Step 12 — Check proxy is forwarding data

```bash
docker compose logs proxy --tail 20 | grep -i "batch\|forward\|sent"
# Should show batches being compressed and sent to the receiver
```

If you see TLS or connection errors, check:
```bash
# Test connectivity from the host (not inside container)
curl -s https://receiver.bytefreezer.com
curl -s https://api.bytefreezer.com/api/v1/health
```

### Step 13 — Check Statistics page

On bytefreezer.com, navigate to **Statistics**.

**Verify:**
- Events received counter is increasing
- Proxy card shows activity
- Receiver card shows intake
- Piper card shows processing

### Step 14 — Check for parquet output

Since the dataset has **testing mode** enabled, the packer processes data on each housekeeping
cycle (~5 minutes) without waiting for accumulation thresholds.

Navigate to **Activity** page.

**Verify:**
- Piper processing entries appear
- Packer entries show "testing mode — bypassing accumulation" and successful parquet upload

Check parquet files:
- Go to **Datasets** → `syslog-test` → **Parquet Files** tab
- Or check MinIO console at bytefreezer.com:9001

| Bucket | Contains | Meaning |
|--------|----------|---------|
| `bytefreezer-intake` | `.ndjson.gz` files | Receiver stored raw data |
| `bytefreezer-piper` | `.ndjson` files | Piper processed data |
| `packer` | `.parquet` files | Packer produced final output |

### Step 15 — Check Service Status and Audit Log

Navigate to **Service Status** page.

**Verify:**
- Your proxy (`tiny:8008` or similar) shows as **Healthy** under your account
- Shared managed services (control, receiver, piper, packer) all show Healthy
- The proxy shows its version, uptime, CPU/memory metrics, and last-seen timestamp

Navigate to **Audit Log** page.

**Verify:**
- Entries for account creation, API key generation, tenant creation, dataset creation
- Entry for dataset proxy assignment
- Entry for proxy service registration
- Each entry shows who performed the action and when

> Every API and dashboard action is recorded in the audit log — configuration changes,
> service registrations, key management. This provides a full trail of what happened and when.

### Step 16 — Query parquet data

Navigate to **Query** page on bytefreezer.com.

Select the dataset and run a query. You should see the fake syslog events with fields like
`source_ip`, `dest_ip`, `action`, `username`, etc.

**Verify:** Query returns rows matching the fakedata events.

---

## Phase 4: Explore Features

### Step 17 — Add a transformation

Go to **Datasets** → `syslog-test` → **Pipeline** tab.

Add a transformation, for example:
- **Rename field:** `source_ip` → `src`
- **Add field:** `environment` = `"test"`
- **Filter:** drop events where `action` = `"heartbeat"` (if any)

Save. Wait for piper to pick up the new config (up to 5 minutes).

**Verify:** Run a query. New events should have the renamed/added fields. Old events remain unchanged.

### Step 18 — Enable GeoIP enrichment (if GeoIP database available)

Go to **Datasets** → `syslog-test` → **Pipeline** tab.

Enable GeoIP enrichment on the `source_ip` field.

**Verify:** New events include `source_ip_geo_country`, `source_ip_geo_city`, etc.

### Step 19 — Disable testing mode

Once you've verified the pipeline works, disable testing mode for production behavior:

Go to **Datasets** → `syslog-test` → Edit → set **Testing** to No.

The packer will now accumulate data until 128MB or 20 minutes before producing parquet files,
resulting in larger, more efficient output files.

---

## Deployment Complete

Your managed proxy is running and producing parquet data. See **[What Happens After Deployment](guide-post-deployment.md)** to understand:
- What you're looking at on the dashboard
- How to play with transformations and GeoIP enrichment
- How this demo differs from a production on-prem deployment
- What the "final mile" to your SIEM looks like

---

## Phase 5: Cleanup

### Stop everything

```bash
cd ~/bytefreezer-proxy
docker compose down -v
```

### Remove test account (optional)

On bytefreezer.com, delete the `test-managed` account.

---

## Troubleshooting

**Proxy not registering with control:**
```bash
docker compose logs proxy | grep -i "control\|auth\|401\|403"
# Check: account_id and bearer_token in proxy.yaml match the account and API key
# Check: control_url is https://api.bytefreezer.com (not http)
```

**Proxy cannot reach receiver:**
```bash
curl -v https://receiver.bytefreezer.com
# If connection refused: check DNS, check receiver is running on bytefreezer.com
```

**"UDP buffer limited by kernel" warnings:**
```bash
sudo sysctl -w net.core.rmem_max=16777216
```

**No data in Statistics:**
- Wait 1-2 minutes for health report cycle
- Check proxy logs for errors
- Verify dataset is assigned to the proxy
- Verify dataset is active (not paused)
- Verify fakedata is running and sending to the correct port

**Piper not processing:**
- Check piper logs on bytefreezer.com: `sudo journalctl -u bytefreezer-piper -f`
- Verify data exists in intake bucket
- Check dataset has processing enabled

**No parquet files:**
- If testing mode OFF: packer waits for 128MB or 20 minutes. Enable testing mode for faster output.
- If testing mode ON: packer processes on each housekeeping cycle (~5 min). Wait one cycle.
- Check packer logs: `sudo journalctl -u bytefreezer-packer -f`
- Verify dataset has S3 destination configured (endpoint, bucket, credentials)
- Verify data exists in piper bucket

**Dataset update wiped source/destination config:**
- The update API replaces entire sub-objects. Always send the full config.source AND
  config.destination together when updating either one.
