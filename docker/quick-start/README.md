# ByteFreezer Quick Start

Full pipeline in Docker Compose: proxy, receiver, piper, packer, MinIO, and fakedata.
Services register with hosted control at `api.bytefreezer.com`.

## Data Flow

```
fakedata --[syslog UDP:5514]--> proxy --[HTTP POST]--> receiver --[S3: intake]--> piper --[S3: piper]--> packer --[parquet to S3]
                                                                       |
                                                                   MinIO (local)
```

## Prerequisites

- Docker and Docker Compose
- A bytefreezer.com account

## Setup

### 1. Get Credentials

Log in to [bytefreezer.com](https://bytefreezer.com) → Settings → copy your **Account ID** and **API Key**.

### 2. Configure

Edit `.env`:

```
CONTROL_API_KEY=your-api-key-here
ACCOUNT_ID=your-account-id-here
```

### 3. Start

```bash
docker compose up -d
```

### 4. Verify Services

```bash
docker compose ps
```

All services should show as healthy. Fakedata will restart until proxy has a configured dataset — this is expected.

### 5. Check MinIO

Open [http://localhost:9001](http://localhost:9001) — login with `minioadmin` / `minioadmin`.
Verify 4 buckets exist: `intake`, `piper`, `packer`, `geoip`.

### 6. Create a Dataset

On [bytefreezer.com](https://bytefreezer.com):

1. **Tenants** → Create tenant named `quickstart`
2. **Datasets** → Create dataset `test-syslog` under `quickstart`
3. Configure the dataset:
   - **Input**: Syslog, port `5514`
   - **Output S3**: endpoint `localhost:9000`, bucket `packer`, access key `minioadmin`, secret key `minioadmin`, SSL off
   - **Assign** to your proxy
   - **Activate** the dataset
4. Optionally enable **Test Mode** for faster results

### 7. Wait for Config Sync

Proxy polls control every 30 seconds. Wait 1–2 minutes for it to pick up the new dataset configuration.

### 8. Verify Data Flow

- **Statistics** page on bytefreezer.com shows events moving through the pipeline
- **MinIO console** → `packer` bucket → parquet files appear after processing

### 9. Cleanup

```bash
docker compose down -v
```

This removes all containers and volumes.

## Ports

| Service  | Port       | Purpose         |
|----------|------------|-----------------|
| MinIO    | 9000       | S3 API          |
| MinIO    | 9001       | Web console     |
| Receiver | 8080       | Webhook intake  |
| Receiver | 8081       | API / health    |
| Piper    | 8082       | API / health    |
| Packer   | 8083       | API / health    |
| Proxy    | 8008       | API / health    |
| Proxy    | 5514/udp   | Syslog intake   |

## Troubleshooting

**Services not registering with control:**
Check that `CONTROL_API_KEY` and `ACCOUNT_ID` are set correctly in `.env`.

```bash
docker compose logs receiver | grep -i control
```

**No data in MinIO buckets:**
Verify the dataset is active and assigned to your proxy on bytefreezer.com.
Check proxy logs:

```bash
docker compose logs proxy | grep -i plugin
```

**Fakedata keeps restarting:**
Expected until the dataset is configured and proxy starts accepting syslog on port 5514.
