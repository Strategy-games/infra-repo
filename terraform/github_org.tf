resource "github_team" "infra" {
  name        = "infra"
  description = "インフラ担当"
  privacy     = "closed"
}

resource "github_team" "mc_ops" {
  name        = "mc-ops"
  description = "MC運営チーム"
  privacy     = "closed"
}

resource "github_team" "moderators" {
  name        = "moderators"
  description = "モデレーター (本番マージ承認権限)"
  privacy     = "closed"
}

resource "github_team" "debug_players" {
  name        = "debug-players"
  description = "デバッグプレイヤー (検証環境テスター)"
  privacy     = "closed"
}
