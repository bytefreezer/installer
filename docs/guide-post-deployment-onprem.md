# What Happens After Deployment (On-Prem)

Your full stack is running on your infrastructure, data is flowing, and parquet files are landing in your local MinIO. Now what?

This page explains what you're looking at, how to use the Connector to query and export your data, and how the demo environment differs from production.

---

## Understanding the Data Pipeline

After a successful deployment, data flows through these stages:

```
Proxy → Receiver → Piper → Packer → Parquet (your MinIO)
                                         ↓
                                    Connector → Elasticsearch / Splunk / webhook / stdout
```

Each stage writes to a separate S3 bucket in your local MinIO:

| Bucket | Contents | Stage |
|--------|----------|-------|
| `intake` | `.ndjson.gz` compressed batches | Receiver stores raw data from proxy |
| `piper` | `.ndjson` processed files | Piper applies transformations and writes output |
| `packer` | `.parquet` columnar files | Packer converts NDJSON to Parquet |

Parquet files are the final output of the processing pipeline. They are stored in a directory structure that enforces tenant and dataset isolation:

```
{tenant_id}/{dataset_id}/data/parquet/year=YYYY/month=MM/day=DD/hour=HH/{filename}.parquet
```

---

## What You Can See on the Dashboard

The dashboard at bytefreezer.com shows control plane data — service registrations, configuration, health status. It does **not** have direct access to your on-prem MinIO or parquet files.

### Service Status Page

Shows all registered services (proxy, receiver, piper, packer, connector) with:
- **Health status** — Healthy, Degraded, Starting, Unhealthy
- **Version** — which build each service is running
- **Metrics** — CPU, memory, disk, uptime
- **Last seen** — when the service last reported in

### Statistics Page

Shows pipeline throughput for your dataset:
- **Events received** — how many records the proxy has forwarded
- **Piper processing** — records transformed and written
- **Packer output** — parquet files produced, total rows, total size

### Activity Page

Shows recent processing events:
- Piper job runs (how many records processed per batch)
- Packer jobs (parquet files created, accumulation status)
- Errors and retries

### Datasets Page

Shows your dataset configuration, assigned proxy, and status. From here you can:
- **Pause/Resume** a dataset (paused datasets are removed from proxy config)
- **Edit** source, destination, and transformation config
- **Test** input and output connectivity

### Audit Log

Every action taken through the API or dashboard is recorded. This includes account/tenant/dataset operations, API key management, configuration changes, and service registrations. Useful for tracking what changed and when.

---

## Connector

The Connector is your "final mile" — it reads parquet files from your local MinIO using DuckDB and exports data to external systems (Elasticsearch, Splunk, webhooks, etc.).

### Web UI (Interactive Mode)

Open `http://testhost:8090` in your browser (replace `testhost` with your host IP).

The interactive mode lets you:
- Browse datasets and see available parquet files
- Write and test SQL queries against your data
- Preview query results
- Configure and test destinations
- Run one-off exports

### Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **interactive** (default) | Web UI at port 8090 | Exploration, ad-hoc queries, testing destinations |
| **batch** | Run a configured query once, export results, exit | One-time data exports, backfills |
| **watch** | Run the query on a timer, continuously exporting new data | Ongoing SIEM feed, streaming to Elasticsearch |

The Docker deployment runs in interactive mode by default. For batch or watch mode, override the command in docker-compose.yml:

```yaml
connector:
  command: ["--config", "/app/config.yaml", "--mode", "watch"]
```

### SQL Queries

Use `PARQUET_PATH` as a placeholder — the connector replaces it with the actual S3 glob path for your dataset.

```sql
-- All records (limited)
SELECT * FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
LIMIT 100

-- Filter by time partition
SELECT * FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
WHERE year = 2026 AND month = 3 AND day = 5

-- Aggregate by hour
SELECT year, month, day, hour, COUNT(*) as count
FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
GROUP BY year, month, day, hour
ORDER BY year, month, day, hour

-- Filter specific fields
SELECT timestamp, source_ip, message
FROM read_parquet('PARQUET_PATH', hive_partitioning=true, union_by_name=true)
WHERE severity >= 4
LIMIT 1000
```

### Destinations

Built-in destinations:

| Destination | Type | Description |
|-------------|------|-------------|
| **stdout** | `stdout` | JSON lines to stdout (default, useful for testing) |
| **Elasticsearch** | `elasticsearch` | Bulk API to Elasticsearch/OpenSearch |
| **Webhook** | `webhook` | Generic HTTP POST to any endpoint |

Configure in `config/connector.yaml`:

```yaml
# Elasticsearch example
destination:
  type: elasticsearch
  config:
    url: "http://elasticsearch:9200"
    index: "bytefreezer-logs"
    username: "elastic"
    password: "changeme"

# Webhook example
destination:
  type: webhook
  config:
    url: "https://example.com/webhook"
    headers:
      Authorization: "Bearer your-token"
```

### Adding Custom Destinations

The connector has a plugin architecture. Create a new Go file in `destinations/` implementing the `Destination` interface. The `init()` function auto-registers it — no other changes needed. Ask Claude Code: "Add a Splunk HEC destination to the connector" and it will generate the code following the existing pattern.

### Configuration Reference

Key fields in `config/connector.yaml`:

