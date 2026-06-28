# RHBK + SPIFFE JWT-SVID 認証フロー考察アップデート

## 1. 結論

今回の `test-jwt-svid-complete.sh` 実行結果により、OpenShift上の RHBK + SPIFFE JWT-SVID client authentication は **End-to-Endで成功**したと判断できます。

確認できた成功ポイントは以下です。

```text
JWT-SVID取得: 成功
JWT-SVIDのsub/iss/aud取得: 成功
Keycloak Token Endpoint認証: HTTP 200
Access Token発行: 成功
```

したがって、これまで未確定だった以下の点は、実環境上では成立したと見てよいです。

```text
Client / App → SPIRE Agent → SPIRE Server → JWT-SVID取得
Client / App → Keycloak Token Endpoint → Federated JWT client authentication
Keycloak → Access Token発行
```

今回の結果により、認証フロー図・説明資料の考察は一部アップデートする必要があります。

---

## 2. 今回の成功ログから確定した値

今回の成功ログでは、JWT-SVIDのclaimsは以下でした。

```text
sub: spiffe://example.org/ns/rhbk-demo/sa/myclient
iss: https://spire-oidc-discovery-provider-spiffe-system.apps.cluster-hb456.hb456.sandbox3244.opentlc.com
aud: https://keycloak-rhbk-demo.apps.cluster-hb456.hb456.sandbox3244.opentlc.com/realms/spiffe
```

Token Endpointは以下です。

```text
https://keycloak-rhbk-demo.apps.cluster-hb456.hb456.sandbox3244.opentlc.com/realms/spiffe/protocol/openid-connect/token
```

認証結果は以下です。

```text
HTTP Status: 200
access_token: 発行成功
token_type: Bearer
expires_in: 300s
```

---

## 3. 前回考察からアップデートすべき点

## 3.1 SPIFFE IDは `/myclient` ではなく Kubernetes ServiceAccount形式

前回の図・考察では、例として以下のSPIFFE IDを使っていました。

```text
spiffe://example.org/myclient
```

しかし、今回の成功ログでは実際のJWT-SVID `sub` は以下です。

```text
spiffe://example.org/ns/rhbk-demo/sa/myclient
```

したがって、スライド・Mermaid・GitOpsドキュメントでは、成功値に合わせてこちらに統一するのがよいです。

```text
jwt.credential.sub = spiffe://example.org/ns/rhbk-demo/sa/myclient
```

これは、OpenShift/Kubernetes上のServiceAccount `myclient` に対応するSPIFFE IDとして自然です。

---

## 3.2 `iss` として SPIRE OIDC Discovery Provider が含まれる

今回のJWT-SVIDでは、`iss` が以下になっています。

```text
https://spire-oidc-discovery-provider-spiffe-system.apps.cluster-hb456.hb456.sandbox3244.opentlc.com
```

したがって、OIDC Discovery Providerは **JWT-SVIDのissuerとしてフロー上に関係している** と整理できます。

ただし、ここで注意が必要です。

OIDC Discovery ProviderがJWT-SVIDの `iss` に含まれていることと、Keycloakが署名検証用の公開鍵をOIDC Discovery Providerから取得していることは、同じ意味ではありません。

今回のRHBK SPIFFE IdP構成では、KeycloakはSPIFFE IdPの `bundleEndpoint` に設定された先を参照します。成功構成では、これはSPIRE ServerのBundle Endpointです。

```text
https://spire-server.spiffe-system.svc.cluster.local:8443
```

そのため、図では以下のように分けて表現するのが最も正確です。

```text
JWT-SVIDのiss: SPIRE OIDC Discovery Provider URL
Keycloakの公開鍵取得先: SPIRE Server Bundle Endpoint
```

---

## 3.3 `client_id` は表示されているが、POSTデータには送られていない

スクリプトの出力には以下があります。

```text
Client ID: myclient
```

ただし、添付スクリプトのToken Requestでは、実際には `client_id` は送信していません。

送信しているform parameterは以下です。

```bash
grant_type=client_credentials
client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe
client_assertion=<JWT-SVID>
```

つまり、今回成功した本命パターンは以下です。

```text
client_assertion_type = urn:ietf:params:oauth:client-assertion-type:jwt-spiffe
client_assertion = JWT-SVID
client_id = 送信しない
```

KeycloakはJWT-SVIDの `sub` などをもとに、対応するclientを解決していると考えられます。

---

## 3.4 `audience` は外部Keycloak Realm URLで成功

今回のスクリプトでは、audienceはOpenShift Routeの外部Keycloak URLから生成されています。

```text
https://keycloak-rhbk-demo.apps.cluster-hb456.hb456.sandbox3244.opentlc.com/realms/spiffe
```

