output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = "https://argocd.strategy-games.net"
}

output "k8s_api_endpoint" {
  description = "Kubernetes API VIP endpoint"
  value       = var.k8s_host
}

output "environment" {
  description = "Current environment"
  value       = var.environment
}
