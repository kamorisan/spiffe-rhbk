# RHBK + SPIFFE GitOps Environment

Red Hat build of Keycloak (RHBK) + OpenShift Zero Trust Workload Identity Manager (ZTWIM/SPIRE) + SPIFFE JWT-SVID認証環境のGitOps構成

## 概要

このリポジトリは、RHBK 26.6.4とSPIRE/SPIFFEを使用したJWT-SVID認証環境を、OpenShift GitOps (Argo CD)で自動構築するための構成を提供します。

**主な特徴:**
- Keycloak Client設定の完全自動化
- デフォルトClusterSPIFFEIDテンプレート使用による一貫性
- Application finalizerによるリソースクリーンアップ
- 手動設定作業を最小化（4ステップ → 2ステップ）

## アーキテクチャ

### システム構成図

![Architecture Diagram](images/architecture.svg)

### デプロイメントフロー

```
00-namespaces → 10-operators → 20-spire → 30-rhbk → 40-keycloak-config → 50-test-workloads
```

- **00-namespaces**: Namespace作成（rhbk-demo）
- **10-operators**: ZTWIM / RHBK Operator導入
- **20-spire**: SPIRE Server/Agent（デフォルトClusterSPIFFEID使用）
- **30-rhbk**: Keycloak + PostgreSQL作成
- **40-keycloak-config**: Keycloak Realm / SPIFFE IdP / Client自動設定
- **50-test-workloads**: JWT-SVID認証テスト用Pod（Deployment）

### JWT-SVID認証フロー

#### 全体フロー（実測値版・推奨）

![Authentication Flow Diagram v2](images/auth-flow-v2.svg)

**v2の主な改善点:**
- 実際の成功ログから取得した値を反映
- SPIFFE ID: `spiffe://example.org/ns/rhbk-demo/sa/myclient` (ServiceAccount形式)
- JWT-SVID `iss`: SPIRE OIDC Discovery Provider URL（実測値）
- Keycloakの公開鍵取得先: SPIRE Server Bundle Endpoint（実構成）
- `client_id`は送信しない（実際の成功パターン）
- OIDC Discovery Providerの役割を明確化

<details>
<summary>旧バージョン（参考）</summary>

![Authentication Flow Diagram v1](images/auth-flow.svg)

</details>

#### Step 1: JWT-SVID取得フロー

![Step 1: JWT-SVID Fetch](images/auth-flow-step1.svg)

**JWT-SVID取得プロセス:**

1. **Application** → **SPIFFE CSI Driver**: Workload API Socketへアクセス
   - CSI DriverがUNIXソケット（`/spiffe-workload-api/spire-agent.sock`）をマウント
   
2. **Application** → **SPIRE Agent**: Workload API経由でJWT-SVIDをリクエスト
   - gRPC呼び出し（JWTSVIDsリクエスト）
   - `audience`: Keycloak realm issuer URL
     - 実測値: `https://keycloak-rhbk-demo.apps.cluster-hb456.../realms/spiffe`
   
3. **SPIRE Agent** → **SPIRE Server**: SPIFFE IDでJWT-SVIDを要求
   - ClusterSPIFFEIDテンプレートに基づきSPIFFE ID決定
   - 実測値: `spiffe://example.org/ns/rhbk-demo/sa/myclient`

4. **SPIRE Server**: 秘密鍵でJWT-SVIDに署名

5. **SPIRE Server** → **SPIRE Agent** → **Application**: JWT-SVID返却
   - **実測Claims**:
     - `sub`: `spiffe://example.org/ns/rhbk-demo/sa/myclient`
     - `iss`: `https://spire-oidc-discovery-provider-spiffe-system.apps.cluster-hb456...`
     - `aud`: `https://keycloak-rhbk-demo.apps.cluster-hb456.../realms/spiffe`
     - `exp`: unix timestamp

#### Step 2-4: Keycloak認証フロー

![Step 2-4: Keycloak Authentication](images/auth-flow-step2-4.svg)

**Keycloak認証プロセス:**

**Step 2: Token Request**
- **jwt-test-client** → **Keycloak**: Token EndpointにJWT-SVIDを送信
  - `grant_type=client_credentials`
  - `client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe`
  - `client_assertion=<JWT-SVID>`
  - **重要**: `client_id`は送信しない（JWT-SVIDの`sub`から解決される）

**Step 3: JWT-SVID検証**
- **3a**: JWT-SVIDから`sub`クレームを抽出
  - 実測値: `spiffe://example.org/ns/rhbk-demo/sa/myclient`
- **3b**: `jwt.credential.sub`でClientを検索（PostgreSQLから取得）
- **3c**: Clientの`jwt.credential.issuer`（alias: `spiffe`）からSPIFFE IdPを取得
- **3d**: SPIRE Server Bundle Endpointから公開鍵を取得
  - **実構成**: `https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443`
  - **注**: OIDC Discovery ProviderではなくSPIRE Serverから直接取得
- **3e**: JWT-SVIDの署名を公開鍵で検証
- **3f**: JWTクレーム（`sub`, `iss`, `aud`, `exp`）を検証
  - `iss`: SPIRE OIDC Discovery Provider URL（実測値）
  - `aud`: Keycloak realm issuer URL

**Step 4: Access Token発行**
- **4a**: 認証成功
- **4b**: Access Token生成（`client_id=myclient`は`sub`から解決）
- **4c**: HTTP 200 OK でAccess Token返却
  - `access_token`: Bearer Token
  - `expires_in`: 300秒
  - `token_type`: Bearer
  - `scope`: email profile

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

