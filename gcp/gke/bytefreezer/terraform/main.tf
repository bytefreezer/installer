# ByteFreezer Processing Stack - Google Kubernetes Engine (GKE)

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

resource "google_storage_bucket_object" "packer" {
  name    = "packer/"
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

# GKE Cluster
resource "google_container_cluster" "bytefreezer" {
  name     = "${var.name_prefix}-gke"
  location = var.zone != "" ? var.zone : var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = var.labels
}

# Node Pool
resource "google_container_node_pool" "primary" {
  name       = "${var.name_prefix}-node-pool"
  location   = var.zone != "" ? var.zone : var.region
  cluster    = google_container_cluster.bytefreezer.name
  node_count = var.node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb

    service_account = google_service_account.bytefreezer.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = var.labels
  }
}

# Get cluster credentials for Helm
data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.bytefreezer.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.bytefreezer.master_auth[0].cluster_ca_certificate)
  }
}

# Kubernetes Service Account for Workload Identity
resource "kubernetes_service_account" "bytefreezer" {
  count = var.deploy_helm_chart ? 1 : 0

  metadata {
    name      = "bytefreezer"
    namespace = var.namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.bytefreezer.email
    }
  }

  depends_on = [google_container_node_pool.primary]
}

# IAM binding for Workload Identity
resource "google_service_account_iam_member" "workload_identity" {
  count = var.deploy_helm_chart ? 1 : 0

  service_account_id = google_service_account.bytefreezer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/bytefreezer]"
}

# Deploy ByteFreezer using Helm
resource "helm_release" "bytefreezer" {
  count = var.deploy_helm_chart ? 1 : 0

  name             = "bytefreezer"
  chart            = var.helm_chart_path
  namespace        = var.namespace
  create_namespace = true

  set {
    name  = "s3.endpoint"
    value = "storage.googleapis.com"
  }

  set {
    name  = "s3.region"
    value = var.region
  }

  set {
    name  = "s3.useSSL"
    value = "true"
  }

  set {
    name  = "s3.buckets.intake"
    value = "${google_storage_bucket.bytefreezer.name}/intake"
  }

  set {
    name  = "s3.buckets.piper"
    value = "${google_storage_bucket.bytefreezer.name}/piper"
  }

  set {
    name  = "s3.buckets.packer"
    value = "${google_storage_bucket.bytefreezer.name}/packer"
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
    name  = "serviceAccount.name"
    value = "bytefreezer"
  }

  set {
    name  = "receiver.replicaCount"
    value = var.receiver_replicas
  }

  set {
    name  = "piper.replicaCount"
    value = var.piper_replicas
  }

  set {
    name  = "packer.replicaCount"
    value = var.packer_replicas
  }

  set {
    name  = "monitoring.enabled"
    value = var.enable_monitoring
  }

  depends_on = [
    google_container_node_pool.primary,
    kubernetes_service_account.bytefreezer,
    google_service_account_iam_member.workload_identity
  ]
}
