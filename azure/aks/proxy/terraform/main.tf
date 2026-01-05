# ByteFreezer Proxy - Azure AKS
# Deploy proxy to existing AKS cluster at edge location

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

# Use existing AKS cluster
data "azurerm_kubernetes_cluster" "existing" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.existing.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].cluster_ca_certificate)
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
