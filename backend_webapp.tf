resource "azurerm_resource_group" "rg" {
  name     = "webApp-rg"
  location = "eastus"
}

resource "azurerm_app_service_plan" "plan" {
  name                = "webApp-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true

  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_application_insights" "app_insights" {
  name                = "backend-ai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}


data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                     = "kv-backend-prod"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  sku_name                 = "standard"
  tenant_id                = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled = true

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [azurerm_subnet.backend_subnet.id]
  }
}

resource "azurerm_key_vault_secret" "db_conn" {
  name         = "DB-Connection"
  value        = "<db-connection-string>"
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "storage_key" {
  name         = "Storage-Key"
  value        = "<storage-key>"
  key_vault_id = azurerm_key_vault.kv.id
}


resource "azurerm_virtual_network" "web_app_vnet" {
  name                = "web-app-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "backend_subnet" {
  name                 = "backend-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.web_app_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private_endpoint_subnet" {
  name                 = "private-endpoint-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.web_app_vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet_private_endpoint_network_policies" "pe_policy" {
  subnet_id                         = azurerm_subnet.private_endpoint_subnet.id
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_storage_account" "backend_sa" {
  name                     = "backendstorageprod"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  #enable_https_traffic_only = true
  is_hns_enabled = true
}

resource "azurerm_storage_container" "uploads" {
  name = "uploads"
  #storage_account_name  = azurerm_storage_account.backend_sa.name
  container_access_type = "private"
}

resource "azurerm_container_registry" "acr" {
  name                          = "privatewebappacr"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false

  network_rule_set {
    default_action = "Deny"
  }
}

resource "azurerm_security_center_subscription_pricing" "defender_acr" {
  tier          = "Standard"
  resource_type = "ContainerRegistry"
}
//AZURE SQL DATABASE SETUP
resource "azurerm_mssql_server" "sql_server" {
  name                = "backend-sql-server-prod"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  version             = "12.0"

  administrator_login          = "sqladminuser"
  administrator_login_password = "<your-password>"

  public_network_access_enabled = false
}
resource "azurerm_mssql_database" "sql_database" {
  name        = "backend-database-prod"
  server_id   = azurerm_mssql_server.sql_server.id
  sku_name    = "S0"
  collation   = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb = 10
}

//PRIVATE ENDPOINT FOR SQL DATABASE + DNS SETUP
resource "azurerm_private_endpoint" "sql_pe" {
  name                = "sql-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "sql-privatelink-connection"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone" "sql_dns" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_link" {
  name                  = "sql-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns.name
  resource_group_name   = azurerm_resource_group.rg.name
  virtual_network_id    = azurerm_virtual_network.web_app_vnet.id
}
resource "azurerm_private_dns_zone_group" "sql_dns_group" {
  name                = "sql-dns-zone-group"
  private_endpoint_id = azurerm_private_endpoint.sql_pe.id

  private_dns_zone_configs {
    name                = "sql-dns"
    private_dns_zone_id = azurerm_private_dns_zone.sql_dns.id
  }
}
//ENABLE AZURE AD ADMIN AUTHENTICATION FOR SQL SERVER
resource "azurerm_mssql_server_active_directory_administrator" "sql_aad_admin" {
  server_id = azurerm_mssql_server.sql_server.id
  login     = "AzureADAdmin"
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = var.aad_admin_object_id
}

//PRIVATE ENDPOINT FOR ACR + DNS SETUP
resource "azurerm_private_endpoint" "acr_private_endpoint" {
  name                = "acr-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "acr-privatelink-connection"
    private_connection_resource_id = azurerm_container_registry.acr.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }
}

resource "azurerm_private_dns_zone" "acr_dns" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_dns_link" {
  name                  = "acr-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.acr_dns.name
  resource_group_name   = azurerm_resource_group.rg.name
  virtual_network_id    = azurerm_virtual_network.web_app_vnet.id
}

resource "azurerm_private_dns_zone_group" "acr_dns_group" {
  name                = "acr-dns-zone-group"
  private_endpoint_id = azurerm_private_endpoint.acr_private_endpoint.id

  private_dns_zone_configs {
    name                = "acr-dns"
    private_dns_zone_id = azurerm_private_dns_zone.acr_dns.id
  }
}
//PRIVATE ENDPOINT FOR KEY VAULT + DNS SETUP
resource "azurerm_private_dns_zone" "kv_dns" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_dns_link" {
  name                  = "kv-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.kv_dns.name
  resource_group_name   = azurerm_resource_group.rg.name
  virtual_network_id    = azurerm_virtual_network.web_app_vnet.id
}

resource "azurerm_private_endpoint" "kv_private_endpoint" {
  name                = "kv-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "kv-privatelink-connection"
    private_connection_resource_id = azurerm_key_vault.kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

resource "azurerm_private_dns_zone_group" "kv_dns_group" {
  name                = "kv-dns-zone-group"
  private_endpoint_id = azurerm_private_endpoint.kv_private_endpoint.id

  private_dns_zone_configs {
    name                = "kv-dns"
    private_dns_zone_id = azurerm_private_dns_zone.kv_dns.id
  }
}

//PRIVATE ENDPOINT FOR STORAGE ACCOUNT + DNS SETUP
resource "azurerm_private_dns_zone" "sa_dns" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}
resource "azurerm_private_dns_zone_virtual_network_link" "sa_dns_link" {
  name                  = "sa-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.sa_dns.name
  resource_group_name   = azurerm_resource_group.rg.name
  virtual_network_id    = azurerm_virtual_network.web_app_vnet.id
}

resource "azurerm_private_endpoint" "sa_private_endpoint" {
  name                = "sa-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "sa-privatelink-connection"
    private_connection_resource_id = azurerm_storage_account.backend_sa.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
}
resource "azurerm_private_dns_zone_group" "sa_dns_group" {
  name                = "sa-dns-zone-group"
  private_endpoint_id = azurerm_private_endpoint.sa_private_endpoint.id

  private_dns_zone_configs {
    name                = "sa-dns"
    private_dns_zone_id = azurerm_private_dns_zone.sa_dns.id
  }
}
// BACKEND WEB APP
resource "azurerm_app_service" "backend" {
  name                = "backend-webapp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.plan.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    linux_fx_version = "DOCKER|<your-backend-image>"
    always_on        = true
    http2_enabled    = true
  }

  https_only = true

  app_settings = {
    APP_ROLE                              = "backend"
    DB_CONNECTION                         = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.kv.vault_uri}secrets/DB-Connection)"
    STORAGE_ACCOUNT_KEY                   = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.kv.vault_uri}secrets/Storage-Key)"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.app_insights.connection_string
  }

  depends_on = [
    azurerm_app_service_plan.plan,
    azurerm_key_vault_secret.db_conn,
    azurerm_key_vault_secret.storage_key
  ]
}

data "azurerm_subscription" "current" {}



//rbac for app service to access ACR, Storage Account, and Key Vault

data "azurerm_role_definition" "acr_pull" {
  name  = "AcrPull"
  scope = data.azurerm_subscription.current.id
}

resource "azurerm_role_assignment" "appservice_acr_pull" {
  scope              = azurerm_container_registry.acr.id
  principal_id       = azurerm_app_service.backend.identity[0].principal_id
  role_definition_id = data.azurerm_role_definition.acr_pull.id
}

resource "azurerm_role_assignment" "appservice_storage" {
  principal_id         = azurerm_app_service.backend.identity[0].principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.backend_sa.id
}

resource "azurerm_role_assignment" "appservice_kv" {
  principal_id         = azurerm_app_service.backend.identity[0].principal_id
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.kv.id
}

