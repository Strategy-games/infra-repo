# strategy-games.net DNS レコード
# Cloudflare Tunnel 経由のため A レコードはプロキシ済み

resource "cloudflare_record" "mc_debug" {
  zone_id = var.cloudflare_zone_id
  name    = "debug"
  value   = "192.0.2.1" # Tunnel 経由のため実 IP は不使用 (Cloudflare が上書き)
  type    = "A"
  proxied = true
  comment = "Debug MC server via Cloudflare Tunnel"
}

resource "cloudflare_record" "bluemap_debug" {
  zone_id = var.cloudflare_zone_id
  name    = "map-debug"
  value   = "192.0.2.1"
  type    = "A"
  proxied = true
  comment = "BlueMap debug environment"
}

resource "cloudflare_record" "argocd" {
  zone_id = var.cloudflare_zone_id
  name    = "argocd"
  value   = "192.0.2.1"
  type    = "A"
  proxied = true
  comment = "ArgoCD UI (Access 認証必須)"
}

resource "cloudflare_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  value   = "192.0.2.1"
  type    = "A"
  proxied = true
  comment = "Grafana monitoring dashboard (Access 認証必須)"
}
