# AI Runbook: Install Proxy on Tiny (Managed Mode)

Machine-readable runbook for AI agents deploying a ByteFreezer proxy on the host "tiny" using bytefreezer.com managed platform.

## Prerequisites

| Item | Value |
|------|-------|
| Target host | `tiny` (SSH alias, key-based auth) |
| Control API | `https://api.bytefreezer.com` |
| Receiver URL | `https://receiver.bytefreezer.com` |
| Docker Compose | Required on tiny |
| UDP buffer | `net.core.rmem_max >= 16777216` |

## Known Pitfalls (from previous installs)

### 1. MCP tool path bugs (FIXED 2026-02-27)
- `bf_list_api_keys`, `bf_generate_api_key`, `bf_revoke_api_key` were hitting `/api-keys` instead of `/keys`
- `bf_list_service_keys`, `bf_generate_service_key` were hitting `/service-keys` instead of `/keys`
- **Status:** Fixed. All key tools now use `/api/v1/accounts/{id}/keys`.

### 2. Dataset config replacement semantics
- **The update API replaces entire sub-objects.** If you send `config.source` without `config.destination`, destination is wiped.
- **Always send both `config.source` AND `config.destination` together** when updating either one.
- Best practice: create the dataset with full config from the start.

### 3. Proxy image has no curl
- The proxy Docker image is minimal Alpine — **no curl installed**.
- Healthcheck must use `wget`: `["CMD-SHELL", "wget -qO- http://localhost:8008/api/v1/health || exit 1"]`
- Do NOT use `curl` in healthchecks — it will fail silently and container will be marked unhealthy.

### 4. Fakedata needs host network mode
- Fakedata sends UDP to `127.0.0.1:5514`.
- Proxy publishes port `5514:5514/udp` on the host.
- Fakedata must use `network_mode: host` to reach the host-published UDP port.
- If fakedata is on the same Docker bridge network as proxy, it should use the container name and internal port instead.

### 5. Dataset must be assigned to proxy AFTER proxy registers
- Create the dataset first WITHOUT assigning a proxy.
- Start the proxy container. Wait for it to register with control (check `bf_account_services`).
- Then assign the dataset to the proxy using `bf_update_dataset_proxy_assignment`.
- The proxy picks up the dataset config on the next config poll (30s interval).

### 6. Testing mode is required for fast parquet output
- Without testing mode, packer waits for 128MB or 20 minutes before producing parquet.
- Set `"testing": true` on dataset creation to bypass accumulation thresholds.
- Packer processes on each housekeeping cycle (~5 min in testing mode).

### 7. Receiver URL must be HTTPS for managed
- Proxy config `receiver.base_url` must be `https://receiver.bytefreezer.com`.
- Using `http://` will fail with connection refused or TLS errors.

### 8. Account type must match deployment
- For managed (proxy-only) installs, account type should be `managed` or `enterprise`.
- For on-prem (full stack) installs, account type should be `on_prem`.

### 9. Config mount path
- Proxy expects config at `/etc/bytefreezer-proxy/config.yaml` inside the container.
- Volume mount: `./config/proxy.yaml:/etc/bytefreezer-proxy/config.yaml:ro`

### 10. OAuth re-auth error (FIXED 2026-02-27)
- Claude Code MCP client probes `/.well-known/oauth-authorization-server` during re-auth.
- MCP server now returns proper JSON 404 instead of plain-text "404 page not found".

## Step-by-Step Procedure

### Phase 1: Account Setup (via MCP tools)

```
1. bf_list_accounts
   → Check if account already exists. Use existing account or create new one.

2. bf_create_account (if needed)
   → name: "test-managed", type: "on_prem" or leave default

3. bf_generate_api_key
   → account_id: <account_id>
   → SAVE THE KEY — it is shown only once

4. bf_create_tenant
   → account_id: <account_id>, body: {"name": "demo"}
   → SAVE tenant_id

5. bf_create_dataset
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
               "access_key": "MINIO_ACCESS_KEY",
               "secret_key": "MINIO_SECRET_KEY"
             }
           }
         }
       }
     }
   → SAVE dataset_id
   → NOTE: For managed, destination points to bytefreezer.com MinIO.
     The managed packer/piper already have MinIO credentials configured.
     The destination in the dataset is for packer output — it uses its own
     configured S3, not the dataset's destination field. So destination
     config here is informational / for on-prem use.
```

