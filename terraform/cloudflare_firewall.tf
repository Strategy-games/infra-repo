# Cloudflare WAF / ファイアウォールルール

resource "cloudflare_ruleset" "zone_firewall" {
  zone_id     = var.cloudflare_zone_id
  name        = "Strategy Games Firewall Rules"
  description = "基本的なWAFルール"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "block"
    description = "管理系 URL への直接アクセス拒否 (Access 経由のみ許可)"
    enabled     = true
    expression  = "(http.host eq \"argocd.strategy-games.net\" and not cf.access.authenticated) or (http.host eq \"grafana.strategy-games.net\" and not cf.access.authenticated)"
  }

  rules {
    action      = "challenge"
    description = "高頻度リクエストへのチャレンジ"
    enabled     = true
    expression  = "(rate(http.request.uri.path, 1m) > 500)"
  }
}
