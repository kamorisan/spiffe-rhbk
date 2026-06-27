# JWT-SVID Authentication Testing Guide

**GitOps環境でのSPIFFE JWT-SVID認証テスト完全ガイド**

## 概要

このガイドでは、GitOps (Argo CD) でデプロイされたRHBK + SPIRE環境で、JWT-SVID認証をテストする手順を説明します。

**GitOps改善により、手動作業を4ステップから2ステップに削減しました。**

### 改善内容

- ✅ **Keycloak Client設定の自動化**: configure-keycloak-v3 Jobで正しいSPIFFE IDを自動設定
- ✅ **デフォルトClusterSPIFFEID使用**: カスタムClusterSPIFFEIDを削除し、Operator管理のデフォルトテンプレートを使用
- ✅ **Bundle Endpoint修正**: 正しいnamespace (zero-trust-workload-identity-manager) を使用
- ✅ **Pod再起動不要**: 設定が最初から正しいため、Keycloak Pod再起動が不要

## 前提条件

✅ すべてのGitOps Applicationが`Synced`かつ`Healthy`であること

```bash
oc get application -n openshift-gitops
```

期待される状態:
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

**重要:** `40-keycloak-config`が`Healthy`であることを確認してください。configure-keycloak-v3 Jobが完了していることが必要です。

```bash
# Keycloak config Job確認
oc get job configure-keycloak-v3 -n rhbk-demo
# STATUS: Complete であること
```

## テスト手順（2ステップ）

### Step 1: spire-agentバイナリのインストール

jwt-test-client podにspire-agentバイナリをインストールします。

```bash
cd /path/to/spiffe-rhbk
./scripts/install-spire-agent-binary.sh
```

**実行内容:**
- SPIRE Agent podから実行中の`spire-agent`バイナリを抽出
- jwt-test-client podの`/tmp/spire-agent`にコピー
- 実行権限を付与

**期待される出力:**
```
=== Install spire-agent Binary into jwt-test-client Pod ===

1. Finding SPIRE Agent Pod...
✓ SPIRE Agent Pod: spire-agent-xxxxx

2. Finding jwt-test-client Pod...
✓ jwt-test-client Pod: jwt-test-client-xxxxxx-xxxxx

3. Checking if spire-agent binary already exists...

4. Extracting spire-agent binary from SPIRE Agent pod...
✓ Extracted from /spire-agent
✓ Extracted binary size: 59768832 bytes

5. Copying spire-agent binary to jwt-test-client pod...

6. Setting executable permission...

7. Verifying installation...
✓ spire-agent installed successfully
  Version: 1.13.3-dev-unk

=== Installation Complete ===
```

---

### Step 2: 認証テスト実行

完全なエンドツーエンド認証テストを実行します。

```bash
./scripts/test-jwt-svid-complete.sh
```

**テストフロー:**

1. **環境検出**
   - OpenShift Apps Domainを取得
   - Keycloak ホスト名とToken Endpointを構築

2. **jwt-test-client Pod選択**
   - Running状態のpodを検索

3. **spire-agentバイナリ確認**
   - `/tmp/spire-agent`または`/usr/local/bin/spire-agent`の存在確認

4. **JWT-SVID取得**
   ```bash
   /tmp/spire-agent api fetch jwt \
     -audience "https://keycloak-rhbk-demo.apps.CLUSTER_DOMAIN/realms/spiffe" \
     -socketPath /spiffe-workload-api/spire-agent.sock
   ```

5. **JWT-SVIDペイロード検証**
   - `sub`: SPIFFE ID
   - `iss`: SPIRE OIDC Discovery Provider
   - `aud`: Keycloak realm issuer

6. **Keycloak認証**
   ```bash
   curl -k -X POST "$TOKEN_ENDPOINT" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     --data-urlencode "grant_type=client_credentials" \
     --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
     --data-urlencode "client_assertion=$JWT_SVID"
   ```

**成功時の出力:**
```
=== JWT-SVID Authentication Complete Test ===

1. Detecting environment...
  Apps Domain: apps.cluster-xxxxx.xxxxx.sandboxXXXX.opentlc.com
  Keycloak Hostname: keycloak-rhbk-demo.apps.cluster-xxxxx...
  Audience: https://keycloak-rhbk-demo.apps.cluster-xxxxx.../realms/spiffe

2. Finding jwt-test-client Pod...
✓ jwt-test-client Pod: jwt-test-client-xxxxxx-xxxxx

3. Checking spire-agent binary...
✓ spire-agent binary found at /tmp/spire-agent

4. Fetching JWT-SVID...
  Audience: https://keycloak-rhbk-demo.apps.cluster-xxxxx.../realms/spiffe
✓ JWT-SVID fetched successfully
  Length: 577 characters

  JWT-SVID Claims:
    sub: spiffe://example.org/ns/rhbk-demo/sa/myclient
    iss: https://spire-oidc-discovery-provider-spiffe-system.apps.cluster-xxxxx...
    aud: https://keycloak-rhbk-demo.apps.cluster-xxxxx.../realms/spiffe

5. Authenticating with Keycloak...
  Token Endpoint: https://keycloak-rhbk-demo.apps.cluster-xxxxx.../realms/spiffe/protocol/openid-connect/token
  Client ID: myclient

  HTTP Status: 200

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

  ✓ Result saved to: logs/SUCCESS-GITOPS-20260627-155445.json

=== Test Summary ===
✓ Environment Detection: Success
✓ Pod Selection: Success
✓ spire-agent Binary: Available
✓ JWT-SVID Fetch: Success
✓ Keycloak Authentication: Success

All tests passed!
```

---

## トラブルシューティング

### 問題1: JWT-SVID取得失敗