この値でJWT-SVIDを取得し、同じ外部URLのToken Endpointへ送信してHTTP 200になっています。

したがって、図や手順では以下のように表現するのがよいです。

```text
JWT-SVID audience = Keycloak realm issuer URL
```

より具体的には、以下です。

```text
https://<keycloak-route-host>/realms/spiffe
```

---

## 4. auth-flow.mmdに対する修正方針

## 4.1 OIDC Discovery Providerは削除せず、役割を限定して残す

前回は「OIDC Discovery Providerは本線から外してよい」と整理しました。

しかし今回の成功ログでは、JWT-SVIDの `iss` がOIDC Discovery Provider URLであることが確認できました。

そのため、図から完全に削除するより、以下のように **issuerとして残す** のがより正確です。

```text
SPIRE OIDC Discovery Provider
役割: JWT-SVIDの iss URL
```

ただし、Keycloakの公開鍵取得フローとしては、OIDC Discovery ProviderではなくSPIRE Server Bundle Endpointを描く方が、今回の構成に合っています。

---

## 4.2 公開鍵取得の線は Keycloak → SPIRE Server Bundle Endpoint にする

今回の成功構成を説明する図では、以下の線を本線として描くべきです。

```text
Keycloak / RHBK → SPIRE Server Bundle Endpoint
```

ラベルは以下がよいです。

```text
GET Bundle Endpoint
JWKS / SPIFFE Bundle取得
use: jwt-svid
```

一方で、OIDC Discovery Providerには以下の注釈を付けるのがよいです。

```text
JWT-SVID iss URL
外部OIDC Federation用途でも利用
```

---

## 4.3 Client IDの表現を修正する

今回のスクリプトでは `CLIENT_ID=myclient` は変数として表示されていますが、Token Requestに `client_id` は送られていません。

したがって、図中では以下のようにするのがよいです。

```text
Token Request:
- grant_type=client_credentials
- client_assertion_type=jwt-spiffe
- client_assertion=<JWT-SVID>
- client_idは送信しない
```

スライドでは簡潔に以下でも十分です。

```text
JWT-SVIDをclient_assertionとして送信
```

---

## 4.4 SPIFFE ID表記を成功値に統一する

図中のSPIFFE IDは以下に統一します。

```text
spiffe://example.org/ns/rhbk-demo/sa/myclient
```

Keycloak client側の設定説明も、以下に合わせます。

```text
jwt.credential.sub = spiffe://example.org/ns/rhbk-demo/sa/myclient
jwt.credential.issuer = spiffe
```

ここで `jwt.credential.issuer = spiffe` は、JWT-SVIDの `iss` URLではなく、Keycloak上のSPIFFE Identity Provider aliasを指す、という説明を残すと誤解が少ないです。

---

## 5. 修正後の推奨フロー

修正後のMermaidフローは以下の形が適切です。

```mermaid
sequenceDiagram
    participant Client as jwt-test-client Pod
    participant Agent as SPIRE Agent
    participant Server as SPIRE Server
    participant OIDC as SPIRE OIDC Discovery Provider
    participant KC as Keycloak / RHBK

    Note over Client,KC: JWT-SVID Client Authentication Flow

    rect rgb(240, 248, 255)
        Note right of Client: Step 1: JWT-SVID取得
        Client->>Agent: Fetch JWT-SVID<br/>audience = Keycloak realm issuer URL
        Agent->>Server: Request JWT-SVID<br/>SPIFFE ID = spiffe://example.org/ns/rhbk-demo/sa/myclient
        Server->>Server: Sign JWT-SVID
        Server-->>Agent: JWT-SVID
        Agent-->>Client: JWT-SVID<br/>sub = spiffe://example.org/ns/rhbk-demo/sa/myclient<br/>iss = SPIRE OIDC Discovery Provider URL
    end

    rect rgb(255, 250, 240)
        Note right of Client: Step 2: Token Request
        Client->>KC: POST Token Endpoint<br/>grant_type=client_credentials<br/>client_assertion_type=jwt-spiffe<br/>client_assertion=&lt;JWT-SVID&gt;<br/>client_idは送信しない
    end

    rect rgb(240, 255, 240)
        Note right of KC: Step 3: JWT-SVID検証
        KC->>KC: Extract sub / iss / aud
        KC->>KC: Find Client by jwt.credential.sub
        KC->>KC: Get SPIFFE IdP<br/>jwt.credential.issuer = spiffe
        KC->>Server: GET Bundle Endpoint<br/>https://spire-server.spiffe-system.svc.cluster.local:8443
        Server-->>KC: SPIFFE Bundle / JWKS<br/>use = jwt-svid
        KC->>KC: Verify signature
        KC->>KC: Validate claims<br/>sub / iss / aud / exp
    end

    rect rgb(255, 240, 245)
        Note right of KC: Step 4: Access Token発行
        KC-->>Client: HTTP 200 OK<br/>access_token
    end

    Note over OIDC: OIDC Discovery ProviderはJWT-SVIDのiss URLとして関係
    Note over KC,Server: Keycloakの公開鍵取得先はSPIRE Server Bundle Endpoint
```

