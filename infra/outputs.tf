output "resource_group_name" {
  value = azurerm_resource_group.hawkeye.name
}

output "log_analytics_workspace_id" {
  description = "Customer ID (GUID) del workspace, usado para consultas KQL"
  value       = azurerm_log_analytics_workspace.hawkeye.workspace_id
}
