output "allocation_service_hostname" {
  description = "External IP of the Agones allocator Service on the routing cluster (game clients connect here)."
  value       = module.router.allocation_service_hostname
}

output "allocation_service_client_tls_crt" {
  description = "Base64-encoded client TLS certificate for the allocator service (mTLS)."
  value       = module.router.allocation_service_client_tls_crt
  sensitive   = true
}

output "allocation_service_client_tls_key" {
  description = "Base64-encoded client TLS private key for the allocator service (mTLS)."
  value       = module.router.allocation_service_client_tls_key
  sensitive   = true
}

output "allocation_service_server_tls_crt" {
  description = "Base64-encoded server TLS certificate (CA) for the allocator service (mTLS)."
  value       = module.router.allocation_service_server_tls_crt
  sensitive   = true
}

output "log_bucket" {
  description = "Name of the OBS bucket used for ELB access logs / artifacts."
  value       = huaweicloud_obs_bucket.log_bucket.bucket
}
