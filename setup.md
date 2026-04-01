# 検証環境 セットアップガイド

> **対象ブランチ: `debug`**
> 検証環境 (Nagasaki) の Proxmox + k8s + ArgoCD + Terraform を 0 から構築する手順。

## 前提条件

| 項目 | 内容 |
|---|---|
| pve01 | i7-8700 (6C/12T) / 94GB RAM / Proxmox VE 9.1.4 |
| pve02 | Intel Celeron / Proxmox VE 9.1.4 |
| pve03 | Ryzen 7 5700X (8C/16T) / 78GB RAM / Proxmox VE 9.1.4 |
| NAS | Synology DSM (VLAN11 側に接続済み) |
| 手元 PC | `kubectl` / `helm` / `terraform` / `git` インストール済み |

### 必要な外部サービス

- [ ] Cloudflare アカウント (`strategy-games.net` ゾーン管理権限)
- [ ] GitHub Personal Access Token (repo + org:write スコープ)
- [ ] Terraform Cloud アカウント (Organization: `strategy-games`)

---

## Step 1: Proxmox VM テンプレート作成

> `virt-customize` は使わない。
> Proxmox の **cloud-init snippet** で初回起動時に `qemu-guest-agent` をインストールする方式を使う。
> (Proxmox VE 9.x / Debian Trixie ホストで動作確認済み)
>
> **⚠️ pve01〜pve03 は同一 Proxmox クラスタのため VMID はクラスタ全体で一意にする必要がある。**
> テンプレートはローカルストレージに作成するため各ノードで個別に実行するが、VMID を変える。
> - pve01 テンプレート: VMID **9050**
> - pve03 テンプレート: VMID **9051**

### 1-1. pve01 で実行

```bash
# Debian 12 (Bookworm) genericcloud イメージ取得
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
  -O /var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2

# local ストレージに snippets コンテンツを有効化
pvesm set local --content vztmpl,iso,backup,snippets

# cloud-init vendor snippet 作成
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/k8s-node-init.yaml <<'EOF'
#cloud-config
packages:
  - qemu-guest-agent
  - curl
  - gnupg
  - apt-transport-https
  - ca-certificates
runcmd:
  - systemctl enable qemu-guest-agent --now
EOF

# VM テンプレート作成 (VMID: 9050)
qm create 9050 \
  --name debian-12-k8s-template \
  --memory 4096 --cores 2 \
  --net0 virtio,bridge=vmbr0,tag=10 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:0,import-from=/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2 \
  --ide2 local-lvm:cloudinit \
  --boot c --bootdisk scsi0 \
  --agent 1 \
  --serial0 socket --vga serial0

qm set 9050 --cicustom "vendor=local:snippets/k8s-node-init.yaml"
qm resize 9050 scsi0 32G
qm template 9050
```

### 1-2. pve03 で実行 (VMID は 9051 を使う)

```bash
# イメージ取得 (pve01 と同じ)
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
  -O /var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2

pvesm set local --content vztmpl,iso,backup,snippets

mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/k8s-node-init.yaml <<'EOF'
#cloud-config
packages:
  - qemu-guest-agent
  - curl
  - gnupg
  - apt-transport-https
  - ca-certificates
runcmd:
  - systemctl enable qemu-guest-agent --now
EOF

# VMID は 9051 (9050 は pve01 で使用済み)
qm create 9051 \
  --name debian-12-k8s-template \
  --memory 4096 --cores 2 \
  --net0 virtio,bridge=vmbr0,tag=10 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:0,import-from=/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2 \
  --ide2 local-lvm:cloudinit \
  --boot c --bootdisk scsi0 \
  --agent 1 \
  --serial0 socket --vga serial0

qm set 9051 --cicustom "vendor=local:snippets/k8s-node-init.yaml"
qm resize 9051 scsi0 32G
qm template 9051
```

---

## Step 2: k8s VM 展開

> Control Plane x1 (pve01) + Worker x2 (pve01/pve03) の 3 ノード構成
> pve02 (Celeron) は k8s クラスタ外で Pelican 等の軽量サービスに使用

### 2-1. pve01 (i7-8700): CP と Worker-1 を作成

```bash
# pve01 で実行
# --- Control Plane ---
qm clone 9050 201 --name k8s-debug-cp --full
qm set 201 \
  --memory 4096 --cores 2 \
  --ipconfig0 ip=192.168.10.141/24,gw=192.168.10.1 \
  --nameserver 192.168.10.1 \
  --sshkeys ~/.ssh/authorized_keys \
  --ciuser debian
qm resize 201 scsi0 40G
qm start 201

# --- Worker 1 (サブ Worker) ---
qm clone 9050 211 --name k8s-debug-wk-1 --full
qm set 211 \
  --memory 16384 --cores 4 \
  --ipconfig0 ip=192.168.10.151/24,gw=192.168.10.1 \
  --nameserver 192.168.10.1 \
  --sshkeys ~/.ssh/authorized_keys \
  --ciuser debian
qm resize 211 scsi0 60G
qm start 211
```

### 2-2. pve03 (Ryzen 7 5700X): Worker-2 を作成

