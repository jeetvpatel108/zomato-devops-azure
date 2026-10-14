resource "azurerm_resource_group" "zomato" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "zomato" {
  name                = var.cluster_name
  location            = azurerm_resource_group.zomato.location
  resource_group_name = azurerm_resource_group.zomato.name
  dns_prefix          = lower(var.cluster_name)

  # Keeps local accounts enabled so `az aks get-credentials --admin` works
  local_account_disabled = false

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = {
    project = "zomato"
  }
}
