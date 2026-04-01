resource "cloudflare_tunnel" "main" {
  account_id = var.cloudflare_account_id
  name       = "strategy-games-tunnel"
  secret     = random_id.tunnel_secret.b64_std
}

resource "random_id" "tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_tunnel_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.main.id

  config {
    # デバッグ MC サーバー (TCP)
    ingress_rule {
      hostname = "debug.strategy-games.net"
      service  = "tcp://192.168.10.200:25565"
    }

    # BlueMap debug
    ingress_rule {
      hostname = "map-debug.strategy-games.net"
      service  = "http://192.168.10.201:8100"
    }

    # ArgoCD UI (管理者のみ)
    ingress_rule {
      hostname = "argocd.strategy-games.net"
      service  = "https://192.168.10.202:443"
    }

    # Grafana (管理者のみ)
    ingress_rule {
      hostname = "grafana.strategy-games.net"
      service  = "http://192.168.10.203:3000"
    }

    # catch-all
    ingress_rule {
      service = "http_status:404"
    }
  }
}