```bash
# pve03 で実行
# MC サーバーが優先配置されるメイン Worker
# Ryzen 7 5700X は高シングルスレッド性能 → Paper に最適
# pve03 のテンプレートは VMID 9051
qm clone 9051 212 --name k8s-debug-wk-2 --full
qm set 212 \
  --memory 24576 --cores 6 \
  --ipconfig0 ip=192.168.10.152/24,gw=192.168.10.1 \
  --nameserver 192.168.10.1 \
  --sshkeys ~/.ssh/authorized_keys \
  --ciuser debian
qm resize 212 scsi0 60G
qm start 212
```

> **IP アドレス まとめ**
> | ノード | IP | Proxmox ホスト | 役割 |
> |---|---|---|---|
> | k8s-debug-cp | 192.168.10.141 | pve01 (i7-8700) | Control Plane |
> | k8s-debug-wk-1 | 192.168.10.151 | pve01 (i7-8700) | Worker サブ |
> | k8s-debug-wk-2 | 192.168.10.152 | pve03 (Ryzen 7 5700X) | Worker メイン (MC担当) |

---

## Step 3: 全ノード 共通セットアップ

**CP / wk-1 / wk-2 の全 VM で実行**

```bash
# SSH ログイン (例: CP)
ssh debian@192.168.10.141

# --- swap 無効化 ---
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# --- カーネルモジュール ---
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# --- sysctl ---
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# --- containerd インストール ---
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update
sudo apt-get install -y containerd.io

# containerd の config を SystemdCgroup=true に設定
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# --- kubeadm / kubelet / kubectl インストール (v1.31) ---
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl conntrack
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

---

## Step 4: k8s クラスタ初期化 (CP のみ)

```bash
# CP ノードで実行 (192.168.10.141)
ssh debian@192.168.10.141

# kubeadm init
# --skip-phases=addon/kube-proxy : Cilium が kube-proxy を置換するためスキップ
sudo kubeadm init \
  --apiserver-advertise-address=192.168.10.141 \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/16 \
  --skip-phases=addon/kube-proxy

# kubeconfig セットアップ
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# join コマンドを保存しておく
kubeadm token create --print-join-command > /tmp/join-command.sh
cat /tmp/join-command.sh
```

---

## Step 5: Worker ノード参加

```bash
# join コマンドを wk-1 / wk-2 にコピーして実行
JOIN_CMD=$(cat /tmp/join-command.sh)

for NODE in 192.168.10.151 192.168.10.152; do
  ssh debian@$NODE "sudo $JOIN_CMD"
done

# CP でノード確認 (NotReady は CNI 未インストールのため正常)
kubectl get nodes
```

---

## Step 6: Cilium CNI インストール

```bash
# Helm インストール (手元 PC または CP から実行)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Cilium Helm リポジトリ追加
helm repo add cilium https://helm.cilium.io
helm repo update

# Cilium インストール (kube-proxy 置換モード)
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.10.141 \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true

# ノードが Ready になるまで待機
kubectl wait --for=condition=Ready nodes --all --timeout=120s
kubectl get nodes
```

---

## Step 7: MetalLB インストール

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update

helm install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace

# IP プールの適用 (このリポジトリのマニフェスト)
kubectl apply -f k8s-manifests/cluster-wide-apps/metallb/ip-address-pool.yaml
kubectl apply -f k8s-manifests/cluster-wide-apps/metallb/l2-advertisement.yaml
```

---

## Step 8: Synology CSI セットアップ

### 8-1. NAS 側設定

Synology DSM にログインして以下を確認:

1. **コントロールパネル → 共有フォルダ** → `k8s-pv` フォルダを作成
2. **コントロールパネル → ファイルサービス → NFS** を有効化
3. NFS アクセスを k8s ノードの IP レンジ (`192.168.10.0/24`) に許可

### 8-2. k8s 側設定

```bash
# Synology CSI の認証情報 Secret を作成
# NAS の管理者ユーザー情報を入力
kubectl create namespace synology-csi

kubectl create secret generic synology-csi-client-info \
  --namespace synology-csi \
  --from-literal=client-info.yaml="$(cat <<EOF
clients:
  - host: 192.168.11.10       # NAS の IP (VLAN11 ストレージ側)
    port: 5000
    https: false
    username: <NAS管理者ユーザー>
    password: <NAS管理者パスワード>
EOF
)"

# CSI ドライバインストール
helm repo add synology-csi https://charts.synology.com
helm install synology-csi synology-csi/synology-csi \
  --namespace synology-csi \
  -f k8s-manifests/cluster-wide-apps/synology-csi/values.yaml

# StorageClass 確認
kubectl get storageclass
```

---

## Step 9: Terraform セットアップ

### 9-1. Terraform Cloud Workspace 設定

