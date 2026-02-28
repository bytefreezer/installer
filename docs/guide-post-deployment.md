# What Happens After Deployment

Your proxy is running, data is flowing, and parquet files are landing. Now what?

This page explains what you're looking at, what you can do with it, and how the demo environment differs from a production deployment.

---

## Understanding the Data Pipeline

After a successful deployment, data flows through these stages:

```
Proxy → Receiver → Piper → Packer → Parquet (S3/MinIO)
```

Each stage writes to a separate S3 bucket:

| Bucket | Contents | Stage |
|--------|----------|-------|
| `intake` | `.ndjson.gz` compressed batches | Receiver stores raw data from proxy |
| `piper` | `.ndjson` processed files | Piper applies transformations and writes output |
| `packer` | `.parquet` columnar files | Packer converts NDJSON to Parquet |

Parquet files are the final output of the ByteFreezer pipeline. They are stored in a directory structure that enforces tenant and dataset isolation:

```
{tenant_id}/{dataset_id}/data/parquet/year=YYYY/month=MM/day=DD/hour=HH/{filename}.parquet
```

---

## What You Can See on the Dashboard

### Service Status Page

Shows all registered services (proxy, receiver, piper, packer) with:
- **Health status** — Healthy, Degraded, Starting, Unhealthy
- **Version** — which build each service is running
- **Metrics** — CPU, memory, disk, uptime
- **Last seen** — when the service last reported in

Your proxy appears here after it registers with the control plane.

### Statistics Page

Shows pipeline throughput for your dataset:
- **Events received** — how many records the proxy has forwarded
- **Piper processing** — records transformed and written
- **Packer output** — parquet files produced, total rows, total size

If piper or packer is not installed for your account (managed mode), those cards show "Not Installed" — this is expected. The managed platform runs them for you.

### Activity Page

Shows recent processing events:
- Piper job runs (how many records processed per batch)
- Packer jobs (parquet files created, accumulation status)
- Errors and retries

### Datasets Page

Shows your dataset configuration, assigned proxy, and status. From here you can:
- **Pause/Resume** a dataset (paused datasets are removed from proxy config)
- **View parquet files** produced for the dataset
- **Edit** source, destination, and transformation config
- **Test** input and output connectivity

### Query Page

Run SQL queries against your parquet data. Select a dataset and query the fields. Fakedata syslog events include fields like `source_ip`, `dest_ip`, `action`, `username`, `protocol`, `bytes_sent`, etc.

### Audit Log

Every action taken through the API or dashboard is recorded in the audit log. This includes:
- Account, tenant, and dataset creation/deletion
- API key generation and revocation
- Dataset configuration changes (source, destination, transformations)
- Dataset proxy assignments
- Service registrations (proxy, receiver, piper, packer connecting to control)

Navigate to **Audit Log** to see the full history. Each entry shows who performed the action (user email or API key), what was changed, and when. This is useful for tracking configuration changes and troubleshooting — if something stopped working, check the audit log to see what changed.

In a production deployment, the audit log provides accountability and compliance evidence for all control plane operations.

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

After saving a transformation, wait for the next piper cycle (up to 5 minutes). Then query the data — new records will reflect the changes.

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

What you have now is a **test pipeline** designed to verify end-to-end data flow. Specifically:

- **Fakedata** generates synthetic syslog events. This is not real data.
- **Testing mode** on the dataset bypasses packer accumulation thresholds so you see parquet files quickly (within minutes instead of the normal 20-minute or 128MB threshold).
- **Managed mode** means receiver, piper, and packer run on bytefreezer.com's shared infrastructure. Your data transits through and is stored on our servers.
- **Parquet files land in bytefreezer.com's MinIO** — you can query them from the dashboard, but this is shared infrastructure.

> **Do not send sensitive or production data through the managed demo.** It is not secured for production use.

### A Production Deployment

In production, the architecture changes:

1. **Your data stays on your infrastructure.** On-prem deployments run receiver, piper, packer, and MinIO on your own servers. Data never leaves your network.

2. **Parquet files land in your S3 or MinIO.** You control the storage, retention, and access.

3. **You connect parquet to your SIEM or analytics stack.** ByteFreezer produces the parquet files — what happens next is up to you (or your operator). Common destinations:
   - **Elastic/OpenSearch** — ingest parquet via Logstash or custom connector
   - **Splunk** — use HEC or file monitoring
   - **Sentinel/Microsoft** — push via Logic Apps or custom integration
   - **Snowflake/Databricks/BigQuery** — load parquet directly (native format)
   - **Custom dashboards** — query parquet with DuckDB, Pandas, Spark, etc.

4. **The query component is a reference implementation.** The query page on bytefreezer.com shows that parquet data is queryable. In production, you (or your operator) would build or configure the final mile — the connector that pushes processed parquet data into your SIEM, data lake, or analytics platform. The [example query project](https://github.com/bytefreezer/query-example) and [ByteFreezer MCP](https://github.com/bytefreezer/mcp) are starting points for building this integration.

5. **Testing mode is disabled.** Packer accumulates data to produce larger, more efficient parquet files (128MB or 20-minute batches).

### Data Sovereignty Summary

| Aspect | Managed Demo | On-Prem Production |
|--------|-------------|-------------------|
| Proxy | Your host | Your host |
| Receiver | bytefreezer.com | Your infrastructure |
| Piper | bytefreezer.com | Your infrastructure |
| Packer | bytefreezer.com | Your infrastructure |
| Storage (MinIO/S3) | bytefreezer.com | Your infrastructure |
| Control plane | bytefreezer.com | bytefreezer.com (config only, no data) |
| Data transit | Over internet (HTTPS) | Local network |
| Parquet output | Shared MinIO | Your S3/MinIO |

The control plane (bytefreezer.com) only handles configuration, health monitoring, and service registration. It never sees your actual data in on-prem mode.

---

## Next Steps

- **Want to deploy on-prem?** See [On-Prem with Docker Compose](guide-onprem-docker-compose.md) or [On-Prem with Kubernetes](guide-onprem-kubernetes.md)
- **Want to build the final mile?** Check the [example query project](https://github.com/bytefreezer/query-example) for connecting parquet to your SIEM
- **Want to automate deployments?** See [Deploy with Claude](guide-deploy-with-claude.md) for AI-assisted setup using MCP
- **Questions?** Contact us at https://bytefreezer.com/contact
