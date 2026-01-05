# ByteFreezer Proxy - Google Cloud Run
# Note: Cloud Run doesn't support UDP, so proxy is limited to HTTP forwarding

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Service Account for Proxy
resource "google_service_account" "proxy" {
  account_id   = "${var.name_prefix}-proxy-sa"
  display_name = "ByteFreezer Proxy Service Account"
  project      = var.project_id
}

# Secret for control service API key
resource "google_secret_manager_secret" "api_key" {
  secret_id = "${var.name_prefix}-proxy-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_key" {
  secret      = google_secret_manager_secret.api_key.id
  secret_data = var.control_service_api_key
}

resource "google_secret_manager_secret_iam_member" "proxy" {
  secret_id = google_secret_manager_secret.api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.proxy.email}"
}

# Proxy Cloud Run Service
resource "google_cloud_run_v2_service" "proxy" {
  name     = "${var.name_prefix}-proxy"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.proxy.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = "${var.image_registry}/bytefreezer-proxy:${var.image_tag}"

      ports {
        container_port = 8008
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      env {
        name  = "PROXY_RECEIVER_URL"
        value = var.receiver_url
      }

      env {
        name  = "PROXY_CONTROL_URL"
        value = var.control_service_url
      }

      env {
        name = "PROXY_CONTROL_SERVICE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  labels = var.labels

  depends_on = [
    google_secret_manager_secret_iam_member.proxy
  ]
}

# Allow unauthenticated access
resource "google_cloud_run_v2_service_iam_member" "proxy_public" {
  count    = var.allow_unauthenticated ? 1 : 0
  location = google_cloud_run_v2_service.proxy.location
  name     = google_cloud_run_v2_service.proxy.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
