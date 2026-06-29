# JWT-SVID Authentication Manual Test Procedure

## 前提条件

- OpenShiftクラスタにログイン済み
- 全GitOps Applicationがデプロイ済み (Synced & Healthy)
- SPIRE Server/Agent稼働中
- Keycloak稼働中、spiffe realm設定済み

## テスト手順

### 方法1: SPIRE Server Podから直接テスト（推奨）

SPIRE Server Podにはspire-server CLIツールがあり、JWT-SVIDの生成とテストができます。

```bash
# 1. SPIRE Server Podを取得
SPIRE_SERVER_POD=$(oc get pod -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spire-server -o jsonpath='{.items[0].metadata.name}')

# 2. 環境変数設定
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KEYCLOAK_HOSTNAME="keycloak-rhbk-demo.${APPS_DOMAIN}"
TOKEN_ENDPOINT="https://${KEYCLOAK_HOSTNAME}/realms/spiffe/protocol/openid-connect/token"
SPIFFE_ID="spiffe://example.org/myclient"

# 3. Registration Entryが存在するか確認
oc exec $SPIRE_SERVER_POD -n zero-trust-workload-identity-manager -c spire-server -- \
  /opt/spire/bin/spire-server entry show -spiffeID $SPIFFE_ID

# 4. JWT-SVID生成
# Note: spire-server token generateはサーバー側でのトークン生成（開発/テスト用）
# 実際の運用ではWorkload APIからフェッチします
```

### 方法2: Test Client Podからテスト

Test Client PodにはSPIFFE Workload APIソケットがマウントされています。

```bash
# 1. Test Client Podを取得
TEST_POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client -o jsonpath='{.items[0].metadata.name}')

# 2. SPIFFE Workload APIソケット確認
oc exec $TEST_POD -n rhbk-demo -- ls -la /spiffe-workload-api/spire-agent.sock

# 3. 環境設定
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KEYCLOAK_HOSTNAME="keycloak-rhbk-demo.${APPS_DOMAIN}"
TOKEN_ENDPOINT="https://${KEYCLOAK_HOSTNAME}/realms/spiffe/protocol/openid-connect/token"
```

### 方法3: SPIRE Agent Podからspire-agent CLIを使用（最も本番に近い）

```bash
# 1. SPIRE Agent Podを取得
SPIRE_AGENT_POD=$(oc get pod -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spire-agent -o jsonpath='{.items[0].metadata.name}')

# 2. Pod情報確認
oc get pod $SPIRE_AGENT_POD -n zero-trust-workload-identity-manager -o yaml | grep -A 5 "image:"

# 3. spire-agentバイナリの場所を確認
oc exec $SPIRE_AGENT_POD -n zero-trust-workload-identity-manager -c spire-agent -- find / -name "spire-agent" -type f 2>/dev/null
```

## 手動認証テスト（JWT-SVIDを取得後）

JWT-SVIDを取得したら、以下のコマンドでKeycloak Token Endpointにアクセスします。

```bash
# 環境変数設定
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
TOKEN_ENDPOINT="https://keycloak-rhbk-demo.${APPS_DOMAIN}/realms/spiffe/protocol/openid-connect/token"
CLIENT_ID="myclient"
JWT_SVID="<YOUR_JWT_SVID_HERE>"

# Keycloak認証
curl -k -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
  --data-urlencode "client_assertion=$JWT_SVID"
```

## 期待される結果

### 成功時のレスポンス

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI...",
  "expires_in": 300,
  "refresh_expires_in": 0,
  "token_type": "Bearer",
  "not-before-policy": 0
}
```

### 失敗時のレスポンス例

```json
{
  "error": "invalid_client",
  "error_description": "Client authentication failed"
}
```

## トラブルシューティング

### JWT-SVIDが取得できない

1. SPIFFE Workload APIソケットの確認
2. ClusterSPIFFEIDの確認: `oc get clusterspiffeid jwt-test-client`
3. SPIRE Agent Podのログ確認

### Keycloak認証失敗

1. Keycloak SPIFFE IdPの設定確認
   - Bundle Endpoint: `https://spire-server.spiffe-system.svc.cluster.local:8443`
   - Trust Domain: `spiffe://example.org`

2. Clientの設定確認
   - Client Authenticator: `federated-jwt`
   - jwt.credential.issuer: `spiffe`
   - jwt.credential.sub: `spiffe://example.org/myclient`

3. Keycloak Podのログ確認

## 簡易テストスクリプト

リポジトリに含まれるテストスクリプトを使用:

```bash
cd /path/to/spiffe-rhbk
chmod +x scripts/test-jwt-svid-auth.sh
./scripts/test-jwt-svid-auth.sh
```

## 参考情報

- Keycloak Admin Console: https://keycloak-rhbk-demo.apps.CLUSTER_DOMAIN
- ArgoCD UI: https://openshift-gitops-server-openshift-gitops.apps.CLUSTER_DOMAIN
- GitOps Repository: https://github.com/kamorisan/spiffe-rhbk