### Phase 2: Deploy Proxy on Tiny (via SSH)

```bash
# 1. Check host is ready
ssh tiny "docker compose version && cat /proc/sys/net/core/rmem_max"
# Expected: Docker Compose v2+, rmem_max >= 16777216

# 2. If rmem_max < 16777216:
ssh tiny "sudo sysctl -w net.core.rmem_max=16777216"

# 3. Clean up any previous install
ssh tiny "cd ~/bytefreezer-proxy && docker compose down -v 2>/dev/null; rm -rf ~/bytefreezer-proxy"

# 4. Create directory structure
ssh tiny "mkdir -p ~/bytefreezer-proxy/config"

# 5. Write proxy config (substitute real values)
ssh tiny "cat > ~/bytefreezer-proxy/config/proxy.yaml << 'PROXYEOF'
app:
  name: \"bytefreezer-proxy\"
  version: \"1.0.0\"

account_id: \"ACCOUNT_ID_HERE\"
bearer_token: \"API_KEY_HERE\"
control_url: \"https://api.bytefreezer.com\"
config_mode: \"control-only\"

server:
  api_port: 8008

receiver:
  base_url: \"https://receiver.bytefreezer.com\"

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
  directory: \"/var/spool/bytefreezer-proxy\"
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
PROXYEOF"

# 6. Write docker-compose.yml
ssh tiny "cat > ~/bytefreezer-proxy/docker-compose.yml << 'COMPOSEEOF'
services:
  proxy:
    image: ghcr.io/bytefreezer/bytefreezer-proxy:latest
    container_name: bytefreezer-proxy
    ports:
      - \"8008:8008\"
      - \"5514:5514/udp\"
    volumes:
      - ./config/proxy.yaml:/etc/bytefreezer-proxy/config.yaml:ro
      - proxy-spool:/var/spool/bytefreezer-proxy
    healthcheck:
      test: [\"CMD-SHELL\", \"wget -qO- http://localhost:8008/api/v1/health || exit 1\"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  fakedata:
    image: ghcr.io/bytefreezer/bytefreezer-fakedata:latest
    container_name: bytefreezer-fakedata
    network_mode: host
    command: [\"syslog\", \"--host\", \"127.0.0.1\", \"--port\", \"5514\", \"--rate\", \"10\"]
    restart: unless-stopped
    depends_on:
      proxy:
        condition: service_started

volumes:
  proxy-spool:
COMPOSEEOF"

# 7. Pull images (avoids timeout on first compose up)
ssh tiny "cd ~/bytefreezer-proxy && docker compose pull"

# 8. Start
ssh tiny "cd ~/bytefreezer-proxy && docker compose up -d"

# 9. Verify containers running
ssh tiny "cd ~/bytefreezer-proxy && docker compose ps"

# 10. Check proxy logs for registration
ssh tiny "cd ~/bytefreezer-proxy && docker compose logs proxy --tail 30"
# Look for: "Registered with control service" or "Health report sent successfully"
```

### Phase 3: Assign Dataset and Verify (via MCP tools)

```
1. bf_account_services
   → account_id: <account_id>
   → Wait until proxy appears with status "Healthy"
   → SAVE instance_id of the proxy

2. bf_update_dataset_proxy_assignment
   → tenant_id: <tenant_id>, dataset_id: <dataset_id>
   → body: {"proxy_instance_id": "<instance_id>"}

3. Wait 30-60 seconds for proxy to pick up config

4. Verify via SSH:
   ssh tiny "cd ~/bytefreezer-proxy && docker compose logs proxy | grep -i 'syslog\|plugin\|listening'"
   → Should show syslog plugin started on port 5514

5. bf_dataset_statistics
   → tenant_id: <tenant_id>, dataset_id: <dataset_id>
   → events_in should be increasing

6. Wait 5-10 minutes for packer cycle, then:
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

## Timing Budget (target: under 10 minutes)

| Phase | Steps | Time |
|-------|-------|------|
| Account setup | Create account, key, tenant, dataset | 1 min |
| Deploy proxy | Write files, pull images, start | 3 min |
| Registration | Wait for proxy to register + assign dataset | 1 min |
| Data flow verification | Check stats increasing | 1 min |
| Parquet verification | Wait for packer cycle | 5 min |
| **Total** | | **~10 min** |

The bottleneck is the packer cycle. With testing mode ON, packer runs every housekeeping interval (~5 min). Everything else completes in under 5 minutes.
