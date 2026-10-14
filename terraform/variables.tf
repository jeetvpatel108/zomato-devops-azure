variable "subscription_id" {
  description = "Azure subscription ID (run: az account show --query id -o tsv)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "Zomato_project"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "Zomato"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralindia"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for worker nodes"
  type        = string
  default     = "Standard_B2s"
}
