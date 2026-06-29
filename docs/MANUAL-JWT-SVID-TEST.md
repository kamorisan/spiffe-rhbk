# JWT-SVID認証テスト - 手動実行手順

このドキュメントでは、`test-jwt-svid-complete.sh`スクリプトが自動化している各ステップを、手動で実行する方法を説明します。

## 前提条件

- OpenShiftクラスターへのログイン済み（`oc login`）
- すべてのGitOps Applicationが`Synced`かつ`Healthy`

## Step 1: 環境情報の取得

### OpenShift Apps Domainの取得

```bash
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Apps Domain: $APPS_DOMAIN"
```

**出力例:**
```
Apps Domain: apps.cluster-hb456.hb456.sandbox3244.opentlc.com
```

### Keycloak Hostname・Audience・Token Endpointの構築

```bash
KEYCLOAK_HOSTNAME="keycloak-rhbk-demo.${APPS_DOMAIN}"
REALM="spiffe"
AUDIENCE="https://${KEYCLOAK_HOSTNAME}/realms/${REALM}"
TOKEN_ENDPOINT="${AUDIENCE}/protocol/openid-connect/token"

echo "Keycloak Hostname: $KEYCLOAK_HOSTNAME"
echo "Audience: $AUDIENCE"
echo "Token Endpoint: $TOKEN_ENDPOINT"
```

**出力例:**
```
Keycloak Hostname: keycloak-rhbk-demo.apps.cluster-hb456.hb456.sandbox3244.opentlc.com
Audience: https://keycloak-rhbk-demo.apps.cluster-hb456.hb456.sandbox3244.opentlc.com/realms/spiffe
Token Endpoint: https://keycloak-rhbk-demo.apps.cluster-hb456.hb456.sandbox3244.opentlc.com/realms/spiffe/protocol/openid-connect/token
```

---

## Step 2: jwt-test-client Podの検索

### Running状態のPodを取得（Deployment管理のみ）

```bash
CLIENT_POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind=="ReplicaSet")].metadata.name}' \
  | awk '{print $1}')

echo "jwt-test-client Pod: $CLIENT_POD"
```

**出力例:**
```
jwt-test-client Pod: jwt-test-client-56b88b584b-r6zlq
```

### Podが使用しているイメージの確認

```bash
oc get pod $CLIENT_POD -n rhbk-demo -o jsonpath='{.spec.containers[0].image}'
echo ""
```

**出力例:**
```
quay.io/kamori/jwt-svid-test-client:v1.0
```

---

## Step 3: spire-agentバイナリの確認

### バイナリの存在確認

```bash
oc exec $CLIENT_POD -n rhbk-demo -c client -- test -x /usr/local/bin/spire-agent && echo "✓ Binary exists" || echo "✗ Binary not found"
```

### バイナリバージョンの確認

```bash
oc exec $CLIENT_POD -n rhbk-demo -c client -- /usr/local/bin/spire-agent --version
```

**出力例:**
```
1.13.3-dev-unk
```

---

## Step 4: JWT-SVID の取得

### Workload API経由でJWT-SVIDを取得

```bash
JWT_OUTPUT=$(oc exec $CLIENT_POD -n rhbk-demo -c client -- \
  /usr/local/bin/spire-agent api fetch jwt \
  -audience "$AUDIENCE" \
  -socketPath /spiffe-workload-api/spire-agent.sock 2>&1)

echo "$JWT_OUTPUT"
```

**出力例:**
```
spiffe://example.org/ns/rhbk-demo/sa/myclient
eyJhbGciOiJFUzI1NiIsImtpZCI6IkdUVG...（長いJWT文字列）
```

### JWT-SVIDの抽出（2行目）

```bash
JWT_SVID=$(echo "$JWT_OUTPUT" | sed -n '2p' | sed 's/^[[:space:]]*//')
echo "JWT-SVID: ${JWT_SVID:0:80}..."
echo "Length: ${#JWT_SVID} characters"
```

