variable "location" {
  description = "Region de Azure para el laboratorio Modo Hawkeye"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource Group del laboratorio"
  type        = string
  default     = "rg-modo-hawkeye-demo"
}

variable "environment" {
  description = "Entorno de demostracion"
  type        = string
  default     = "demo"
}
