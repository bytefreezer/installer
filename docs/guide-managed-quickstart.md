# How to Try ByteFreezer with a Managed Account

Deploy a single proxy on your host and use the managed platform for everything else.
All processing and storage runs on bytefreezer.com — you only install the proxy.

**Image tag:** `v1.0.0-rc.0225b`

## What You Need

- A Linux host with Docker and Docker Compose ("tiny")
- Network access from tiny to bytefreezer.com on HTTPS (receiver and control API)
- A web browser

## Architecture

```
tiny                              bytefreezer.com (managed)
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

Note the **Account ID** from the response. Copy the **API Key** — it is shown only once.

**Verify:** The account appears in the Accounts list.

### Step 3 — Create a tenant

Navigate to **Tenants** (under the new account) and create:

| Field | Value |
|-------|-------|
| Name | `demo` |

Note the **Tenant ID**.

**Verify:** Tenant appears in the Tenants list.

### Step 4 — Create a dataset

Navigate to **Datasets** (under the new tenant) and create:

| Field | Value |
|-------|-------|
| Name | `syslog-test` |
| Active | Yes |

Configure the dataset:
- **Input:** syslog, port `5514`
- **Output S3:** endpoint `localhost:9000`, bucket `packer`, access key and secret key from bytefreezer.com MinIO config, SSL off

Do NOT assign a proxy yet — we will do that after the proxy registers.

**Verify:** Dataset appears in the Datasets list with status "active".

---

## Phase 2: Deploy Proxy on Tiny

### Step 5 — Create project directory

SSH to tiny:

```bash
ssh tiny
mkdir -p ~/bytefreezer-proxy/config
cd ~/bytefreezer-proxy
```

### Step 6 — Create docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
services:
  proxy:
    image: ghcr.io/bytefreezer/bytefreezer-proxy:v1.0.0-rc.0225b
    container_name: bytefreezer-proxy
    ports:
      - "8008:8008"
      - "5514:5514/udp"
    environment:
      PROXY_CONTROL_SERVICE_API_KEY: ${CONTROL_API_KEY}
    volumes:
      - ./config/proxy.yaml:/etc/bytefreezer/config.yaml:ro
      - proxy-spool:/var/spool/bytefreezer-proxy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8008/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

volumes:
  proxy-spool:
EOF
```

### Step 7 — Create .env

Replace `YOUR_API_KEY` with the key from Step 2:

```bash
cat > .env << 'EOF'
CONTROL_API_KEY=YOUR_API_KEY
EOF
```

### Step 8 — Create proxy config

```bash
cat > config/proxy.yaml << 'EOF'
app:
  name: "bytefreezer-proxy"
  version: "1.0.0"

server:
  api_port: 8008

receiver:
  url: "https://receiver.bytefreezer.com"

control_service:
  enabled: true
  control_url: "https://api.bytefreezer.com"
  timeout_seconds: 30

udp:
  enabled: true
  ports:
    - port: 5514
      name: syslog

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
EOF
```

### Step 9 — Start the proxy

```bash
docker compose up -d
```

**Verify:**

```bash
docker compose ps
# Should show: bytefreezer-proxy  healthy

docker compose logs proxy | head -20
# Look for: "Health report sent successfully"
# Look for: "Registered with control service"
```

### Step 10 — Verify proxy appears on dashboard

Go to bytefreezer.com **Service Status** page.

**Verify:** The proxy instance appears with status "Healthy" under your test-managed account.

### Step 11 — Assign dataset to proxy

Go to **Datasets** → `syslog-test` → Edit.
Set **Assigned Proxy** to the proxy instance that just registered.
Save.

**Verify:** Dataset shows the assigned proxy ID.

---

## Phase 3: Generate Test Data

### Step 12 — Run fakedata

On tiny, in a separate terminal:

```bash
docker run --rm --network host \
  ghcr.io/bytefreezer/bytefreezer-fakedata:latest \
  syslog --host 127.0.0.1 --port 5514 --rate 10
```

