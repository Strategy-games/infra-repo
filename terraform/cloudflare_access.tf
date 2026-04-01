# Cloudflare Zero Trust Access - 管理系サービス (Google OAuth)

resource "cloudflare_access_application" "argocd" {
  zone_id          = var.cloudflare_zone_id
  name             = "ArgoCD"
  domain           = "argocd.strategy-games.net"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_access_policy" "argocd_infra_team" {
  application_id = cloudflare_access_application.argocd.id
  zone_id        = var.cloudflare_zone_id
  name           = "Infra Team"
  precedence     = 1
  decision       = "allow"

  include {
    email_domain = ["strategy-games.net"]
  }
}

resource "cloudflare_access_application" "grafana" {
  zone_id          = var.cloudflare_zone_id
  name             = "Grafana"
  domain           = "grafana.strategy-games.net"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_access_policy" "grafana_infra_team" {
  application_id = cloudflare_access_application.grafana.id
  zone_id        = var.cloudflare_zone_id
  name           = "Infra Team"
  precedence     = 1
  decision       = "allow"

  include {
    email_domain = ["strategy-games.net"]
  }
}

resource "cloudflare_access_application" "bluemap_debug" {
  zone_id          = var.cloudflare_zone_id
  name             = "BlueMap Debug"
  domain           = "map-debug.strategy-games.net"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_access_policy" "bluemap_debug_team" {
  application_id = cloudflare_access_application.bluemap_debug.id
  zone_id        = var.cloudflare_zone_id
  name           = "Debug Players"
  precedence     = 1
  decision       = "allow"

  include {
    email_domain = ["strategy-games.net"]
  }
}
