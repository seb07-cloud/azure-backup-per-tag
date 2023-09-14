resource "azuread_application" "app" {
  display_name = "backup-tagging"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "spn" {
  application_id               = azuread_application.app.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

# create service principal client secret
resource "azuread_service_principal_password" "spn_pwd" {
  service_principal_id = azuread_service_principal.spn.id
  end_date_relative    = "8760h" # 1 year
}
