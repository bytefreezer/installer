# How to Deploy ByteFreezer On-Prem with Docker Compose

Deploy the complete ByteFreezer processing stack on a single host.
Control plane runs on bytefreezer.com. Processing, storage, and proxy are all self-hosted.

**Image tag:** `v1.0.0-rc.0225b`

## What You Need

- A Linux host with Docker and Docker Compose ("tiny")
  - Minimum: 4 GB RAM, 20 GB disk
- Network access from tiny to api.bytefreezer.com on HTTPS (control API)
- A web browser

## Architecture

```
tiny (self-hosted)
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

## Phase 1: Create Account on bytefreezer.com

### Step 1 — Log in to bytefreezer.com

Open https://bytefreezer.com. Log in as system administrator.

### Step 2 — Create a new account

Navigate to **Accounts** and create:

| Field | Value |
|-------|-------|
| Name | `test-onprem-docker` |
| Email | your email |
| Deployment Type | `on_prem` |

Copy the **Account ID** and **API Key** (shown only once).

**Verify:** Account appears in the Accounts list.

---

## Phase 2: Deploy the Stack on Tiny

### Step 3 — Clone or copy the installer

SSH to tiny:

```bash
ssh tiny

# Option A: Clone the repo
git clone https://github.com/bytefreezer/installer.git
cd installer/docker/quick-start

# Option B: Or just create the files manually (see below)
```

### Step 4 — Configure .env

Edit the `.env` file:

```bash
cp .env .env.backup  # if cloned

cat > .env << 'EOF'
IMAGE_REGISTRY=ghcr.io/bytefreezer
IMAGE_TAG=v1.0.0-rc.0225b

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

### Step 5 — Verify config files

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

### Step 6 — Start the stack

```bash
docker compose up -d
```

### Step 7 — Verify all services are running

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
| bf-fakedata | — | running (restarts until dataset configured) |

Note: bf-fakedata will restart repeatedly until a dataset is configured and proxy starts accepting syslog. This is expected.

### Step 8 — Verify MinIO buckets

Open http://tiny:9001 in your browser (or replace `tiny` with the host IP).
Login: `minioadmin` / `minioadmin`.

**Verify:** Four buckets exist: `intake`, `piper`, `packer`, `geoip`.

### Step 9 — Verify services registered with control

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

---

## Phase 3: Configure Dataset

### Step 10 — Create a tenant

On bytefreezer.com, navigate to **Tenants** (under `test-onprem-docker` account) and create:

| Field | Value |
|-------|-------|
| Name | `demo` |

### Step 11 — Create a dataset

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

### Step 12 — Assign to proxy

Edit the dataset and set **Assigned Proxy** to the proxy instance that registered.

**Verify:** Dataset shows assigned proxy ID.

### Step 13 — Wait for config sync

The proxy polls control every 30 seconds. Wait 1-2 minutes.

**Verify:**

```bash
docker compose logs proxy --tail 20
# Look for: plugin configuration received, syslog listener started on 5514
```

---

## Phase 4: Verify Data Flow

### Step 14 — Check fakedata is sending

```bash
docker compose logs fakedata --tail 10
# Should show: "Sending syslog data to proxy:5514 at 10 msg/s"
```

If fakedata was previously crashing (before dataset was configured), it should now be running steadily.

### Step 15 — Check proxy receives data

```bash
docker compose logs proxy --tail 20
# Look for: batch activity, forwarding to receiver
```

### Step 16 — Check receiver stores to S3

```bash
docker compose logs receiver --tail 20
# Look for: "stored to S3", file writes to intake bucket
```

**Verify in MinIO:** Open http://tiny:9001 → `intake` bucket.
Files should appear with `.jsonl.snappy` extension within 30-60 seconds.

### Step 17 — Check piper processes data

```bash
docker compose logs piper --tail 20
# Look for: processing files from intake, writing to piper bucket
```

**Verify in MinIO:** `piper` bucket should have `.jsonl` files.

### Step 18 — Check packer produces parquet

```bash
docker compose logs packer --tail 20
# Look for: packing, parquet file written
```

**Verify in MinIO:** `packer` bucket should have `.parquet` files.
This may take a few minutes depending on packer's housekeeping interval.

### Step 19 — Check Statistics page

On bytefreezer.com, navigate to **Statistics** (under your account).

**Verify:**
- Events received counter increasing
- All four service cards show activity
- No error indicators

### Step 20 — Check Activity page

Navigate to **Activity**.

**Verify:**
- Piper processing entries visible
- Packer accumulation entries visible

### Step 21 — Query parquet data

Navigate to **Query** page on bytefreezer.com.

Run a query against your dataset. You should see fake syslog events.

**Verify:** Query returns rows with fields like `source_ip`, `dest_ip`, `action`, `username`, `bytes_sent`, etc.

---

## Phase 5: Explore Features

### Step 22 — Add transformations

Go to **Datasets** → `syslog-test` → **Pipeline** tab.

Add transformations:
- **Rename:** `source_ip` → `src`
- **Add field:** `environment` = `"test-docker"`
- **Filter:** keep only events where `action` = `"login"`

Save. Wait for piper to refresh config (up to 5 minutes).

**Verify:** Query new events — renamed fields and added fields present. Filtered events excluded.

### Step 23 — Enable GeoIP (optional)

If GeoIP databases are available in the `geoip` MinIO bucket:

1. Upload `GeoLite2-City.mmdb` and `GeoLite2-Country.mmdb` to `geoip` bucket
2. Enable GeoIP on `source_ip` in dataset pipeline config
3. Wait for piper to refresh

**Verify:** New events include `source_ip_geo_country`, `source_ip_geo_city`.

### Step 24 — Test dataset pause (kill switch)

On bytefreezer.com, go to **Datasets** → `syslog-test`.
Click the pause button.

**Verify:**
- Dataset shows "Paused" badge
- Proxy stops forwarding data for this dataset (check proxy logs)
- Statistics stop increasing

Resume the dataset.

**Verify:** Data flow resumes.

### Step 25 — Verify end-to-end with parquet

After transformations are applied and packer has run:

1. Check `packer` bucket in MinIO for new `.parquet` files
2. Query the data on bytefreezer.com
3. Confirm transformed fields are in the parquet output

**Verify:** Parquet files contain transformed data.

---

## Phase 6: Cleanup

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
