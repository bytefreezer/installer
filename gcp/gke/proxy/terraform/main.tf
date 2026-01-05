# ByteFreezer Proxy - GCP GKE

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Get existing cluster
data "google_container_cluster" "existing" {
  name     = var.cluster_name
  location = var.cluster_location
}

data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.existing.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.existing.master_auth[0].cluster_ca_certificate)
  }
}

# Deploy ByteFreezer Proxy using Helm
resource "helm_release" "proxy" {
  name             = var.release_name
  chart            = var.helm_chart_path
  namespace        = var.namespace
  create_namespace = true

  set {
    name  = "receiver.url"
    value = var.receiver_url
  }

  set {
    name  = "controlService.url"
    value = var.control_service_url
  }

  set_sensitive {
    name  = "controlService.apiKey"
    value = var.control_service_api_key
  }

  set {
    name  = "replicaCount"
    value = var.replica_count
  }

  set {
    name  = "service.type"
    value = var.service_type
  }

  dynamic "set" {
    for_each = var.udp_ports
    content {
      name  = "udpPorts[${set.key}]"
      value = set.value
    }
  }
}
