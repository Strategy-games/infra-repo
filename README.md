# strategy-games infra-repo

> **現在のブランチ: `debug`** — 検証環境向け GitOps リポジトリ
>
> 本番環境は `main` ブランチで管理（未実装）

## 目次

- [ブランチ概要](#ブランチ概要)
- [インフラ全体図](#インフラ全体図)
- [検証環境 k8s クラスタ構成](#検証環境-k8s-クラスタ構成)
- [debug ブランチ デプロイ構成](#debug-ブランチ-デプロイ構成)
- [ネットワーク構成](#ネットワーク構成)
- [GitOps フロー](#gitops-フロー)
- [ディレクトリ構成](#ディレクトリ構成)
- [ブランチ戦略](#ブランチ戦略)

---

## ブランチ概要

| ブランチ | 環境 | 状態 | 用途 |
|---|---|---|---|
| `debug` | 検証 (Nagasaki) | **実装済み** | デバッグプレイヤーによる動作確認 |
| `main` | 本番 (sv01/02/03) | 未実装 | 本番サービス提供 |

---

## インフラ全体図

```mermaid
graph TB
    subgraph "Internet"
        Player((プレイヤー\nデバッグ))
        Admin((管理者))
    end

    subgraph "Cloudflare Edge"
        CF_Tunnel["Cloudflare Tunnel"]
        CF_Access["Cloudflare Access\n(Google OAuth)"]
    end

    subgraph "検証環境 - Nagasaki"
        subgraph "Proxmox Cluster (pve01/pve02)"
            subgraph "k8s debug クラスタ"
                VProxy["Velocity Proxy\nLoadBalancer: .231:25565"]
                MC["Paper MC Server\nminecraft-debug ns"]
                DB["MariaDB\nClusterIP"]
                BM["BlueMap\nLoadBalancer: .232:8100"]
                GL["game-logic-api\nClusterIP"]
                ArgoCD_S["ArgoCD\nLoadBalancer: .202"]
                Grafana_S["Grafana\nLoadBalancer: .203"]
            end
        end
        NAS["Synology NAS\n(PV ストレージ)"]
    end

    Player -->|"TCP 25565"| CF_Tunnel
    CF_Tunnel --> VProxy
    VProxy --> MC
    MC <--> DB
    MC <--> GL
    BM -.->|"world data (ReadOnly PVC)"| MC

    Admin -->|"HTTPS + OAuth"| CF_Access
    CF_Access --> CF_Tunnel
    CF_Tunnel --> ArgoCD_S
    CF_Tunnel --> Grafana_S

    NAS -->|"Synology CSI"| MC
    NAS -->|"Synology CSI"| DB
    NAS -->|"Synology CSI"| BM

    style MC fill:#2d5a27,stroke:#4CAF50,color:#fff
    style VProxy fill:#1565c0,stroke:#0d47a1,color:#fff
    style ArgoCD_S fill:#e65100,stroke:#ff6f00,color:#fff
    style CF_Tunnel fill:#f48120,stroke:#e67300,color:#fff
    style CF_Access fill:#f48120,stroke:#e67300,color:#fff
    style NAS fill:#6a1b9a,stroke:#7c4dff,color:#fff
```

---

## 検証環境 k8s クラスタ構成

```mermaid
graph TB
    subgraph "pve01 (i7-8700 / 94GB)"
        pve01_pve["Proxmox VE 9.1.4"]
        cp1["k8s-debug-cp\n2vCPU / 4GB\nControl Plane"]
        wk1["k8s-debug-wk-1\n4vCPU / 16GB\nWorker (サブ)"]
    end

    subgraph "pve02 (Celeron)"
        pve02_pve["Proxmox VE 9.1.4"]
        cel["軽量サービス / Pelican\n(k8s クラスタ外)"]
    end

    subgraph "pve03 (Ryzen 7 5700X / 78GB)"
        pve03_pve["Proxmox VE 9.1.4"]
        wk2["k8s-debug-wk-2\n6vCPU / 24GB\nWorker (メイン・MC担当)"]
    end

    subgraph "k8s debug クラスタ"
        CP["Control Plane x1\n(debug は HA 不要)"]
        WK["Worker Nodes x2"]
    end

    cp1 --> CP
    wk1 & wk2 --> WK

    style pve01_pve fill:#6a5a1a,stroke:#FFC107,color:#fff
    style pve02_pve fill:#37474f,stroke:#607d8b,color:#fff
    style pve03_pve fill:#2d5a27,stroke:#4CAF50,color:#fff
    style CP fill:#e65100,stroke:#ff6f00,color:#fff
    style WK fill:#1565c0,stroke:#0d47a1,color:#fff
    style cel fill:#37474f,stroke:#607d8b,color:#fff
```

---

## debug ブランチ デプロイ構成

### `minecraft-debug` namespace (mc-services AppProject)

```mermaid
graph LR
    subgraph "minecraft-debug namespace"
        subgraph "Velocity Proxy"
            VP_Deploy["Deployment\nitzg/bungeecord\nTYPE=VELOCITY"]
            VP_SVC["Service (LoadBalancer)\n192.168.10.231:25565"]
        end

        subgraph "Paper MC Server"
            MC_SS["StatefulSet\nitzg/minecraft-server:java21\nTYPE=PAPER"]
            MC_SVC_LB["Service (LoadBalancer)\n25565 / 25575(RCON)"]
            MC_SVC_HL["Service (Headless)\nDNS: minecraft-debug-headless"]
            MC_PVC_DATA["PVC: data (30Gi)\nSynology CSI"]
            MC_PVC_PLG["PVC: plugins (5Gi)\nカスタム JAR 格納"]
        end

        subgraph "MariaDB 11"
            DB_SS["StatefulSet\nmariadb:11"]
            DB_SVC["Service (ClusterIP)\n:3306"]
            DB_PVC["PVC: data (20Gi)\nSynology CSI"]
        end

        subgraph "BlueMap"
            BM_Deploy["Deployment\nghcr.io/bluemap-minecraft/bluemap"]
            BM_SVC["Service (LoadBalancer)\n192.168.10.232:8100"]
            BM_PVC["PVC: render-output (50Gi)"]
        end

        subgraph "game-logic-api"
            GL_Deploy["Deployment\n(eclipse-temurin:21-jre\n→ カスタム JAR)"]
            GL_SVC["Service (ClusterIP)\n:8080"]
            GL_PVC["PVC: app-jar (1Gi)"]
        end
    end

    VP_SVC --> VP_Deploy
    VP_Deploy -->|"headless DNS"| MC_SVC_HL
    MC_SS --- MC_PVC_DATA & MC_PVC_PLG
    DB_SS --- DB_PVC
    BM_Deploy -->|"ReadOnly PVC"| MC_PVC_DATA
    BM_Deploy --- BM_PVC
    GL_Deploy -->|"RCON"| MC_SS
    GL_Deploy -->|"JDBC"| DB_SVC
    GL_Deploy --- GL_PVC

    style MC_SS fill:#2d5a27,stroke:#4CAF50,color:#fff
    style VP_Deploy fill:#1565c0,stroke:#0d47a1,color:#fff
    style DB_SS fill:#6a1b9a,stroke:#7c4dff,color:#fff
```

### cluster-wide-apps (ArgoCD 自動管理)

| コンポーネント | Helm Chart | 用途 |
|---|---|---|
| `cilium` | helm.cilium.io | CNI (kube-proxy 置換) |
| `metallb` | metallb.github.io | LoadBalancer IP 割り当て |
| `cert-manager` | charts.jetstack.io | TLS 証明書自動発行 |
| `monitoring/prometheus` | prometheus-community | メトリクス収集 |
| `monitoring/grafana` | grafana.github.io | ダッシュボード |
| `synology-csi` | github.com/SynologyOpenSource/synology-csi | NAS 永続ボリューム |
| `velero` | vmware-tanzu | k8s リソースバックアップ |

---

## ネットワーク構成

```mermaid
graph TB
    subgraph "MetalLB IP プール"
        P1["default-pool\n192.168.10.200 - .230\n汎用サービス"]
        P2["mc-debug-pool\n192.168.10.231 - .240\nMC debug 専用"]
        P3["admin-pool\n192.168.10.241 - .249\nArgoCD / Grafana"]
    end

    subgraph "割り当て済み IP"
        IP231["192.168.10.231\nVelocity Proxy :25565"]
        IP232["192.168.10.232\nBlueMap :8100"]
        IP202["192.168.10.202\nArgoCD"]
        IP203["192.168.10.203\nGrafana"]
    end

    subgraph "k8s 内部ネットワーク"
        PodCIDR["Pod CIDR\n10.244.0.0/16\n(Cilium 管理)"]
        SvcCIDR["Service CIDR\n10.96.0.0/16"]
    end

    P2 --> IP231 & IP232
    P3 --> IP202 & IP203

    style P2 fill:#2d5a27,stroke:#4CAF50,color:#fff
    style P3 fill:#e65100,stroke:#ff6f00,color:#fff
```

---

## GitOps フロー

```mermaid
sequenceDiagram
    participant Dev as 開発者
    participant GH as GitHub (debug ブランチ)
    participant GHA as GitHub Actions
    participant TF as Terraform Cloud
    participant Argo as ArgoCD
    participant K8s as k8s cluster

    Dev->>GH: PR 作成 (terraform/ 変更)
    GH->>GHA: terraform-plan.yml 起動
    GHA->>TF: terraform plan
    TF-->>GHA: Plan 結果
    GHA-->>GH: PR にコメント

    Dev->>GH: debug ブランチへマージ
    GH->>GHA: terraform-apply.yml 起動
    GHA->>TF: terraform apply
    TF->>K8s: Namespace / ArgoCD インストール

    Note over Argo,K8s: ArgoCD が debug ブランチを継続監視

    Dev->>GH: k8s-manifests/ 変更を push
    GH-->>Argo: Webhook 通知
    Argo->>K8s: 自動 sync (prune + selfHeal)
    K8s-->>Argo: sync 完了
```

---

## ディレクトリ構成

```
infra-repo/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml    # PR 時に plan 結果をコメント
│       └── terraform-apply.yml   # debug push 時に apply
│
├── terraform/                    # IaC (Cloudflare / GitHub / k8s Bootstrap)
│   ├── versions.tf               # Provider バージョン固定
│   ├── main.tf                   # Provider 設定
│   ├── variables.tf              # 変数定義 (シークレットは Terraform Cloud)
│   ├── outputs.tf
│   ├── cloudflare_dns.tf         # DNS レコード (debug.strategy-games.net 等)
│   ├── cloudflare_tunnel.tf      # Cloudflare Tunnel ingress ルール
│   ├── cloudflare_access.tf      # Zero Trust Access (Google OAuth)
│   ├── cloudflare_firewall.tf    # WAF ルール
│   ├── github_org.tf             # チーム管理 (infra/mc-ops/moderators/debug-players)
│   ├── github_repos.tf           # リポジトリ設定 / ブランチ保護
│   ├── kubernetes_namespaces.tf  # Namespace 作成
│   ├── kubernetes_secrets.tf     # Secret bootstrap
│   └── helm_argocd.tf            # ArgoCD Helm インストール + Root Application
│
└── k8s-manifests/                # ArgoCD GitOps マニフェスト
    ├── apps/root/
    │   ├── projects.yaml         # AppProject 定義 x3
    │   └── apps.yaml             # ApplicationSet 定義 x3
    │
    ├── cluster-wide-apps/        # インフラコンポーネント (自動検出)
    │   ├── cilium/values.yaml
    │   ├── metallb/              # ip-address-pool / l2-advertisement
    │   ├── monitoring/           # prometheus / grafana
    │   ├── cert-manager/values.yaml
    │   ├── synology-csi/values.yaml
    │   └── velero/values.yaml
    │
    ├── mc-services/              # MC 関連サービス → minecraft-debug ns
    │   ├── minecraft-debug/      # Paper StatefulSet (メイン)
    │   ├── velocity-proxy/       # Velocity プロキシ
    │   ├── mariadb/              # MariaDB 11
    │   ├── bluemap/              # 3D マップレンダリング
    │   └── game-logic/           # ゲームロジック API
    │
    └── web-services/             # Web サービス (values のみ / 移行予定)
        ├── mattermost/values.yaml
        └── pelican/values.yaml
```

---

## ブランチ戦略

```mermaid
gitGraph
   commit id: "Initial commit" tag: "main"
   branch debug
   checkout debug
   commit id: "feat: debug infra (k8s + terraform)"
   commit id: "現在地"
```

| ブランチ | Terraform Workspace | ArgoCD targetRevision | k8s Namespace |
|---|---|---|---|
| `debug` | `infra-debug` | `debug` | `minecraft-debug` |
| `main` | `infra-prod` (未作成) | `main` | `minecraft` |

---

## デプロイ状況 (debug ブランチ)

> 最終更新: 2026-04-02 — `argocd app list` の実測値に基づく

### インフラ基盤

| コンポーネント | ArgoCD 状態 | 備考 |
|---|---|---|
| Proxmox VM (CP/WK) | — | cloud-init snippet 方式で稼働中 |
| Cilium CNI | ✅ Synced / Healthy | kube-proxy 置換モード |
| MetalLB | ✅ Synced / Healthy | L2 モード |
| cert-manager | ✅ Synced / Healthy | |
| Synology CSI | ✅ Synced / Healthy | ArgoCD (GitOps) 管理 |
| Monitoring (Prometheus/Grafana) | ✅ Synced / Healthy | |
| Velero | ✅ Synced / Healthy | |
| ArgoCD | ✅ Terraform Helm インストール済み | |
| Cloudflare DNS/Tunnel | ✅ 作成済み | Terraform apply 完了 |
| GitHub チーム/ブランチ保護 | ✅ 設定済み | public リポジトリ必須 |
| Cloudflare WAF Ruleset | ⏸️ スキップ | 有料プラン必要 |

### MC サービス (minecraft-debug namespace)

| コンポーネント | ArgoCD 状態 | 備考 |
|---|---|---|
| mc-minecraft-debug | ✅ Synced / ⏳ Progressing | Paper 起動中 (初回 JAR DL + ワールド生成) |
| mc-mariadb | ✅ Synced / ⏳ Progressing | DB 初期化中 |
| mc-velocity-proxy | ✅ Synced / ⚠️ Degraded | MC 起動完了で自動回復予定 |
| mc-bluemap | ✅ Synced / ⚠️ Degraded | RWO PVC 別ノード問題 → nodeAffinity 要修正 |
| mc-game-logic | ✅ Synced / ⚠️ Degraded | JAR 未配置 / カスタムイメージ未ビルド |

### Web サービス

| コンポーネント | ArgoCD 状態 | 備考 |
|---|---|---|
| web-mattermost | ✅ Synced / Healthy | |
| web-pelican | ✅ Synced / Healthy | |

### 既知の制約・未解決問題

- **Cloudflare WAF Ruleset**: `http_request_firewall_custom` フェーズは Pro プラン以上が必要。`cloudflare_firewall.tf` はコメントアウト済み。
- **GitHub ブランチ保護**: Free プランでは public リポジトリのみ有効。`visibility = "public"` に設定済み。
- **Terraform Cloud 実行モード**: プライベートクラスタのため **Local モード** で実行。
- **mc-bluemap Degraded**: `minecraft-debug-data-minecraft-debug-0` は `ReadWriteOnce` PVC のため、MC Pod と異なるノードにスケジュールされると mount 失敗。`k8s-manifests/mc-services/bluemap/deployment.yaml` に MC と同じ `k8s-debug-wk-2` への `nodeAffinity` 追加が必要。
- **mc-game-logic Degraded**: placeholder image (`eclipse-temurin:21-jre-bookworm`) を使用中。CI/CD で `ghcr.io/strategy-games/game-logic-api:debug` をビルド・push するか、PVC (`game-logic-api-jar`) に JAR を手動配置するまで Degraded のまま。
