terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.68.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.41.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.9.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
  }
}

provider "azurerm" {
  features {}
}

# Current Subscription ID + Tenant ID
data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-backup-tagging"
  location = "westeurope"
}

resource "azurerm_automation_account" "automation_aa" {
  name                = "automation-account"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "aa_system_id" {
  scope                = azurerm_automation_account.automation_aa.id
  role_definition_name = "Backup Contributor"
  principal_id         = azurerm_automation_account.automation_aa.identity[0].principal_id
}

data "local_file" "backup_tagging_pwsh" {
  filename = "../runbook/Check-TagsAndAssignBackupPolicy.ps1"
}

data "local_file" "backup_tagging_helper_functions" {
  filename = "../runbook/modules/Helper-Functions.psm1"
}

resource "azurerm_automation_runbook" "backup_tagging_runbook" {
  name                    = "Check-TagsAndAssignBackupPolicy"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_aa.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShellWorkflow"

  content = data.local_file.backup_tagging_pwsh.content
}

resource "azurerm_automation_module" "az_accounts" {
  name                    = "Az.Accounts"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_aa.name
  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Accounts/2.12.5"
  }

  timeouts {
    create = "10m"
  }

  lifecycle {
    ignore_changes = [
      name
    ]
  }
}

resource "azurerm_automation_module" "az_compute" {
  name                    = "Az.Compute"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_aa.name
  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Compute/6.2.0"
  }

  depends_on = [azurerm_automation_module.az_accounts]

  timeouts {
    create = "10m"
  }

  lifecycle {
    ignore_changes = [
      name
    ]
  }
}

resource "azurerm_automation_webhook" "backup_tagging_webhook" {
  name                    = "Check-TagsAndAssignBackupPolicy"
  resource_group_name     = azurerm_resource_group.rg.name
  automation_account_name = azurerm_automation_account.automation_aa.name
  runbook_name            = azurerm_automation_runbook.backup_tagging_runbook.name
  expiry_time             = "2025-01-01T00:00:00+00:00"

  depends_on = [
    azurerm_automation_runbook.backup_tagging_runbook,
  ]
}

output "azurerm_automation_webhook_uri" {
  value     = azurerm_automation_webhook.backup_tagging_webhook.uri
  sensitive = true
}

output "service_principal_id" {
  value     = azurerm_automation_account.automation_aa.identity[0].principal_id
  sensitive = true
}