| Key | Required | Description |
|-----|----------|-------------|
| `control.url` | Yes | Control API URL (default: `https://api.bytefreezer.com`) |
| `control.api_key` | Yes | Your API key or service key |
| `control.account_id` | Yes | Your account ID |
| `query.tenant_id` | Batch/Watch | Tenant ID for the dataset to query |
| `query.dataset_id` | Batch/Watch | Dataset ID to query |
| `query.sql` | Batch/Watch | SQL query with `PARQUET_PATH` placeholder |
| `destination.type` | Batch/Watch | `stdout`, `elasticsearch`, or `webhook` |
| `destination.config` | Batch/Watch | Destination-specific config (see examples above) |
| `schedule.interval_seconds` | Watch | How often to poll for new data (default: 60) |
| `schedule.batch_size` | Watch | Records per batch sent to destination (default: 1000) |

---

## What You Can Do Next

### Play with Transformations

Go to **Datasets** → your dataset → **Pipeline** tab.

Transformations modify data as it flows through piper. Changes apply to new data only — existing parquet files are not reprocessed.

You can build transformations manually using the JSON examples below, or use the **Agent** tab next to the Pipeline tab. The AI agent knows your dataset schema, available filters, and current pipeline config — describe what you want in plain English and it will generate the transformation JSON for you. For example: "drop all events where action is deny and rename source_ip to src".

Examples to try:

**Rename a field:**
```json
{
  "filters": [
    {
      "type": "rename_field",
      "config": { "from": "source_ip", "to": "src_ip" }
    }
  ]
}
```

**Add a static field:**
```json
{
  "filters": [
    {
      "type": "add_field",
      "config": { "field": "environment", "value": "demo" }
    }
  ]
}
```

**Drop a field:**
```json
{
  "filters": [
    {
      "type": "remove_field",
      "config": { "field": "raw_message" }
    }
  ]
}
```

**Filter events (drop matching records):**
```json
{
  "filters": [
    {
      "type": "drop",
      "config": { "condition": "action == 'deny'" }
    }
  ]
}
```

After saving a transformation, wait for the next piper cycle (up to 5 minutes). Then query the data in the Connector — new records will reflect the changes.

Use the **Test Transformation** button to preview changes against sample data before deploying.

### Enable GeoIP Enrichment

If a GeoIP database is available (MaxMind GeoLite2), piper can enrich IP address fields with geographic data.

Add a GeoIP filter to the transformation pipeline:
```json
{
  "type": "geoip",
  "config": { "field": "source_ip" }
}
```

New events will include `source_ip_geo_country`, `source_ip_geo_city`, `source_ip_geo_lat`, `source_ip_geo_lon`, etc.

### Try Different Data Sources

The proxy supports multiple input plugins. Create additional datasets with different source types:

| Plugin | Transport | Example Port | Use Case |
|--------|-----------|-------------|----------|
| `syslog` | UDP | 514, 5514 | System logs, network devices |
| `netflow` | UDP | 2055 | Network flow data (NetFlow v5/v9) |
| `sflow` | UDP | 6343 | sFlow v5/v6 network sampling |
| `ipfix` | UDP | 4739 | IPFIX (RFC 7011) flow data |
| `http` | TCP | 8080 | HTTP webhook / REST API ingestion |
| `kafka` | TCP | 9092 | Apache Kafka consumer |
| `sqs` | AWS API | — | AWS SQS queue consumer |
| `nats` | TCP | 4222 | NATS messaging subscriber |
| `ebpf` | UDP | 2056 | Kernel-level eBPF telemetry |

Each dataset gets its own port and plugin instance. The proxy manages them dynamically — no restart needed. Create the dataset, assign it to the proxy, and the plugin starts on the next config poll (30 seconds).

---

## Demo vs. Production: What's Different

### This Demo Environment

What you have now is a **test pipeline** designed to verify end-to-end data flow:

- **Fakedata** generates synthetic syslog events — not real data.
- **Testing mode** on the dataset bypasses packer accumulation thresholds so you see parquet files quickly (within minutes instead of the normal 20-minute or 128MB threshold).
- **All data stays on your host.** On-prem mode means receiver, piper, packer, and MinIO run locally. The control plane on bytefreezer.com only handles configuration and health monitoring — it never sees your data.

### A Production Deployment

In production:

1. **Real data sources.** Replace fakedata with real syslog, netflow, or other inputs from your network devices and servers.

2. **Testing mode disabled.** Packer accumulates data to produce larger, more efficient parquet files (128MB or 20-minute batches).

3. **Connector in watch mode.** Configure the connector with your production destination (Elasticsearch, Splunk, webhook) and run it in watch mode for continuous data export. Only export the fields and events you need — this is where ByteFreezer reduces SIEM costs.

4. **Custom destinations.** Build connector plugins for your specific SIEM or analytics platform. The plugin architecture makes this straightforward.

5. **Retention and lifecycle.** Configure MinIO lifecycle rules to automatically expire old parquet files based on your retention requirements.

### Data Sovereignty Summary

| Aspect | On-Prem (this deployment) |
|--------|--------------------------|
| Proxy | Your host |
| Receiver | Your host |
| Piper | Your host |
| Packer | Your host |
| Connector | Your host |
| Storage (MinIO) | Your host |
| Parquet output | Your MinIO |
| Control plane | bytefreezer.com (config only, no data) |
| Data transit | Local network only |

The control plane (bytefreezer.com) only handles configuration, health monitoring, and service registration. It never sees your actual data.

---

## Next Steps

- **Want to try managed mode?** See [Managed Deployment](guide-managed.md) (proxy only, fastest to set up)
- **Deploy on different infrastructure?** See [On-Prem Docker Compose](guide-onprem-docker.md) or [On-Prem Kubernetes](guide-onprem-k8s.md)
- **Build a custom connector destination?** See the connector [CLAUDE.md](https://github.com/bytefreezer/connector) for the plugin interface
- **Questions?** Contact us at https://bytefreezer.com/contact
