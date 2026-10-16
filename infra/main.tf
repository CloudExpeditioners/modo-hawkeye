
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

resource "azurerm_resource_group" "hawkeye" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "modo-hawkeye"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_log_analytics_workspace" "hawkeye" {
  name                = "law-modo-hawkeye-demo"
  location            = azurerm_resource_group.hawkeye.location
  resource_group_name = azurerm_resource_group.hawkeye.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    project     = "modo-hawkeye"
    environment = var.environment
    managed_by  = "terraform"
  }
}