**出力例:**
```
JWT-SVID: eyJhbGciOiJFUzI1NiIsImtpZCI6IkdUVG9ZckVGSGhiWDU3bTlmb2xLd3lQQ0tscUxNV...
Length: 577 characters
```

### JWT-SVID Claimsのデコード（オプション）

```bash
# Header
echo "$JWT_SVID" | cut -d. -f1 | base64 -d 2>/dev/null | jq .

# Payload (Claims)
echo "$JWT_SVID" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

**Payload出力例:**
```json
{
  "sub": "spiffe://example.org/ns/rhbk-demo/sa/myclient",
  "iss": "https://spire-oidc-discovery-provider-spiffe-system.apps.cluster-hb456...",
  "aud": "https://keycloak-rhbk-demo.apps.cluster-hb456.../realms/spiffe",
  "exp": 1782690756
}
```

---

## Step 5: Keycloak認証（Access Token取得）

### Token Endpointへのリクエスト

```bash
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
  -d "client_assertion=$JWT_SVID")

# HTTPステータスコードの抽出
HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo "HTTP Status: $HTTP_STATUS"
echo ""
echo "Response:"
echo "$BODY" | jq .
```

**成功時の出力例:**
```
HTTP Status: 200

Response:
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6IC...",
  "expires_in": 300,
  "refresh_expires_in": 0,
  "token_type": "Bearer",
  "not-before-policy": 0,
  "scope": "email profile"
}
```

### Access Tokenの抽出

```bash
ACCESS_TOKEN=$(echo "$BODY" | jq -r '.access_token')
echo "Access Token: ${ACCESS_TOKEN:0:80}..."
```

### Access Token Claimsのデコード（オプション）

```bash
echo "$ACCESS_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

**出力例:**
```json
{
  "exp": 1782691056,
  "iat": 1782690756,
  "jti": "trrtcc:f40b4ab4-dfbc-d9f8-4744-541b09a4f612",
  "iss": "https://keycloak-rhbk-demo.apps.cluster-hb456.../realms/spiffe",
  "aud": "account",
  "sub": "47027b3f-444f-439d-9f81-1e530e27a14e",
  "typ": "Bearer",
  "azp": "myclient",
  "acr": "1",
  "realm_access": {
    "roles": [
      "offline_access",
      "uma_authorization",
      "default-roles-spiffe"
    ]
  },
  "scope": "email profile",
  "clientHost": "133.200.223.198",
  "email_verified": false,
  "preferred_username": "service-account-myclient",
  "clientAddress": "133.200.223.198",
  "client_id": "myclient"
}
```

---

## すべてのステップを1つのスクリプトとして実行

```bash
#!/bin/bash
set -euo pipefail

echo "=== JWT-SVID Authentication Manual Test ==="
echo ""

# Step 1: Environment
APPS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KEYCLOAK_HOSTNAME="keycloak-rhbk-demo.${APPS_DOMAIN}"
REALM="spiffe"
AUDIENCE="https://${KEYCLOAK_HOSTNAME}/realms/${REALM}"
TOKEN_ENDPOINT="${AUDIENCE}/protocol/openid-connect/token"

echo "1. Environment:"
echo "   Audience: $AUDIENCE"
echo ""

# Step 2: Find Pod
CLIENT_POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind=="ReplicaSet")].metadata.name}' \
  | awk '{print $1}')

echo "2. Pod: $CLIENT_POD"
echo ""

# Step 3: Fetch JWT-SVID
echo "3. Fetching JWT-SVID..."
JWT_OUTPUT=$(oc exec $CLIENT_POD -n rhbk-demo -c client -- \
  /usr/local/bin/spire-agent api fetch jwt \
  -audience "$AUDIENCE" \
  -socketPath /spiffe-workload-api/spire-agent.sock 2>&1)

JWT_SVID=$(echo "$JWT_OUTPUT" | sed -n '2p' | sed 's/^[[:space:]]*//')
echo "   ✓ JWT-SVID fetched (${#JWT_SVID} chars)"
echo ""

# Step 4: Authenticate with Keycloak
echo "4. Authenticating with Keycloak..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
  -d "client_assertion=$JWT_SVID")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

if [ "$HTTP_STATUS" = "200" ]; then
    echo "   ✅ SUCCESS (HTTP $HTTP_STATUS)"
    echo ""
    echo "Response:"
    echo "$BODY" | jq .
else
    echo "   ✗ FAILED (HTTP $HTTP_STATUS)"
    echo ""
    echo "Error Response:"
    echo "$BODY" | jq .
    exit 1
fi
```

