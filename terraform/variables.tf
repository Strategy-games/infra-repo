variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for strategy-games.net"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "k8s_host" {
  description = "Kubernetes API server endpoint"
  type        = string
  default     = "https://192.168.10.100:8443"
}

variable "k8s_client_certificate" {
  description = "Base64-encoded client certificate for k8s auth"
  type        = string
  sensitive   = true
}

variable "k8s_client_key" {
  description = "Base64-encoded client key for k8s auth"
  type        = string
  sensitive   = true
}

variable "k8s_cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  type        = string
  sensitive   = true
}

variable "synology_nas_ip" {
  description = "Synology NAS IP address"
  type        = string
  default     = "192.168.11.10"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.8.0"
}

variable "environment" {
  description = "Deployment environment (debug / production)"
  type        = string
  default     = "debug"
}
