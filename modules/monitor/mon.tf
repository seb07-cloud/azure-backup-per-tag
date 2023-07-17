data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_subscription" "current" {
}

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = data.azurerm_resource_group.this.name
  short_name          = var.action_group_short_name

  automation_runbook_receiver {
    name                  = var.automation_runbook_receiver_name
    automation_account_id = var.automation_account_id
    runbook_name          = var.runbook_name
    webhook_resource_id   = var.webhook_resource_id
    is_global_runbook     = var.is_global_runbook
    service_uri           = var.service_uri
  }
}

resource "azurerm_monitor_activity_log_alert" "this" {
  name                = var.actitivity_log_alert_name
  resource_group_name = azurerm_resource_group.example.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "This alert will trigger when a VM is created."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/write"
    level          = "Informational"
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = data.azurerm_resource_group.this.name
  short_name          = var.action_group_short_name

  automation_runbook_receiver {
    name                  = "Runbook Receiver for Activity Log Alerts for VM Creation"
    automation_account_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.this.name}/providers/Microsoft.Automation/automationAccounts/example-account}"
    runbook_name          = var.runbook_name
    webhook_resource_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.this.name}/providers/Microsoft.Automation/automationAccounts/example-account/webhooks/example-webhook"
    is_global_runbook     = true
  }
}
