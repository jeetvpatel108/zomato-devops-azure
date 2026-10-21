resource "azurerm_container_registry" "zomato" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.zomato.name
  location            = azurerm_resource_group.zomato.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Let the AKS cluster's kubelet identity pull images from this ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.zomato.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.zomato.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}