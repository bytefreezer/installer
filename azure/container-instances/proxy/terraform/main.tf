# ByteFreezer Proxy - Azure Container Instances

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "proxy" {
  name     = "${var.name_prefix}-proxy-rg"
  location = var.location
  tags     = var.tags
}

# Proxy Container Group
resource "azurerm_container_group" "proxy" {
  name                = "${var.name_prefix}-proxy"
  location            = azurerm_resource_group.proxy.location
  resource_group_name = azurerm_resource_group.proxy.name
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = "${var.name_prefix}-proxy"

  container {
    name   = "proxy"
    image  = "${var.image_registry}/bytefreezer-proxy:${var.image_tag}"
    cpu    = var.cpu
    memory = var.memory

    ports {
      port     = 8008
      protocol = "TCP"
    }

    dynamic "ports" {
      for_each = var.udp_ports
      content {
        port     = ports.value
        protocol = "UDP"
      }
    }

    environment_variables = {
      PROXY_RECEIVER_URL  = var.receiver_url
      PROXY_CONTROL_URL   = var.control_service_url
    }

    secure_environment_variables = {
      PROXY_CONTROL_SERVICE_API_KEY = var.control_service_api_key
    }
  }

  tags = var.tags
}