### デプロイ確認

全Applicationが`Synced`かつ`Healthy`であることを確認:

```bash
oc get application -n openshift-gitops
```

期待される出力:
```
NAME                 SYNC STATUS   HEALTH STATUS
00-namespaces        Synced        Healthy
10-operators         Synced        Healthy
20-spire             Synced        Healthy
30-rhbk              Synced        Healthy
40-keycloak-config   Synced        Healthy
50-test-workloads    Synced        Healthy
rhbk-spiffe-dev      Synced        Healthy
```

### SPIRE Server確認

```bash
oc get spireserver cluster -n zero-trust-workload-identity-manager
oc get pod -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spire-server
```

### Keycloak確認

```bash
oc get keycloak -n rhbk-demo
oc get pod -n rhbk-demo -l app=keycloak
```

### SPIFFE Workload API確認

```bash
POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client --field-selector=status.phase=Running -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind=="ReplicaSet")].metadata.name}' | awk '{print $1}')
oc exec $POD -n rhbk-demo -c client -- ls -la /spiffe-workload-api/spire-agent.sock
```

## 構成詳細

### バージョン

- **RHBK**: 26.6.4
- **ZTWIM Operator**: stable-v1
- **SPIRE Agent**: 1.13.3-dev

### SPIRE設定

- **SpireServer profile**: `https_web`
- **Trust Domain**: `example.org`
- **CA Key Type**: `ec-p256`
- **ClusterSPIFFEID**: デフォルトテンプレート使用
  ```
  spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}
  ```
- **SPIRE Server Endpoint**: `https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443`

### Keycloak設定

- **Realm**: `spiffe`
- **Features**: `spiffe`, `client-auth-federated`
- **SPIFFE IdP alias**: `spiffe`
- **Bundle Endpoint**: `https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443`
- **Client ID**: `myclient`
- **Client Authenticator**: `federated-jwt`
- **Client SPIFFE ID**: `spiffe://example.org/ns/rhbk-demo/sa/myclient` (自動設定)
- **client_assertion_type**: `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe`

## JWT-SVID認証テスト

完全な認証テストガイド: **[JWT-SVID Authentication Guide](docs/JWT-SVID-AUTHENTICATION-GUIDE.md)**

### クイックスタート

GitOps改善により、**手動作業を4ステップから1ステップに削減**しました。

```bash
# 認証テスト実行（spire-agentバイナリは既にカスタムイメージに組み込み済み）
./scripts/test-jwt-svid-complete.sh
```

**改善点:**
- カスタムコンテナイメージ（`quay.io/kamori/jwt-svid-test-client:v1.0`）にspire-agentバイナリを事前組み込み
- Pod再起動後も自動的に動作（手動インストール不要）
- RHEL9ベースで完全な互換性を確保

### 成功時の出力例

```
✅ SUCCESS: Keycloak authentication successful!

Response:
{
  "access_token": "eyJhbGci...",
  "expires_in": 300,
  "token_type": "Bearer",
  "scope": "email profile"
}

Summary:
  ✓ Access Token: eyJhbGci...
  ✓ Token Type: Bearer
  ✓ Expires In: 300s

  ✓ Result saved to: logs/SUCCESS-GITOPS-20260627-164556.json
```

### 自動化された設定

以下の設定が自動的に正しく構成されます：

- ✅ **Keycloak Client SPIFFE ID**: `spiffe://example.org/ns/rhbk-demo/sa/myclient`
- ✅ **Bundle Endpoint**: `https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443`
- ✅ **ClusterSPIFFEID**: デフォルトテンプレート使用

**従来必要だった手動作業（不要になりました）:**
- ~~Keycloak Client設定の修正~~
- ~~Keycloak Pod再起動~~

## ドキュメント

### テスト手順

- **[JWT-SVID認証テストガイド](docs/JWT-SVID-AUTHENTICATION-GUIDE.md)** - 完全な認証テスト手順

### 設計資料

- [GitOps環境構築ガイドライン](docs/design/rhbk_spiffe_gitops_environment_guidelines.md) - 環境構築の設計原則
- [GitOps改善履歴](docs/GITOPS-IMPROVEMENTS.md) - 自動化改善の詳細

### レポート

- [docs/report/](docs/report/) - 調査レポート・トラブルシューティング記録

## トラブルシューティング

### Application削除がスタックする場合

Operator管理リソース（SpireServer, SpireOIDCDiscoveryProvider等）に`foregroundDeletion` finalizerが付いている場合、子リソースの削除を待ちます。エラー状態のDeploymentがある場合は手動で削除します。

```bash
# スタック状況確認
oc get application -n openshift-gitops

# Operator管理リソース確認
oc get spireserver,spireoidcdiscoveryprovider -n zero-trust-workload-identity-manager

# 必要に応じて手動削除
oc delete deployment spire-spiffe-oidc-discovery-provider -n zero-trust-workload-identity-manager --force --grace-period=0
```

### Pod選択スクリプトエラー

JobとDeploymentが同じラベルを持つため、スクリプトがJob Podを誤選択する場合があります。スクリプトは`ownerReferences`でDeployment Podを選択するよう修正済みです。

```bash
# 正しいPod選択例
CLIENT_POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client --field-selector=status.phase=Running \
  -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind=="ReplicaSet")].metadata.name}' | awk '{print $1}')
```
