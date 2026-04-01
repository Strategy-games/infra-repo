# シークレットは Terraform Cloud の sensitive variables として管理
# 実際の値は variables.tf の sensitive = true 変数経由で注入

# ArgoCD 初期パスワード (bootstrap のみ。以降は argocd CLI で変更)
resource "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret-override"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    # 実際の値は Terraform Cloud の変数で設定
    # password = var.argocd_admin_password (要 variable 追加)
  }

  type = "Opaque"

  lifecycle {
    ignore_changes = [data]
  }
}

# Minecraft Debug サーバー用 RCON パスワード
# NOTE: 実際の値は手動で kubectl create secret して注入するか
#       External Secrets Operator を使用
# resource "kubernetes_secret" "mc_debug_rcon" {
#   metadata {
#     name      = "minecraft-debug-secrets"
#     namespace = kubernetes_namespace.minecraft_debug.metadata[0].name
#   }
#   data = {
#     rcon-password = var.mc_debug_rcon_password
#   }
#   type = "Opaque"
# }
