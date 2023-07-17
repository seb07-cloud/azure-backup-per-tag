data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "azurerm_user_assigned_identity" "this" {
  name                = var.managed_identity_name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.nameÅÅ
}