---

## 6. デモアーキテクチャ図への反映ポイント

スライド用の簡略図では、以下のように配置するのがよいです。

```text
Client / App
  ↓ 1. JWT-SVID取得
SPIRE Agent
  ↓ 2. JWT-SVID発行要求
SPIRE Server
  → JWT-SVID issuer: SPIRE OIDC Discovery Provider URL

Client / App
  ↓ 3. JWT-SVIDをclient_assertionとして送信
Keycloak / RHBK

Keycloak / RHBK
  ↓ 4. JWKS / Bundle取得
SPIRE Server Bundle Endpoint

Keycloak / RHBK
  ↓ 5. Access Token発行
Client / App
```

OIDC Discovery Providerは、Keycloakとの線でつなぐのではなく、SPIRE ServerまたはJWT-SVIDの横に補足として配置するのがよいです。

```text
SPIRE OIDC Discovery Provider
JWT-SVIDのiss URL
```

---

## 7. 成功条件のアップデート

スライド下部に置く成功条件は、今回の成功値を反映して以下に更新するのがよいです。

```text
成功条件:
- SpireServer profile=https_web
- Bundle Endpoint証明書にDNS SANsあり
- Keycloak truststore=OpenShift Service CA
- JWT-SVID aud=Keycloak realm issuer URL
- JWT-SVID sub=spiffe://example.org/ns/rhbk-demo/sa/myclient
- jwt.credential.issuer=spiffe
- jwt.credential.sub=JWT-SVIDのsubと一致
- client_assertion_type=jwt-spiffe
- client_idは送信しない
```

スライド上で短くするなら以下です。

```text
成功条件:
profile=https_web / truststore=OpenShift Service CA / aud=Keycloak realm issuer / sub=ServiceAccount SPIFFE ID / client_assertion_type=jwt-spiffe
```

---

## 8. 添付スクリプトに対する補足

今回の `test-jwt-svid-complete.sh` は、End-to-End認証確認として有用です。

ただし、以下の点は今後の再現・本番化のために補足しておくとよいです。

### 8.1 `curl -k` を使っている

スクリプトではToken Endpointへのcurlに `-k` が付いています。

```bash
curl -k -s -w '\nHTTP_CODE:%{http_code}' -X POST "$TOKEN_ENDPOINT" \
```

これはKeycloak Route側のTLS検証をスキップします。

今回の目的はJWT-SVID client authenticationの検証なので問題ありませんが、本番相当の疎通確認では `-k` なしでも成功することを別途確認するのが望ましいです。

### 8.2 Access Tokenをログに保存している

スクリプトは成功時にレスポンスを以下に保存します。

```text
logs/SUCCESS-GITOPS-<timestamp>.json
```

Access Tokenは短命でも認証情報なので、共有用ログではマスクするべきです。

```text
access_token: <redacted>
```

### 8.3 `client_id`は表示のみ

出力には `Client ID: myclient` と出ますが、リクエストbodyには `client_id` を含めていません。

これは今回の成功パターンとして重要なので、ドキュメントに明記するべきです。

---

## 9. 最終結論

今回の成功結果により、RHBK + SPIFFE JWT-SVID client authenticationの実フローは以下として整理できます。

```text
1. Client PodがSPIRE Agent Workload APIからJWT-SVIDを取得
2. JWT-SVIDにはServiceAccount由来のSPIFFE IDがsubとして入る
3. JWT-SVIDのissにはSPIRE OIDC Discovery Provider URLが入る
4. Client PodがJWT-SVIDをclient_assertionとしてKeycloak Token Endpointへ送信
5. Keycloakはjwt.credential.sub / issuer設定に基づきclientとSPIFFE IdPを解決
6. KeycloakはSPIRE Server Bundle Endpointから公開鍵を取得
7. KeycloakがJWT-SVIDの署名とclaimsを検証
8. 検証成功後、Access Tokenを発行
```

したがって、フロー図では **OIDC Discovery Providerを完全削除するのではなく、JWT-SVIDのissuerとして補足的に残す** のがよいです。

一方で、Keycloakの公開鍵取得先は **SPIRE OIDC Discovery ProviderではなくSPIRE Server Bundle Endpoint** として描くのが、今回の成功構成に最も合っています。
