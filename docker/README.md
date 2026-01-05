# ByteFreezer Docker Compose Deployments

Docker Compose configurations for deploying ByteFreezer components.

## Components

| Directory | Description |
|-----------|-------------|
| [bytefreezer](./bytefreezer/) | Processing stack (receiver, piper, packer) - deploy centrally |
| [proxy](./proxy/) | Edge data collection - deploy at data source locations |

## Architecture

```
   Edge Sites                              Central Processing
                                       ┌─────────────────────────┐
┌─────────────────┐                    │                         │
│  Site A         │                    │  ┌──────────┐           │
│  ┌───────────┐  │   ┌────────────────┼─►│ Receiver │           │
│  │   Proxy   │──┼───┤                │  └────┬─────┘           │
│  └───────────┘  │   │                │       │                 │
└─────────────────┘   │                │       ▼                 │
                      │                │  ┌─────────┐            │
┌─────────────────┐   │                │  │   S3    │            │
│  Site B         │   │                │  └────┬────┘            │
│  ┌───────────┐  │   │                │       │                 │
│  │   Proxy   │──┼───┤                │       ▼                 │
│  └───────────┘  │   │                │  ┌─────────┐            │
└─────────────────┘   │                │  │  Piper  │            │
                      │                │  └────┬────┘            │
┌─────────────────┐   │                │       │                 │
│  Site C         │   │                │       ▼                 │
│  ┌───────────┐  │   │                │  ┌─────────┐            │
│  │   Proxy   │──┼───┘                │  │ Packer  │            │
│  └───────────┘  │                    │  └─────────┘            │
└─────────────────┘                    │                         │
   proxy/docker-compose.yml            └─────────────────────────┘
                                        bytefreezer/docker-compose.yml
```

## Quick Start

### 1. Deploy Processing Stack (Central)

```bash
cd bytefreezer

# Copy and configure environment
cp .env.example .env
# Edit .env with your control service credentials

# Edit config files
# - config/receiver.yaml: Set control_service.control_url
# - config/piper.yaml: Set control_service.control_url
# - config/packer.yaml: Set control_service.control_url

# Start with bundled MinIO
docker compose --profile with-minio up -d

# Or start without MinIO (using external S3)
docker compose up -d
```

Get the receiver URL for proxy configuration:
```bash
# If running locally
echo "http://$(hostname -I | awk '{print $1}'):8080"
```

### 2. Deploy Proxies (Edge Sites)

```bash
cd proxy

# Copy and configure environment
cp .env.example .env
# Edit .env with your control service API key

# Edit config/proxy.yaml:
# - Set receiver.url to your receiver URL
# - Set control_service.control_url

# Start proxy
docker compose up -d
```

## Configuration

### Processing Stack (bytefreezer/)

#### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `IMAGE_REGISTRY` | Container image registry | `ghcr.io/bytefreezer` |
| `IMAGE_TAG` | Image tag | `latest` |
| `CONTROL_URL` | Control service URL | - |
| `CONTROL_API_KEY` | API key for control service | - |
| `S3_ACCESS_KEY` | S3/MinIO access key | `minioadmin` |
| `S3_SECRET_KEY` | S3/MinIO secret key | `minioadmin` |
| `MINIO_ROOT_USER` | MinIO root user (if using bundled) | `minioadmin` |
| `MINIO_ROOT_PASSWORD` | MinIO root password | `minioadmin` |

#### Config Files

- `config/receiver.yaml` - Receiver configuration
- `config/piper.yaml` - Piper configuration
- `config/packer.yaml` - Packer configuration

Key settings to configure:
- `control_service.control_url` - Your control service URL
- `s3.endpoint` - S3 endpoint (default: `minio:9000` for bundled MinIO)

### Proxy (proxy/)

#### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `IMAGE_REGISTRY` | Container image registry | `ghcr.io/bytefreezer` |
| `IMAGE_TAG` | Image tag | `latest` |
| `CONTROL_API_KEY` | API key for control service | - |

#### Config Files

- `config/proxy.yaml` - Proxy configuration

Key settings to configure:
- `receiver.url` - URL of your ByteFreezer receiver
- `control_service.control_url` - Your control service URL

