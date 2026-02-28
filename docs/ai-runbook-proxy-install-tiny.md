# AI Runbook: Install Proxy on Tiny (Managed Mode)

Machine-readable runbook for AI agents deploying a ByteFreezer proxy on the host "tiny" using bytefreezer.com managed platform.

## Prerequisites

| Item | Value |
|------|-------|
| Target host | `tiny` (SSH alias, key-based auth) |
| Control API | `https://api.bytefreezer.com` |
| Receiver URL | `https://receiver.bytefreezer.com` |
| Docker Compose | Required on tiny |
| User in docker group | Required (check with `groups`) |
| UDP buffer | `net.core.rmem_max >= 16777216` |

## Critical Install Order

**Proxy FIRST, then dataset.** Do not create the dataset before the proxy is registered.

1. Create account + API key
2. Deploy proxy on tiny → wait for it to register as Healthy
3. Create tenant + dataset (with full source AND destination config)
4. Assign dataset to proxy
5. Verify data flow

## Known Pitfalls (from previous installs)

### 1. Host network mode required
- Proxy must use `network_mode: host` — binds directly to host ports.
- Allows control plane to dynamically assign plugin ports without container restart.
- Port mapping (`ports: "8008:8008"`) does NOT work with dynamic config.

### 2. Proxy image has no curl
- The proxy Docker image is minimal Alpine — **no curl installed**.
- Healthcheck must use `wget`: `["CMD-SHELL", "wget -qO- http://localhost:8008/api/v1/health || exit 1"]`

### 3. Fakedata needs host network mode
- Fakedata sends UDP to `127.0.0.1:5514`.
- With proxy in host network mode, fakedata must also use `network_mode: host`.

### 4. Deploy proxy BEFORE creating dataset
- Start proxy, wait for registration (Healthy in `bf_account_services`).
- Then create tenant + dataset + assign.
- Avoids stale instance ID problems from container restarts.

### 5. Create dataset with FULL config from the start
- **The update API replaces entire sub-objects.** If you send `config.source` without `config.destination`, destination is wiped.
- **Always include both `config.source` AND `config.destination`** at creation time.

### 6. Testing mode required for fast parquet output
- Without testing mode, packer waits for 128MB or 20 minutes before producing parquet.
- Set `"testing": true` on dataset creation to bypass accumulation thresholds.

### 7. Receiver URL must be HTTPS for managed
- Proxy config `receiver.base_url` must be `https://receiver.bytefreezer.com`.

### 8. Config mount path
- Proxy expects config at `/etc/bytefreezer-proxy/config.yaml` inside the container.
- Volume mount: `./config/proxy.yaml:/etc/bytefreezer-proxy/config.yaml:ro`

### 9. Cache volume
- Mount a named volume at `/var/cache/bytefreezer-proxy` to avoid permission errors.

### 10. `assigned_proxy_id` not `proxy_instance_id`
- The `bf_update_dataset_proxy_assignment` body field is `{"assigned_proxy_id": "..."}`.

### 11. Dataset destination needs REAL managed MinIO credentials
- The packer writes parquet to whatever S3 destination is configured on the dataset.
- For managed mode, the destination must use the real bytefreezer.com MinIO credentials — not placeholders.
- Without valid creds, output test shows "degraded" and no parquet files are produced.
- Get the credentials from the packer config on bytefreezer.com: `ssh bytefreezer.com "grep -A5 s3source /etc/bytefreezer-packer/config.yaml"`

### 12. Docker group requirement
- Deploy user must be in the `docker` group.
- Fix: `sudo usermod -aG docker $USER` then re-login.

### 12. Config poll interval is 30s
- After assigning a dataset to the proxy, wait up to 30s for it to pick up config.

## Pre-Flight Checks (run on tiny before install)

```bash
# 1. Docker available and user has permission
ssh tiny "docker compose version"

# 2. UDP buffer size (>= 16777216 for high-rate UDP)
ssh tiny "cat /proc/sys/net/core/rmem_max"
# If < 16777216:
ssh tiny "sudo sysctl -w net.core.rmem_max=16777216"

# 3. Target ports not in use
ssh tiny "ss -ulnp | grep ':5514 '"   # should be empty
ssh tiny "ss -tlnp | grep ':8008 '"   # should be empty

# 4. HTTPS connectivity to managed platform
ssh tiny "curl -sf https://api.bytefreezer.com/api/v1/health | head -c 100"
ssh tiny "curl -sf https://receiver.bytefreezer.com/health | head -c 100"

# 5. Docker group check
ssh tiny "groups"
# Must include 'docker'. If not: sudo usermod -aG docker $USER && newgrp docker
```

## Step-by-Step Procedure

### Phase 1: Account Setup (via MCP tools) — ~1 min

```
1. bf_list_accounts
   → Check if account already exists. Use existing account or create new one.

2. bf_create_account (if needed)
   → name: "test-managed"

3. bf_generate_api_key
   → account_id: <account_id>
   → SAVE THE KEY — it is shown only once
```

### Phase 2: Deploy Proxy on Tiny (via SSH) — ~3 min