**症状:**
```
✗ Failed to fetch JWT-SVID
rpc error: code = Unavailable desc = could not fetch JWT-SVID
```

**原因:**
- SPIFFE Workload APIソケットが存在しない
- ClusterSPIFFEIDが適用されていない

**解決方法:**
```bash
# SPIFFE CSI Driverの確認
oc get spiffecsidriver -n zero-trust-workload-identity-manager

# ClusterSPIFFEIDの確認
oc get clusterspiffeid

# jwt-test-client podのvolume確認
oc get pod -n rhbk-demo -l app=jwt-test-client -o yaml | grep -A 10 volumes
```

---

### 問題2: Keycloak認証失敗（401 invalid_client_credentials）

**症状:**
```
HTTP Status: 401
{
  "error": "invalid_client",
  "error_description": "Invalid client or Invalid client credentials"
}
```

**原因（GitOps改善後は発生しないはず）:**
- configure-keycloak-v3 Jobが正常完了していない
- Keycloak Client設定が正しくない

**解決方法:**
```bash
# Keycloak config Job確認
oc get job configure-keycloak-v3 -n rhbk-demo
oc logs job/configure-keycloak-v3 -n rhbk-demo

# 必要に応じて再実行（Job削除してArgo CDが再作成）
oc delete job configure-keycloak-v3 -n rhbk-demo
# Argo CDが自動的に再作成します

# または手動修正スクリプトを使用（非推奨）
./scripts/fix-keycloak-client-config.sh
```

---

### 問題3: spire-agentバイナリが見つからない

**症状:**
```
✗ spire-agent binary not found
```

**解決方法:**
```bash
# Step 1を実行
./scripts/install-spire-agent-binary.sh
```

**注意:** jwt-test-client podが再作成されると、バイナリは失われます。その場合はStep 1を再実行してください。

---

## 重要な設定値

### SPIFFE ID

**デフォルトClusterSPIFFEIDテンプレート:**
```yaml
spiffeIDTemplate: spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}
```

**jwt-test-clientの場合:**
- Namespace: `rhbk-demo`
- ServiceAccount: `myclient`
- 結果: `spiffe://example.org/ns/rhbk-demo/sa/myclient`

### Keycloak Client設定

```json
{
  "clientId": "myclient",
  "clientAuthenticatorType": "federated-jwt",
  "attributes": {
    "jwt.credential.issuer": "spiffe",
    "jwt.credential.sub": "spiffe://example.org/ns/rhbk-demo/sa/myclient"
  }
}
```

**重要:**
- `jwt.credential.issuer`: SPIFFE Identity Provider **alias** (URLではない)
- `jwt.credential.sub`: 実際に発行されるSPIFFE ID (ClusterSPIFFEIDテンプレートの結果)

### SPIFFE Identity Provider設定

```json
{
  "alias": "spiffe",
  "providerId": "spiffe",
  "config": {
    "bundleEndpoint": "https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443",
    "trustDomain": "spiffe://example.org"
  }
}
```

**重要:**
- `bundleEndpoint`: Operator管理のSPIRE Serverは`zero-trust-workload-identity-manager` namespaceに存在
- `spiffe-system`ではないので注意

---

## OAuth 2.0フロー詳細

### Token Request（client_id なしパターン）

```http
POST /realms/spiffe/protocol/openid-connect/token HTTP/1.1
Host: keycloak-rhbk-demo.apps.cluster-xxxxx.opentlc.com
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe
&client_assertion=eyJhbGci...
```

**重要:** `client_id`パラメータは**含めない**

Keycloakは以下のフローで認証します:

1. `client_assertion` (JWT-SVID) を受信
2. JWT-SVIDの`sub`クレームを読み取る: `spiffe://example.org/ns/rhbk-demo/sa/myclient`
3. この`sub`をclient IDとして使用し、該当するClientを検索
4. Clientの`jwt.credential.sub`と一致するか確認
5. Clientの`jwt.credential.issuer` (="spiffe") からSPIFFE IdPを取得
6. SPIFFE IdPの`bundleEndpoint`からJWKSを取得
7. JWT-SVIDの署名を検証
8. 認証成功 → Access Token発行

---

## 成功ログ

認証が成功すると、結果は以下に保存されます:

```
logs/SUCCESS-GITOPS-YYYYMMDD-HHMMSS.json
```

**例:** `logs/SUCCESS-GITOPS-20260627-155445.json`

ログには以下が含まれます:
- `access_token`: Keycloakが発行したBearer Token
- `expires_in`: トークン有効期限（秒）
- `token_type`: "Bearer"
- `scope`: "email profile"

---

## 参考情報

### 関連ドキュメント

- [GitOps環境構築ガイドライン](design/rhbk_spiffe_gitops_environment_guidelines.md)
- [GitOps改善履歴](GITOPS-IMPROVEMENTS.md)
- レポート: [docs/report/](report/)

### Keycloak Admin Console

```
URL: https://keycloak-rhbk-demo.apps.CLUSTER_DOMAIN
Username: temp-admin
Password: (oc get secret keycloak-initial-admin -n rhbk-demo -o jsonpath='{.data.password}' | base64 -d)
```

**確認ポイント:**
- Realm: `spiffe`
- Identity Providers: `spiffe` (providerId: spiffe)
- Clients: `myclient` (Client Authenticator Type: federated-jwt)

### Argo CD UI

```
URL: https://openshift-gitops-server-openshift-gitops.apps.CLUSTER_DOMAIN
```

すべてのApplicationが`Synced`かつ`Healthy`であることを確認してください。

---

**作成日:** 2026-06-27  
**環境:** OpenShift 4.x + Zero Trust Workload Identity Manager Operator + RHBK 26.6.4  
**GitOpsリポジトリ:** https://github.com/kamorisan/spiffe-rhbk
