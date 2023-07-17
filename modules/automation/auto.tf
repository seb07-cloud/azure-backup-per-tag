data "local_file" "demo_ps1" {
  filename = "../runbooks/powershell/demo.ps1"
}

resource "azurerm_automation_account" "this" {
  name                = var.automation_account_name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
}

# create a azurerm automation runbook to run a powershell script

resource "azurerm_automation_runbook" "demo_rb" {
  name                    = "Demo-Runbook"
  location                = azurerm_resource_group.rg_automation_account.location
  resource_group_name     = azurerm_resource_group.rg_automation_account.name
  automation_account_name = azurerm_automation_account.aa_demo.name
  log_verbose             = "true"
  log_progress            = "true"
  description             = "This Run Book is a demo"
  runbook_type            = "PowerShell"
  content                 = data.local_file.demo_ps1.content
}