```bash
# 1. Run pre-flight checks (see above)

# 2. Clean up any previous install
ssh tiny "cd ~/bytefreezer-proxy && docker compose down -v 2>/dev/null; rm -rf ~/bytefreezer-proxy"

# 3. Create directory structure
ssh tiny "mkdir -p ~/bytefreezer-proxy/config"

# 4. Write proxy config (substitute real values)
cat <<'PROXYEOF' | ssh tiny "cat > ~/bytefreezer-proxy/config/proxy.yaml"
app:
  name: "bytefreezer-proxy"
  version: "1.0.0"

account_id: "ACCOUNT_ID_HERE"
bearer_token: "API_KEY_HERE"
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
PROXYEOF

# 5. Write docker-compose.yml
cat <<'COMPOSEEOF' | ssh tiny "cat > ~/bytefreezer-proxy/docker-compose.yml"
services:
  proxy:
    image: ghcr.io/bytefreezer/bytefreezer-proxy:latest
    container_name: bytefreezer-proxy
    network_mode: host
    volumes:
      - ./config/proxy.yaml:/etc/bytefreezer-proxy/config.yaml:ro
      - proxy-spool:/var/spool/bytefreezer-proxy
      - proxy-cache:/var/cache/bytefreezer-proxy
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
  proxy-cache:
COMPOSEEOF

# 6. Pull images
ssh tiny "cd ~/bytefreezer-proxy && docker compose pull"

# 7. Start
ssh tiny "cd ~/bytefreezer-proxy && docker compose up -d"

# 8. Verify containers running
ssh tiny "cd ~/bytefreezer-proxy && docker compose ps"

# 9. Check proxy logs for registration
ssh tiny "cd ~/bytefreezer-proxy && docker compose logs proxy --tail 20"
# Look for: "Registered with control service" or "Health report sent successfully"
```

### Phase 3: Create Dataset and Assign (via MCP tools) — ~1 min

```
1. bf_account_services
   → account_id: <account_id>
   → Wait until proxy appears with status "Healthy"
   → SAVE instance_id (will be "tiny:8008" with host network)

2. bf_create_tenant
   → account_id: <account_id>, body: {"name": "demo"}
   → SAVE tenant_id

3. bf_create_dataset
   → tenant_id: <tenant_id>
   → body: {
       "name": "syslog-test",
       "testing": true,
       "config": {
         "source": {
           "type": "syslog",
           "custom": {"port": 5514, "host": "0.0.0.0"}
         },
         "destination": {
           "type": "s3",
           "connection": {
             "endpoint": "localhost:9000",
             "bucket": "packer",
             "region": "us-east-1",
             "ssl": false,
             "credentials": {
               "type": "static",
               "access_key": "<REAL_MANAGED_MINIO_KEY>",
               "secret_key": "<REAL_MANAGED_MINIO_SECRET>"
             }
           }
         }
       }
     }
   → SAVE dataset_id

4. bf_update_dataset_proxy_assignment
   → tenant_id: <tenant_id>, dataset_id: <dataset_id>
   → body: {"assigned_proxy_id": "tiny:8008"}

5. Wait 30s for proxy config poll
```

### Phase 4: Verify (MCP tools + SSH) — ~1 min

```
1. SSH: docker compose logs proxy | grep -i 'syslog\|plugin\|listening'
   → Should show syslog plugin started on port 5514

2. bf_dataset_statistics
   → tenant_id: <tenant_id>, dataset_id: <dataset_id>
   → events_in should be increasing

3. bf_list_account_errors
   → account_id: <account_id>
   → Should be empty or no critical errors

4. Wait 5-10 minutes for packer cycle, then:
   bf_dataset_parquet_files
   → tenant_id: <tenant_id>, dataset_id: <dataset_id>
   → Should list .parquet files
```

## Verification Checklist

| Check | Tool/Command | Expected |
|-------|-------------|----------|
| Containers running | `ssh tiny "docker compose -f ~/bytefreezer-proxy/docker-compose.yml ps"` | proxy + fakedata Up |
| Proxy registered | `bf_account_services` | Proxy instance with status Healthy |
| Proxy has dataset config | `ssh tiny "docker compose -f ~/bytefreezer-proxy/docker-compose.yml logs proxy \| grep plugin"` | syslog plugin started |
| Data flowing | `bf_dataset_statistics` | events_in > 0, increasing |
| Parquet output | `bf_dataset_parquet_files` | .parquet files listed (after ~5 min) |
| No errors | `bf_list_account_errors` | Empty or no critical errors |

## Cleanup

```bash
ssh tiny "cd ~/bytefreezer-proxy && docker compose down -v && rm -rf ~/bytefreezer-proxy"
```

Then optionally delete dataset, tenant, account via MCP tools.

## Timing (measured: ~6 min to data flow, ~10 min to parquet)

| Phase | Steps | Time |
|-------|-------|------|
| Account setup | Create account, key | 1 min |
| Pre-flight + deploy proxy | Checks, write files, pull, start | 3 min |
| Registration + tenant + dataset + assign | Wait for Healthy, create, assign | 1 min |
| Data flow verification | Check stats increasing | 1 min |
| Parquet verification | Wait for packer cycle | 5 min |
| **Total** | | **~10 min** |

The bottleneck is the packer cycle. With testing mode ON, packer runs every housekeeping interval (~5 min). Everything else completes in under 6 minutes.
