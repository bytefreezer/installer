# ByteFreezer Processing Stack - Azure Container Instances
# Serverless container deployment (similar to AWS ECS Fargate)

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
resource "azurerm_resource_group" "bytefreezer" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# Virtual Network for container instances
resource "azurerm_virtual_network" "bytefreezer" {
  name                = "${var.name_prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.bytefreezer.location
  resource_group_name = azurerm_resource_group.bytefreezer.name
  tags                = var.tags
}

resource "azurerm_subnet" "containers" {
  name                 = "containers"
  resource_group_name  = azurerm_resource_group.bytefreezer.name
  virtual_network_name = azurerm_virtual_network.bytefreezer.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "aci-delegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Storage Account
resource "azurerm_storage_account" "bytefreezer" {
  name                     = replace("${var.name_prefix}stor", "-", "")
  resource_group_name      = azurerm_resource_group.bytefreezer.name
  location                 = azurerm_resource_group.bytefreezer.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

# Storage Containers
resource "azurerm_storage_container" "intake" {
  name                  = "bytefreezer-intake"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "piper" {
  name                  = "bytefreezer-piper"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "geoip" {
  name                  = "bytefreezer-geoip"
  storage_account_name  = azurerm_storage_account.bytefreezer.name
  container_access_type = "private"
}

# Receiver Container Group
resource "azurerm_container_group" "receiver" {
  name                = "${var.name_prefix}-receiver"
  location            = azurerm_resource_group.bytefreezer.location
  resource_group_name = azurerm_resource_group.bytefreezer.name
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = "${var.name_prefix}-receiver"

  container {
    name   = "receiver"
    image  = "${var.image_registry}/bytefreezer-receiver:${var.image_tag}"
    cpu    = var.receiver_cpu
    memory = var.receiver_memory

    ports {
      port     = 8080
      protocol = "TCP"
    }

    ports {
      port     = 8081
      protocol = "TCP"
    }

    environment_variables = {
      RECEIVER_S3_ENDPOINT = azurerm_storage_account.bytefreezer.primary_blob_endpoint
      RECEIVER_S3_BUCKET   = "bytefreezer-intake"
      RECEIVER_S3_SSL      = "true"
      RECEIVER_CONTROL_URL = var.control_service_url
    }

    secure_environment_variables = {
      RECEIVER_S3_ACCESS_KEY             = azurerm_storage_account.bytefreezer.name
      RECEIVER_S3_SECRET_KEY             = azurerm_storage_account.bytefreezer.primary_access_key
      RECEIVER_CONTROL_SERVICE_API_KEY   = var.control_service_api_key
    }
  }

  tags = var.tags
}

# Piper Container Group
resource "azurerm_container_group" "piper" {
  name                = "${var.name_prefix}-piper"
  location            = azurerm_resource_group.bytefreezer.location
  resource_group_name = azurerm_resource_group.bytefreezer.name
  os_type             = "Linux"
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.containers.id]

  container {
    name   = "piper"
    image  = "${var.image_registry}/bytefreezer-piper:${var.image_tag}"
    cpu    = var.piper_cpu
    memory = var.piper_memory

    ports {
      port     = 8082
      protocol = "TCP"
    }

    environment_variables = {
      PIPER_S3_SOURCE_ENDPOINT      = azurerm_storage_account.bytefreezer.primary_blob_endpoint
      PIPER_S3_SOURCE_BUCKET        = "bytefreezer-intake"
      PIPER_S3_DESTINATION_ENDPOINT = azurerm_storage_account.bytefreezer.primary_blob_endpoint
      PIPER_S3_DESTINATION_BUCKET   = "bytefreezer-piper"
      PIPER_S3_SSL                  = "true"
      PIPER_CONTROL_URL             = var.control_service_url
    }

    secure_environment_variables = {
      PIPER_S3_SOURCE_ACCESS_KEY      = azurerm_storage_account.bytefreezer.name
      PIPER_S3_SOURCE_SECRET_KEY      = azurerm_storage_account.bytefreezer.primary_access_key
      PIPER_S3_DESTINATION_ACCESS_KEY = azurerm_storage_account.bytefreezer.name
      PIPER_S3_DESTINATION_SECRET_KEY = azurerm_storage_account.bytefreezer.primary_access_key
      PIPER_CONTROL_SERVICE_API_KEY   = var.control_service_api_key
    }
  }

  tags = var.tags
}

# Packer Container Group
resource "azurerm_container_group" "packer" {
  name                = "${var.name_prefix}-packer"
  location            = azurerm_resource_group.bytefreezer.location
  resource_group_name = azurerm_resource_group.bytefreezer.name
  os_type             = "Linux"
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.containers.id]

  container {
    name   = "packer"
    image  = "${var.image_registry}/bytefreezer-packer:${var.image_tag}"
    cpu    = var.packer_cpu
    memory = var.packer_memory

    ports {
      port     = 8083
      protocol = "TCP"
    }

    environment_variables = {
      BYTEFREEZER_S3SOURCE_ENDPOINT     = azurerm_storage_account.bytefreezer.primary_blob_endpoint
      BYTEFREEZER_S3SOURCE_BUCKET_NAME  = "bytefreezer-piper"
      BYTEFREEZER_S3SOURCE_SSL          = "true"
      # Note: Packer outputs to per-tenant destinations from Control API
      BYTEFREEZER_CONTROL_SERVICE_URL   = var.control_service_url
    }

    secure_environment_variables = {
      BYTEFREEZER_S3SOURCE_ACCESS_KEY       = azurerm_storage_account.bytefreezer.name
      BYTEFREEZER_S3SOURCE_SECRET_KEY       = azurerm_storage_account.bytefreezer.primary_access_key
      BYTEFREEZER_CONTROL_SERVICE_API_KEY   = var.control_service_api_key
    }
  }

  tags = var.tags
}
