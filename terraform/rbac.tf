data "azurerm_role_definition" "backup_contributor" {
  name = "Backup Contributor"
}

resource "azurerm_role_assignment" "example" {
  name               = "4a9ae827-6dc8-4571-9bce-72682b92ebe8"
  scope              = data.azurerm_subscription.current.id
  role_definition_id = data.azurerm_role_definition.backup_contributor.id
  principal_id       = azuread_service_principal.spn.object_id
}
