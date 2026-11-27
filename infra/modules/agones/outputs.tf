output "gameserver_namespace" {
  description = "Namespace Agones GameServers are scheduled into."
  value       = var.gameserver_namespace
}

output "cluster_name" {
  description = "Logical cluster name handed to the router for GameServerAllocationPolicy."
  value       = var.cluster_name
}

output "allocation_service_hostname" {
  description = "Agones allocator Service ELB address (used by the router for multi-cluster allocation)."
  value       = try(coalesce(
    data.kubernetes_service.allocation_service.status.0.load_balancer.0.ingress.0.hostname,
    data.kubernetes_service.allocation_service.status.0.load_balancer.0.ingress.0.ip,
  ), null)
}

output "allocation_service_client_tls_crt" {
  description = "Allocator client certificate (mTLS) — injected into the router's GameServerAllocationPolicy."
  value       = try(data.kubernetes_secret.allocator_client_cert.data["tls.crt"], null)
  sensitive   = true
}

output "allocation_service_client_tls_key" {
  description = "Allocator client private key (mTLS) — injected into the router's GameServerAllocationPolicy."
  value       = try(data.kubernetes_secret.allocator_client_cert.data["tls.key"], null)
  sensitive   = true
}

output "allocation_service_server_tls_crt" {
  description = "Allocator server CA certificate (mTLS) — router validates the DGS allocator against this."
  value       = try(data.kubernetes_secret.allocator_server_cert.data["tls.crt"], null)
  sensitive   = true
}
