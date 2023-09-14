resource "random_string" "kv_string" {
  length  = 8
  special = false
}

data "http" "icanhazip" {
  url = "http://icanhazip.com"
}

resource "azurerm_key_vault" "kv" {
  # keyvault name new guid
  name                = "kv-${random_string.kv_string.result}"
  location            = resource.azurerm_resource_group.rg.location
  resource_group_name = resource.azurerm_resource_group.rg.name
  tenant_id           = data.azuread_client_config.current.tenant_id

  sku_name = "standard"
  purge_protection_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = ["${trimspace(data.http.icanhazip.body)}/32"]
  }


  access_policy {
    tenant_id = data.azuread_client_config.current.tenant_id
    object_id = resource.azuread_service_principal.spn.object_id

    key_permissions = [
      "Get",
      "List",
      "Update",
      "Create",
      "Import",
      "Delete",
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
    ]

    certificate_permissions = [
      "Get",
      "List",
      "Create",
      "Delete",
      "Import",
      "Update",
      "ManageContacts",
      "ManageIssuers",
      "GetIssuers",
      "ListIssuers",
      "SetIssuers",
      "DeleteIssuers",
      "Purge",
      "Backup",
      "Restore",
    ]
  }

  lifecycle {
    ignore_changes = [
      
    ]
  }
}

resource "azurerm_key_vault_access_policy" "kv_spn_ap" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = data.azuread_client_config.current.tenant_id
  object_id = azuread_service_principal.spn.object_id

  secret_permissions = ["Delete", "Get", "List", "Purge", "Set"]

  certificate_permissions = ["Get", "List", "Create", "Delete", "Update"]
}

resource "azurerm_key_vault_access_policy" "kv_current_principal" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = data.azuread_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  secret_permissions = ["Delete", "Get", "List", "Purge", "Set"]

  certificate_permissions = ["Get", "List", "Create", "Delete", "Update"]
}


resource "azurerm_key_vault_certificate" "self_signed_certificate" {
  name         = "self-signed-certificate"
  key_vault_id = resource.azurerm_key_vault.kv.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=axians-managed-services.at"
      validity_in_months = 12
    }
  }
}

resource "azuread_application_certificate" "example" {
  application_object_id = azuread_application.app.object_id
  type                  = "AsymmetricX509Cert"
  encoding              = "hex"
  value                 = azurerm_key_vault_certificate.self_signed_certificate.certificate_data
  end_date              = azurerm_key_vault_certificate.self_signed_certificate.certificate_attribute[0].expires
  start_date            = azurerm_key_vault_certificate.self_signed_certificate.certificate_attribute[0].not_before
}
