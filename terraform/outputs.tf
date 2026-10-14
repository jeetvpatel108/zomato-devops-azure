output "resource_group_name" {
  value = azurerm_resource_group.zomato.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.zomato.name
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.zomato.name} --name ${azurerm_kubernetes_cluster.zomato.name} --admin --overwrite-existing"
}
