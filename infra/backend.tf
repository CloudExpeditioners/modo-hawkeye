terraform {
  backend "azurerm" {
    resource_group_name  = "rg-hawkeye-tfstate"
    storage_account_name = "sthawkeyetfstate2026"
    container_name       = "tfstate"
    key                  = "modo-hawkeye.tfstate"

    use_oidc         = true
    use_azuread_auth = true
  }
}
