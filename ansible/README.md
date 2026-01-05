# ByteFreezer Ansible Playbooks

Deploy ByteFreezer to bare metal servers or VMs using Ansible.

## Structure

```
ansible/
├── bytefreezer/          # Processing stack (receiver, piper, packer)
│   ├── playbook.yml
│   ├── inventory.yml.example
│   ├── vars/
│   │   ├── main.yml
│   │   └── secrets.yml.example
│   └── roles/
│       ├── docker/
│       ├── minio/
│       ├── receiver/
│       ├── piper/
│       ├── packer/
│       └── prometheus/
└── proxy/                # Edge proxy
    ├── playbook.yml
    ├── inventory.yml.example
    ├── vars/
    └── roles/
        ├── docker/
        └── proxy/
```

## Prerequisites

- Ansible 2.9+
- SSH access to target servers
- Target servers: Ubuntu 20.04+ or RHEL/CentOS 8+
- Python 3 on target servers

## Quick Start

### 1. Deploy Processing Stack

```bash
cd bytefreezer

# Create inventory
cp inventory.yml.example inventory.yml
# Edit inventory.yml with your server details

# Create secrets
cp vars/secrets.yml.example vars/secrets.yml
# Edit vars/secrets.yml with your API key

# Encrypt secrets
ansible-vault encrypt vars/secrets.yml

# Run playbook
ansible-playbook -i inventory.yml playbook.yml --ask-vault-pass
```

### 2. Deploy Proxy (Edge)

```bash
cd proxy

# Create inventory
cp inventory.yml.example inventory.yml
# Edit with edge server details

# Create and encrypt secrets
cp vars/secrets.yml.example vars/secrets.yml
ansible-vault encrypt vars/secrets.yml

# Run playbook
ansible-playbook -i inventory.yml playbook.yml --ask-vault-pass
```

## Configuration

### Processing Stack Variables

Edit `bytefreezer/vars/main.yml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `minio_enabled` | Deploy MinIO for S3 storage | `false` |
| `monitoring_enabled` | Deploy Prometheus | `false` |
| `control_service_url` | Control service URL | `https://api.bytefreezer.com` |
| `s3_endpoint` | S3 endpoint | `minio:9000` |
| `image_tag` | Container image tag | `latest` |

### Proxy Variables

Edit `proxy/vars/main.yml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `receiver_url` | URL of receiver | - |
| `control_service_url` | Control service URL | `https://api.bytefreezer.com` |
| `udp_ports` | UDP ports to expose | `[5514]` |

## Examples

### With MinIO and Prometheus

```bash
# Edit vars/main.yml
minio_enabled: true
monitoring_enabled: true

# Run playbook
ansible-playbook -i inventory.yml playbook.yml --ask-vault-pass
```

### Multiple Servers

```yaml
# inventory.yml
all:
  children:
    bytefreezer:
      hosts:
        server1:
          ansible_host: 192.168.1.101
        server2:
          ansible_host: 192.168.1.102
        server3:
          ansible_host: 192.168.1.103
```

### External S3

```yaml
# vars/main.yml
minio_enabled: false
s3_endpoint: s3.amazonaws.com
s3_use_ssl: true

# vars/secrets.yml
vault_s3_access_key: "your-access-key"
vault_s3_secret_key: "your-secret-key"
```

## Service Management

After deployment, services are managed via systemd:

```bash
# Check status
systemctl status bytefreezer-receiver
systemctl status bytefreezer-piper
systemctl status bytefreezer-packer

# View logs
journalctl -u bytefreezer-receiver -f

# Restart service
systemctl restart bytefreezer-piper
```

## Ports

### Processing Stack

| Service | Port | Description |
|---------|------|-------------|
| Receiver | 8080 | Webhook (data intake) |
| Receiver | 8081 | API |
| Receiver | 9091 | Metrics |
| Piper | 8082 | API |
| Piper | 9092 | Metrics |
| Packer | 8083 | API |
| Packer | 9093 | Metrics |
| MinIO | 9000 | S3 API |
| MinIO | 9001 | Console |
| Prometheus | 9090 | UI |

### Proxy

| Service | Port | Description |
|---------|------|-------------|
| Proxy | 8008 | API |
| Proxy | 5514 | Syslog (UDP) |

## Updating

To update to a new version:

```bash
# Edit vars/main.yml
image_tag: "v1.2.3"

# Re-run playbook
ansible-playbook -i inventory.yml playbook.yml --ask-vault-pass
```