This sends 10 syslog messages per second to the proxy.

**Verify:**

```bash
# Check proxy is receiving data
docker compose logs proxy --tail 20
# Look for: batch/plugin activity, forwarding to receiver
```

### Step 13 — Verify proxy forwards to receiver

```bash
docker compose logs proxy | grep -i "forward\|batch\|sent"
# Should show batches being sent to the receiver
```

If you see connection errors to the receiver, check:
- Can you reach it? `curl -s https://receiver.bytefreezer.com` from tiny
- DNS resolving? `dig receiver.bytefreezer.com`

---

## Phase 4: Verify the Pipeline

### Step 14 — Check Statistics page

On bytefreezer.com, navigate to **Statistics**.

**Verify:**
- Events received counter is increasing
- Proxy card shows activity
- Receiver card shows intake
- Piper card shows processing (if data has been processed)
- Packer card shows parquet output (after packing cycle)

### Step 15 — Check Activity page

Navigate to **Activity**.

**Verify:**
- Piper processing entries appear
- Packer accumulation entries appear (may take a few minutes)

### Step 16 — Check MinIO buckets

Access MinIO console on bytefreezer.com (port 9001) or use `mc`:

**Verify these buckets have data:**

| Bucket | Contains | Meaning |
|--------|----------|---------|
| `bytefreezer-intake` | `.jsonl.snappy` files | Receiver stored raw data |
| `bytefreezer-piper` | `.jsonl` files | Piper processed data |
| `packer` (or tenant bucket) | `.parquet` files | Packer produced final output |

### Step 17 — Query parquet data

Navigate to **Query** page on bytefreezer.com.

Select the dataset and run a query. You should see the fake syslog events with fields like `source_ip`, `dest_ip`, `action`, `username`, etc.

**Verify:** Query returns rows matching the fakedata events.

---

## Phase 5: Explore Features

### Step 18 — Add a transformation

Go to **Datasets** → `syslog-test` → **Pipeline** tab.

Add a transformation, for example:
- **Rename field:** `source_ip` → `src`
- **Add field:** `environment` = `"test"`
- **Filter:** drop events where `action` = `"heartbeat"` (if any)

Save the dataset. Wait for piper to pick up the new config (up to 5 minutes).

**Verify:** Run a query. New events should have the renamed/added fields. Old events remain unchanged.

### Step 19 — Enable GeoIP enrichment (if GeoIP database available)

Go to **Datasets** → `syslog-test` → **Pipeline** tab.

Enable GeoIP enrichment on the `source_ip` field.

**Verify:** New events include `source_ip_geo_country`, `source_ip_geo_city`, etc.

### Step 20 — Check parquet files

After the packer cycle completes (check Activity page), verify that new parquet files contain the transformed fields.

**Verify:** Query returns events with transformation applied and GeoIP data (if enabled).

---

## Phase 6: Cleanup

### Stop fakedata

`Ctrl+C` the fakedata container.

### Stop proxy

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
docker compose logs proxy | grep -i control
# Check API key is correct in .env
# Check control_url in proxy.yaml
```

**Proxy cannot reach receiver:**
```bash
curl -v https://receiver.bytefreezer.com
# If connection refused: check DNS, check receiver is running on bytefreezer.com
```

**No data in Statistics:**
- Wait 1-2 minutes for health report cycle
- Check proxy logs for errors
- Verify dataset is assigned to the proxy
- Verify dataset is active (not paused)

**Piper not processing:**
- Check piper logs on bytefreezer.com: `journalctl -u bytefreezer-piper -f`
- Verify data exists in intake bucket
- Check dataset has processing enabled

**No parquet files:**
- Packer runs on a cycle (housekeeping interval). Wait a few minutes.
- Check packer logs: `journalctl -u bytefreezer-packer -f`
- Verify data exists in piper bucket
