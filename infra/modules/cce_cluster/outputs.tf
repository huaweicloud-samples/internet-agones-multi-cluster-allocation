output "cluster_name" {
  value = var.cluster_name
}

output "gameserver_namespace" {
  value = module.agones.gameserver_namespace
}

output "allocation_service_hostname" {
  description = "Agones allocator Service 的 ELB 访问地址"
  value       = module.agones.allocation_service_hostname
}

output "allocation_service_client_tls_crt" {
  description = "allocator 客户端证书（mTLS，路由集群注入用）"
  value       = module.agones.allocation_service_client_tls_crt
  sensitive   = true
}

output "allocation_service_client_tls_key" {
  description = "allocator 客户端私钥（mTLS，路由集群注入用）"
  value       = module.agones.allocation_service_client_tls_key
  sensitive   = true
}

output "allocation_service_server_tls_crt" {
  description = "allocator 服务端 CA 证书（路由集群注入用）"
  value       = module.agones.allocation_service_server_tls_crt
  sensitive   = true
}
