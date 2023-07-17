terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.65.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "mid" {
  source                = "./modules/managedIdentity"
  resource_group_name   = "rg-terraform-aks"
  managed_identity_name = "terraform-aks-mid"
}

module "monitor" {
  source                    = "./modules/monitor"
  resource_group_name       = "rg-terraform-aks"
  action_group_name         = "terraform-aks-ag"
  action_group_short_name   = "terraform-aks-ag"
  actitivity_log_alert_name = "terraform-aks-ala"
  automation_account_id     = module.mid.managed_identity_id
  runbook_name              = "terraform-aks-rb"
  webhook_resource_id       = "terraform-aks-wr"
  is_global_runbook         = true
  service_uri               = "terraform-aks-su"
}