## Using External S3

To use external S3 instead of bundled MinIO:

1. Don't use the `with-minio` profile:
   ```bash
   docker compose up -d  # Without --profile with-minio
   ```

2. Update `.env`:
   ```env
   S3_ACCESS_KEY=your-aws-access-key
   S3_SECRET_KEY=your-aws-secret-key
   ```

3. Update config files to use external endpoint:
   ```yaml
   s3:
     endpoint: "s3.amazonaws.com"
     ssl: true
   ```

## Ports

### Processing Stack

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| Receiver | 8080 | HTTP | Webhook (data intake from proxies) |
| Receiver | 8081 | HTTP | API (health) |
| Receiver | 9091 | HTTP | Metrics (Prometheus) |
| Piper | 8082 | HTTP | API |
| Piper | 9092 | HTTP | Metrics (Prometheus) |
| Packer | 8083 | HTTP | API |
| Packer | 9093 | HTTP | Metrics (Prometheus) |
| MinIO | 9000 | HTTP | S3 API |
| MinIO | 9001 | HTTP | Console |
| Prometheus | 9090 | HTTP | UI and API (optional) |

### Proxy

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| Proxy | 8008 | HTTP | API (health, metrics) |
| Proxy | 5514 | UDP | Syslog (configurable) |

## Monitoring

### With Bundled Prometheus

Start the processing stack with Prometheus for metrics collection:

```bash
cd bytefreezer

# Start with Prometheus only
docker compose --profile with-prometheus up -d

# Start with both MinIO and Prometheus
docker compose --profile with-minio --profile with-prometheus up -d
```

Access Prometheus UI at http://localhost:9090

### Metrics Ports

When Prometheus is enabled, it scrapes metrics from:

| Service | Metrics Port | Path |
|---------|--------------|------|
| Receiver | 9091 | `/metrics` |
| Piper | 9092 | `/metrics` |
| Packer | 9093 | `/metrics` |
| Prometheus | 9090 | (self-monitoring) |

### Prometheus Configuration

The default configuration is in `config/prometheus.yml`. Modify to:
- Change scrape interval
- Add additional targets
- Configure alerting rules

### Using External Prometheus

If you have an existing Prometheus instance, configure it to scrape ByteFreezer:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'bytefreezer-receiver'
    static_configs:
      - targets: ['<host>:9091']
    metrics_path: /metrics

  - job_name: 'bytefreezer-piper'
    static_configs:
      - targets: ['<host>:9092']
    metrics_path: /metrics

  - job_name: 'bytefreezer-packer'
    static_configs:
      - targets: ['<host>:9093']
    metrics_path: /metrics
```

### Grafana Integration

Both bundled and external Prometheus work with Grafana:

1. Add Prometheus as a data source:
   - URL: `http://bytefreezer-prometheus:9090` (if using Docker network)
   - Or: `http://localhost:9090` (if accessing from host)

2. Import or create dashboards using available metrics.

### Prometheus Retention

Configure data retention via environment variable:

```bash
PROMETHEUS_RETENTION=30d docker compose --profile with-prometheus up -d
```

## Scaling

### Processing Stack

```bash
docker compose up -d --scale piper=2 --scale packer=2
```

### Proxy

For multiple proxies, deploy to separate hosts or use different port mappings.

## Troubleshooting

### Check Status

```bash
docker compose ps
docker compose logs -f
```

### Health Checks

```bash
# Receiver
curl http://localhost:8081/api/v1/health

# Piper
curl http://localhost:8082/api/v1/health

# Packer
curl http://localhost:8083/api/v1/health

# Proxy
curl http://localhost:8008/api/v1/health
```

### Test Proxy UDP

```bash
# Send test syslog message
echo "<14>Test message" | nc -u localhost 5514
```

## Stop Services

```bash
# Processing stack
cd bytefreezer
docker compose down

# With volumes (removes data)
docker compose down -v

# Proxy
cd proxy
docker compose down
```

## Requirements

- Docker 20.10+
- Docker Compose v2.0+
- ByteFreezer control service access (URL + API key)
