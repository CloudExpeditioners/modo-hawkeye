
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # El backend remoto en Azure se configurará
  # en un paso posterior.
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}