1. [app.terraform.io](https://app.terraform.io) → `strategy-games` Organization を開く
2. **New Workspace** → `infra-debug` を作成
3. **Variables** タブで以下を **Sensitive** として登録:

| Variable | 説明 |
|---|---|
| `cloudflare_api_token` | Cloudflare API Token (Zone:Edit, DNS:Edit, Access:Edit) |
| `cloudflare_zone_id` | Cloudflare ゾーン ID |
| `cloudflare_account_id` | Cloudflare アカウント ID |
| `github_token` | GitHub PAT (repo + org:write) |
| `k8s_client_certificate` | `base64 ~/.kube/config` の client-certificate-data |
| `k8s_client_key` | `base64 ~/.kube/config` の client-key-data |
| `k8s_cluster_ca_certificate` | `base64 ~/.kube/config` の certificate-authority-data |

```bash
# kubeconfig から各値を取得するコマンド例
kubectl config view --raw --minify \
  -o jsonpath='{.users[0].user.client-certificate-data}'
kubectl config view --raw --minify \
  -o jsonpath='{.users[0].user.client-key-data}'
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
```

### 9-2. GitHub Actions シークレット設定

リポジトリ Settings → Secrets → Actions:

| Secret | 値 |
|---|---|
| `TF_API_TOKEN` | Terraform Cloud の Team/User Token |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token |
| `CLOUDFLARE_ZONE_ID` | ゾーン ID |
| `CLOUDFLARE_ACCOUNT_ID` | アカウント ID |
| `GH_TOKEN` | GitHub PAT |
| `K8S_CLIENT_CERT` | client-certificate-data (base64) |
| `K8S_CLIENT_KEY` | client-key-data (base64) |
| `K8S_CA_CERT` | certificate-authority-data (base64) |
| `DISCORD_WEBHOOK_URL` | Discord Webhook URL |

### 9-3. Terraform 実行

```bash
cd terraform

# Terraform Cloud にログイン
terraform login

terraform init
terraform plan   # 内容を確認
terraform apply  # 適用 (ArgoCD インストール含む)
```

---

## Step 10: Secrets 作成 (手動)

ArgoCD 管理外のシークレットを手動で作成する。

```bash
# Minecraft RCON パスワード
kubectl create secret generic minecraft-debug-secrets \
  --namespace minecraft-debug \
  --from-literal=rcon-password='<任意の強力なパスワード>'

# MariaDB パスワード
kubectl create secret generic mariadb-secrets \
  --namespace minecraft-debug \
  --from-literal=root-password='<ルートパスワード>' \
  --from-literal=user-password='<sgames ユーザーパスワード>'
```

---

## Step 11: ArgoCD 動作確認

```bash
# ArgoCD CLI インストール
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# ログイン (Terraform が作成した LoadBalancer IP)
argocd login 192.168.10.202 --insecure --username admin \
  --password $(kubectl get secret argocd-initial-admin-secret \
    -n argocd -o jsonpath='{.data.password}' | base64 -d)

# パスワードを変更
argocd account update-password

# Root Application の sync 状態確認
argocd app list
argocd app sync root
```

---

## Step 12: 動作確認

```bash
# --- k8s リソース確認 ---
kubectl get all -n minecraft-debug

# StatefulSet が Running になるまで待機 (初回は Paper JAR ダウンロードで 3-5 分かかる)
kubectl wait --for=condition=Ready pod/minecraft-debug-0 \
  -n minecraft-debug --timeout=300s

# MC サーバーのログ確認
kubectl logs -f minecraft-debug-0 -n minecraft-debug

# --- RCON で動作確認 ---
# kubectl exec で RCON 接続
kubectl exec -it minecraft-debug-0 -n minecraft-debug -- \
  rcon-cli --host localhost --port 25575 \
  --password <RCONパスワード> list

# --- 外部接続確認 ---
# Velocity Proxy の LoadBalancer IP を確認
kubectl get svc velocity-proxy -n minecraft-debug

# MC クライアントから debug.strategy-games.net:25565 に接続して確認

# --- ArgoCD で全 app が Synced / Healthy か確認 ---
argocd app list
```

---

## 補足: よくある問題

### Pod が Pending のまま

```bash
# スケジューリングできない理由を確認
kubectl describe pod <pod名> -n minecraft-debug

# よくある原因:
# 1. PVC が Pending → NAS / Synology CSI の設定を確認
# 2. リソース不足 → kubectl top nodes で確認
```

### Synology CSI PVC が Pending

```bash
# CSI ドライバのログ確認
kubectl logs -n synology-csi -l app=synology-csi-controller

# NAS への疎通確認 (Worker ノードから)
curl http://192.168.11.10:5000
```

### ArgoCD が Sync しない

```bash
# Application の詳細確認
argocd app get mc-minecraft-debug

# 手動 sync
argocd app sync mc-minecraft-debug --force
```

### kubeadm join が失敗する

```bash
# Token 期限切れの場合は再発行
kubeadm token create --print-join-command
```

---

## 参考

- [07_k8s_optimization_plan.md](https://github.com/Strategy-games/infra/blob/main/07_k8s_optimization_plan.md) — 設計方針・技術スタック
- [itzg/minecraft-server](https://docker-minecraft-server.readthedocs.io/) — Paper 設定オプション
- [Cilium kubeproxy-free](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/) — Cilium kube-proxy 置換設定
- [seichi_infra](https://github.com/GiganticMinecraft/seichi_infra) — 参考実装
