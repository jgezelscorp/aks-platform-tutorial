# main.tf — AKS platform (faithful to deck Section 4 IaC excerpt, completed to a
# validatable config: adds the referenced RG/VNet/subnet + user node pool).
# Validate with:  terraform init -backend=false && terraform validate
# Apply with:     terraform init && terraform apply

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}-${var.env}"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefix}-${var.env}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "sys" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/20"]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                              = "aks-${var.prefix}-${var.env}"
  location                          = var.location
  resource_group_name               = azurerm_resource_group.rg.name
  dns_prefix                        = var.prefix
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Standard"
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = [var.admin_group_object_id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }

  default_node_pool {
    name           = "systempool"
    vm_size        = "Standard_D4s_v5"
    node_count     = 3
    zones          = ["1", "2", "3"]
    vnet_subnet_id = azurerm_subnet.sys.id
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  vm_size               = "Standard_D4s_v5"
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 3
  zones                 = ["1", "2", "3"]
  vnet_subnet_id        = azurerm_subnet.sys.id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}
