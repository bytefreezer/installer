# ByteFreezer Processing Stack - Azure AKS
# Deploys: AKS cluster, receiver, piper, packer, storage

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "bytefreezer" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# Storage Account for S3-compatible storage (Azure Blob with S3 API)
resource "azurerm_storage_account" "bytefreezer" {
  name                     = replace("${var.name_prefix}storage", "-", "")
  resource_group_name      = azurerm_resource_group.bytefreezer.name
  location                 = azurerm_resource_group.bytefreezer.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  blob_properties {
    versioning_enabled = true
  }

  tags = var.tags
}

# Storage Containers (buckets)
resource "azurerm_storage_container" "intake" {
  name                  = "intake"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "piper" {
  name                  = "piper"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "packer" {
  name                  = "packer"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "geoip" {
  name                  = "geoip"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "bytefreezer" {
  name                = "${var.name_prefix}-aks"
  location            = azurerm_resource_group.bytefreezer.location
  resource_group_name = azurerm_resource_group.bytefreezer.name
  dns_prefix          = var.name_prefix
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    enable_auto_scaling = var.enable_autoscaling
    min_count           = var.enable_autoscaling ? var.min_node_count : null
    max_count           = var.enable_autoscaling ? var.max_node_count : null
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = var.tags
}

# Role assignment for AKS to access storage
resource "azurerm_role_assignment" "aks_storage" {
  scope                = azurerm_storage_account.bytefreezer.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster.bytefreezer.kubelet_identity[0].object_id
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.bytefreezer.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.bytefreezer.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.bytefreezer.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.bytefreezer.kube_config[0].cluster_ca_certificate)
  }
}

# Deploy ByteFreezer using Helm
resource "helm_release" "bytefreezer" {
  count = var.deploy_helm_chart ? 1 : 0

  name       = "bytefreezer"
  chart      = var.helm_chart_path
  namespace  = var.namespace
  create_namespace = true

  set {
    name  = "s3.endpoint"
    value = "${azurerm_storage_account.bytefreezer.name}.blob.core.windows.net"
  }

  set {
    name  = "s3.useSSL"
    value = "true"
  }

  set_sensitive {
    name  = "s3.accessKey"
    value = azurerm_storage_account.bytefreezer.name
  }

  set_sensitive {
    name  = "s3.secretKey"
    value = azurerm_storage_account.bytefreezer.primary_access_key
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
    azurerm_role_assignment.aks_storage
  ]
}
