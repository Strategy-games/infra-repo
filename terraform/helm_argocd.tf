resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = "argocd.strategy-games.net"
      }
      server = {
        ingress = {
          enabled = false # Cloudflare Tunnel 経由のため Ingress 不使用
        }
        service = {
          type = "LoadBalancer"
          loadBalancerIP = "192.168.10.202"
        }
      }
      configs = {
        params = {
          "server.insecure" = true # Tunnel が TLS 終端するため
        }
        cm = {
          "admin.enabled" = "true"
          "application.resourceTrackingMethod" = "annotation"
        }
        rbac = {
          "policy.default" = "role:readonly"
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      applicationSet = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# ArgoCD App-of-Apps: Root Application (debug ブランチ向け)
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/Strategy-games/infra-repo"
        targetRevision = "debug"
        path           = "k8s-manifests/apps/root"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.argocd.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
