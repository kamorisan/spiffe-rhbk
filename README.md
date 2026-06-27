# RHBK + SPIFFE GitOps Environment

Red Hat build of Keycloak (RHBK) + OpenShift Zero Trust Workload Identity Manager (ZTWIM/SPIRE) + SPIFFE JWT-SVID認証環境のGitOps構成

## 概要

このリポジトリは、RHBK 26.6.4とSPIRE/SPIFFEを使用したJWT-SVID認証環境を、OpenShift GitOps (Argo CD)で再現可能に構築するための構成を提供します。

## アーキテクチャ

```
00-namespaces → 10-operators → 20-spire → 30-rhbk → 40-keycloak-config → 50-test-workloads
```

- **00-namespaces**: Namespace作成
- **10-operators**: ZTWIM / RHBK Operator導入
- **20-spire**: SPIRE Server/Agent, ClusterSPIFFEID作成
- **30-rhbk**: Keycloak + PostgreSQL作成
- **40-keycloak-config**: Keycloak Realm / SPIFFE IdP / Client設定
- **50-test-workloads**: JWT-SVID認証テスト用Pod

## デプロイ

### 前提条件

- OpenShift GitOps Operator インストール済み
- GitHubリポジトリURL: `https://github.com/kamori/spiffe-rhbk.git`

### App-of-Apps デプロイ

```bash
oc apply -f clusters/dev/applications/app-of-apps.yaml
```

### クリーンアップ

```bash
oc delete application rhbk-spiffe-dev -n openshift-gitops
```

Applicationを削除すると、finalizerによって関連リソースも自動削除されます。

## ディレクトリ構成

```
spiffe-rhbk/
├── clusters/dev/applications/    # Argo CD Application定義
├── platform/
│   ├── namespaces/               # Namespace定義
│   └── operators/                # Operator Subscription/OperatorGroup
├── spire/                        # SPIRE Server/Agent CR
├── rhbk/                         # Keycloak + PostgreSQL
├── keycloak-config/              # Keycloak設定Job
├── test-workloads/               # テスト用Pod
└── docs/                         # ドキュメント
```

## 検証

### SPIRE Server確認

```bash
oc get spireserver cluster -n spiffe-system
oc get pod -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spire-server
```

### Keycloak確認

```bash
oc get keycloak -n rhbk-demo
oc get pod -n rhbk-demo -l app=keycloak
```

### JWT-SVID取得テスト

```bash
POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client -o jsonpath='{.items[0].metadata.name}')
oc exec $POD -n rhbk-demo -- ls -la /spiffe-workload-api/spire-agent.sock
```

## Known Good Values

- RHBK: 26.6.4
- ZTWIM Operator: stable-v1
- SpireServer profile: `https_web`
- Trust Domain: `example.org`
- CA Key Type: `ec-p256`
- Keycloak Features: `spiffe`, `client-auth-federated`
- SPIFFE IdP alias: `spiffe`
- Bundle Endpoint: `https://spire-server.spiffe-system.svc.cluster.local:8443`
- Client Authenticator: `federated-jwt`
- client_assertion_type: `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe`

## テスト

### JWT-SVID認証テスト（推奨）

完全な認証テストガイド: **[JWT-SVID Authentication Guide](docs/JWT-SVID-AUTHENTICATION-GUIDE.md)**

**クイックスタート:**

```bash
# Step 1: spire-agentバイナリをインストール
./scripts/install-spire-agent-binary.sh

# Step 2: Keycloak Client設定を修正
./scripts/fix-keycloak-client-config.sh

# Step 3: Keycloak pod再起動
oc delete pod keycloak-0 -n rhbk-demo
oc wait --for=condition=Ready pod/keycloak-0 -n rhbk-demo --timeout=180s

# Step 4: 認証テスト実行
./scripts/test-jwt-svid-complete.sh
```

**成功時の結果:**
- HTTP 200 OK
- Access Token取得
- ログ保存: `logs/SUCCESS-GITOPS-YYYYMMDD-HHMMSS.json`

### その他のテストスクリプト

```bash
# 簡易テスト（参考用）
./scripts/test-jwt-svid-auth.sh
```

## ドキュメント

- **[JWT-SVID認証テストガイド](docs/JWT-SVID-AUTHENTICATION-GUIDE.md)** - 完全な認証テスト手順
- [GitOps環境構築ガイドライン](docs/rhbk_spiffe_gitops_environment_guidelines.md) - 環境構築の設計原則
- [手動テスト手順](docs/manual-test-procedure.md) - 手動テスト参考資料
