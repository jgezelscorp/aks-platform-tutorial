variable "prefix" {
  type    = string
  default = "aksplat"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "admin_group_object_id" {
  type        = string
  description = "Entra ID group object ID granted cluster-admin via Azure RBAC."
}

variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription ID (or set ARM_SUBSCRIPTION_ID)."
}

variable "kubernetes_version" {
  type    = string
  default = "1.31.1"
}
