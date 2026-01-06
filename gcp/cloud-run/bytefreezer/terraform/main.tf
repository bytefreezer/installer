# ByteFreezer Processing Stack - Google Cloud Run
# Serverless container deployment

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

# GCS Bucket for storage
resource "google_storage_bucket" "bytefreezer" {
  name          = "${var.project_id}-${var.name_prefix}-data"
  location      = var.region
  force_destroy = var.force_destroy_bucket

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  labels = var.labels
}

# Create folders (prefixes) in the bucket
resource "google_storage_bucket_object" "intake" {
  name    = "intake/"
  content = " "
  bucket  = google_storage_bucket.bytefreezer.name
}

resource "google_storage_bucket_object" "piper" {
  name    = "piper/"
  content = " "
  bucket  = google_storage_bucket.bytefreezer.name
}

resource "google_storage_bucket_object" "geoip" {
  name    = "geoip/"
  content = " "
  bucket  = google_storage_bucket.bytefreezer.name
}

# Service Account for ByteFreezer
resource "google_service_account" "bytefreezer" {
  account_id   = "${var.name_prefix}-sa"
  display_name = "ByteFreezer Service Account"
  project      = var.project_id
}

# IAM binding for storage access
resource "google_storage_bucket_iam_member" "bytefreezer" {
  bucket = google_storage_bucket.bytefreezer.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.bytefreezer.email}"
}

# Secret for control service API key
resource "google_secret_manager_secret" "api_key" {
  secret_id = "${var.name_prefix}-control-api-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_key" {
  secret      = google_secret_manager_secret.api_key.id
  secret_data = var.control_service_api_key
}

resource "google_secret_manager_secret_iam_member" "bytefreezer" {
  secret_id = google_secret_manager_secret.api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.bytefreezer.email}"
}

# VPC Connector for internal communication
resource "google_vpc_access_connector" "bytefreezer" {
  name          = "${var.name_prefix}-connector"
  region        = var.region
  network       = var.network
  ip_cidr_range = var.vpc_connector_cidr
}

# Receiver Cloud Run Service
resource "google_cloud_run_v2_service" "receiver" {
  name     = "${var.name_prefix}-receiver"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.bytefreezer.email

    scaling {
      min_instance_count = var.receiver_min_instances
      max_instance_count = var.receiver_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.bytefreezer.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.image_registry}/bytefreezer-receiver:${var.image_tag}"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.receiver_cpu
          memory = var.receiver_memory
        }
      }

      env {
        name  = "RECEIVER_S3_ENDPOINT"
        value = "storage.googleapis.com"
      }

      env {
        name  = "RECEIVER_S3_BUCKET"
        value = "${google_storage_bucket.bytefreezer.name}/intake"
      }

      env {
        name  = "RECEIVER_S3_SSL"
        value = "true"
      }

      env {
        name  = "RECEIVER_CONTROL_URL"
        value = var.control_service_url
      }

      env {
        name = "RECEIVER_CONTROL_SERVICE_API_KEY"
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
    google_secret_manager_secret_iam_member.bytefreezer,
    google_storage_bucket_iam_member.bytefreezer
  ]
}

# Allow unauthenticated access to receiver
resource "google_cloud_run_v2_service_iam_member" "receiver_public" {
  count    = var.receiver_allow_unauthenticated ? 1 : 0
  location = google_cloud_run_v2_service.receiver.location
  name     = google_cloud_run_v2_service.receiver.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Piper Cloud Run Service
resource "google_cloud_run_v2_service" "piper" {
  name     = "${var.name_prefix}-piper"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = google_service_account.bytefreezer.email

    scaling {
      min_instance_count = var.piper_min_instances
      max_instance_count = var.piper_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.bytefreezer.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.image_registry}/bytefreezer-piper:${var.image_tag}"

      ports {
        container_port = 8082
      }

      resources {
        limits = {
          cpu    = var.piper_cpu
          memory = var.piper_memory
        }
      }

      env {
        name  = "PIPER_S3_SOURCE_ENDPOINT"
        value = "storage.googleapis.com"
      }

      env {
        name  = "PIPER_S3_SOURCE_BUCKET"
        value = "${google_storage_bucket.bytefreezer.name}/intake"
      }

      env {
        name  = "PIPER_S3_DESTINATION_ENDPOINT"
        value = "storage.googleapis.com"
      }

      env {
        name  = "PIPER_S3_DESTINATION_BUCKET"
        value = "${google_storage_bucket.bytefreezer.name}/piper"
      }

      env {
        name  = "PIPER_S3_SSL"
        value = "true"
      }

      env {
        name  = "PIPER_CONTROL_URL"
        value = var.control_service_url
      }

      env {
        name = "PIPER_CONTROL_SERVICE_API_KEY"
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
    google_secret_manager_secret_iam_member.bytefreezer,
    google_storage_bucket_iam_member.bytefreezer
  ]
}

# Packer Cloud Run Service
resource "google_cloud_run_v2_service" "packer" {
  name     = "${var.name_prefix}-packer"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = google_service_account.bytefreezer.email

    scaling {
      min_instance_count = var.packer_min_instances
      max_instance_count = var.packer_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.bytefreezer.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.image_registry}/bytefreezer-packer:${var.image_tag}"

      ports {
        container_port = 8083
      }

      resources {
        limits = {
          cpu    = var.packer_cpu
          memory = var.packer_memory
        }
      }

      env {
        name  = "PACKER_S3SOURCE_ENDPOINT"
        value = "storage.googleapis.com"
      }

      env {
        name  = "PACKER_S3SOURCE_BUCKET"
        value = "${google_storage_bucket.bytefreezer.name}/piper"
      }

      env {
        name  = "PACKER_S3DESTINATION_ENDPOINT"
        value = "storage.googleapis.com"
      }

      env {
        name  = "PACKER_S3DESTINATION_BUCKET"
        value = "${google_storage_bucket.bytefreezer.name}/packer"
      }

      env {
        name  = "PACKER_S3_SSL"
        value = "true"
      }

      env {
        name  = "PACKER_CONTROL_URL"
        value = var.control_service_url
      }

      env {
        name = "PACKER_CONTROL_SERVICE_API_KEY"
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
    google_secret_manager_secret_iam_member.bytefreezer,
    google_storage_bucket_iam_member.bytefreezer
  ]
}