---

## トラブルシューティング

### JWT-SVID取得が失敗する場合

**症状:**
```
Error: error fetching JWT-SVID: rpc error: code = Unknown desc = workload is not authorized for trust domain "example.org"
```

**確認事項:**
```bash
# ClusterSPIFFEIDの確認
oc get clusterspiffeid -A

# SPIRE Agentログの確認
oc logs -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spire-agent --tail=50
```

### Keycloak認証が失敗する場合

**症状:**
```json
{
  "error": "unauthorized_client",
  "error_description": "Client authentication with signed JWT failed: ..."
}
```

**確認事項:**
```bash
# Keycloak Client設定の確認
oc exec keycloak-0 -n rhbk-demo -- /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin

oc exec keycloak-0 -n rhbk-demo -- /opt/keycloak/bin/kcadm.sh get clients -r spiffe --fields clientId,attributes
```

### spire-agentバイナリが見つからない場合

**症状:**
```
executable file `/usr/local/bin/spire-agent` not found: No such file or directory
```

**確認事項:**
```bash
# Podが正しいイメージを使用しているか確認
oc get pod $CLIENT_POD -n rhbk-demo -o jsonpath='{.spec.containers[0].image}'

# 期待されるイメージ: quay.io/kamori/jwt-svid-test-client:v1.0
```

**解決方法:**
```bash
# Podを再作成して正しいイメージを使用
oc delete pod $CLIENT_POD -n rhbk-demo

# 新しいPodが起動するまで待機
oc wait --for=condition=Ready pod -l app=jwt-test-client -n rhbk-demo --timeout=120s
```

---

## 参考情報

### 使用されるエンドポイント

| エンドポイント | 用途 |
|--------------|------|
| `/spiffe-workload-api/spire-agent.sock` | SPIRE Workload API（JWT-SVID取得） |
| `https://keycloak-rhbk-demo.../realms/spiffe/protocol/openid-connect/token` | Keycloak Token Endpoint（Access Token取得） |
| `https://spire-server.../bundle` | SPIRE Server Bundle Endpoint（公開鍵取得・Keycloakが使用） |
| `https://spire-oidc-discovery-provider-spiffe-system...` | OIDC Discovery Provider（JWT-SVID issuer） |

### 重要なパラメータ

| パラメータ | 値 | 説明 |
|----------|-----|-----|
| `grant_type` | `client_credentials` | OAuth 2.0 Client Credentials Grant |
| `client_assertion_type` | `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe` | JWT-SVID認証タイプ |
| `client_assertion` | `<JWT-SVID>` | SPIRE Agentから取得したJWT-SVID |
| `client_id` | **送信不要** | JWT-SVIDの`sub`クレームから自動解決される |

### JWT-SVID Claims

| Claim | 値の例 | 説明 |
|-------|--------|-----|
| `sub` | `spiffe://example.org/ns/rhbk-demo/sa/myclient` | SPIFFE ID（ServiceAccount形式） |
| `iss` | `https://spire-oidc-discovery-provider-spiffe-system...` | OIDC Discovery Provider URL |
| `aud` | `https://keycloak-rhbk-demo.../realms/spiffe` | Keycloak realm issuer URL |
| `exp` | `1782690756` | 有効期限（Unix timestamp） |

---

## 自動化スクリプト

手動実行が煩雑な場合は、自動化スクリプトを使用してください：

```bash
./scripts/test-jwt-svid-complete.sh
```

詳細は [JWT-SVID Authentication Guide](JWT-SVID-AUTHENTICATION-GUIDE.md) を参照してください。
