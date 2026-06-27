# RHBK + SPIFFE GitOps環境構築ガイド

**対象:** Red Hat build of Keycloak (RHBK) + OpenShift Zero Trust Workload Identity Manager (ZTWIM) / SPIRE + SPIFFE JWT-SVID認証環境  
**目的:** 成功した検証環境を、他のOpenShiftクラスターでも再現可能なGitOps構成として管理する  
**想定GitOps基盤:** OpenShift GitOps / Argo CD  
**作成日:** 2026-06-27

---

## 1. 基本方針

今回の環境は、以下のコンポーネントが段階的に依存しています。

```text
Namespace
  ↓
Operators
  ↓
ZTWIM / SPIRE Operand
  ↓
RHBK Instance
  ↓
Keycloak Realm / SPIFFE IdP / Client設定
  ↓
JWT-SVID認証テスト用Workload
```

そのため、GitOpsではすべてを1つのApplicationにまとめるのではなく、**依存関係ごとにApplicationを分割**します。

推奨する分割は以下です。

```text
00-namespaces
10-operators
20-spire
30-rhbk
40-keycloak-config
50-test-workloads
```

---

## 2. 推奨リポジトリ構成

```text
rhbk-spiffe-gitops/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── install-order.md
│   ├── known-good-values.md
│   └── troubleshooting.md
│
├── clusters/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── values.yaml
│   │   └── applications/
│   │       ├── app-of-apps.yaml
│   │       ├── 00-namespaces.yaml
│   │       ├── 10-operators.yaml
│   │       ├── 20-spire.yaml
│   │       ├── 30-rhbk.yaml
│   │       ├── 40-keycloak-config.yaml
│   │       └── 50-test-workloads.yaml
│   │
│   ├── staging/
│   │   └── ...
│   │
│   └── prod/
│       └── ...
│
├── platform/
│   ├── namespaces/
│   │   ├── kustomization.yaml
│   │   ├── spiffe-system.yaml
│   │   └── rhbk-demo.yaml
│   │
│   ├── operators/
│   │   ├── kustomization.yaml
│   │   ├── ztwim/
│   │   │   ├── operatorgroup.yaml
│   │   │   └── subscription.yaml
│   │   └── rhbk/
│   │       ├── operatorgroup.yaml
│   │       └── subscription.yaml
│   │
│   └── trust/
│       ├── kustomization.yaml
│       └── keycloak-spire-truststore-configmap.yaml
│
├── spire/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── zerotrustworkloadidentitymanager.yaml
│   │   ├── spireserver.yaml
│   │   ├── spireagent.yaml
│   │   ├── spiffe-csi-driver.yaml
│   │   ├── spire-oidc-discovery-provider.yaml
│   │   └── clusterspiffeid-myclient.yaml
│   │
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       │       ├── spireserver-patch.yaml
│       │       └── clusterspiffeid-patch.yaml
│       ├── staging/
│       └── prod/
│
├── rhbk/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── keycloak.yaml
│   │   ├── postgres.yaml
│   │   ├── service.yaml
│   │   ├── route.yaml
│   │   └── truststore.yaml
│   │
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       │       ├── keycloak-hostname-patch.yaml
│       │       └── keycloak-features-patch.yaml
│       ├── staging/
│       └── prod/
│
├── keycloak-config/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── realm-spiffe.json
│   │   ├── idp-spiffe.json
│   │   ├── client-myclient.json
│   │   ├── authentication-flow.json
│   │   └── keycloak-config-job.yaml
│   │
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   └── patches/
│       │       ├── idp-bundle-endpoint-patch.yaml
│       │       └── client-attributes-patch.yaml
│       ├── staging/
│       └── prod/
│
├── test-workloads/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── jwt-test-client.yaml
│   │   ├── serviceaccount-myclient.yaml
│   │   └── auth-test-job.yaml
│   │
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── prod/
│
└── scripts/
    ├── export-current-state.sh
    ├── sanitize-export.sh
    ├── test-bundle-endpoint.sh
    ├── test-jwt-svid.sh
    └── test-token-request.sh
```

---

## 3. Application分割方針

### 3.1 分割の判断基準

以下に該当するものは、Applicationを分けることを推奨します。

```text
1. CRDを作るもの
2. CRDに依存するもの
3. 起動完了を待つ必要があるもの
4. Secret / 証明書 / Truststoreに依存するもの
5. 環境ごとの差分が大きいもの
6. 本番では不要なテスト用リソース
```

今回の構成では、次の分割が扱いやすいです。

| Application | 役割 | 分割理由 |
|---|---|---|
| 00-namespaces | Namespace作成 | 全リソースの前提 |
| 10-operators | ZTWIM / RHBK Operator導入 | CRD作成のため |
| 20-spire | SPIRE / ZTWIM Operand作成 | ZTWIM Operator CRDに依存 |
| 30-rhbk | RHBKインスタンス作成 | RHBK Operator CRDに依存 |
| 40-keycloak-config | Realm / IdP / Client設定 | Keycloak起動後に実行が必要 |
| 50-test-workloads | JWT-SVID認証テスト | 本番では不要または限定利用 |

---

## 4. Sync Wave設計

Argo CDのSync Waveを使い、以下の順番で同期します。

```text
Wave 0   00-namespaces
Wave 10  10-operators
Wave 20  20-spire
Wave 30  30-rhbk
Wave 40  40-keycloak-config
Wave 50  50-test-workloads
```

例:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "20"
```

ただし、Sync Waveだけでは「Operatorが完全にReadyになったこと」までは保証できません。Operator導入直後にCRを適用するApplicationには、必要に応じて以下を設定します。

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
```

また、Keycloak Realm設定用のJobには、Keycloak起動待ち処理を入れることを推奨します。

```bash
until curl -sf http://keycloak-service.rhbk-demo.svc:8080/realms/master; do
  echo "waiting for keycloak..."
  sleep 5
done
```

---

## 5. App of Apps構成

トップレベルはApp of Appsにします。

```text
app-of-apps
├── 00-namespaces
├── 10-operators
├── 20-spire
├── 30-rhbk
├── 40-keycloak-config
└── 50-test-workloads
```

### app-of-apps例

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhbk-spiffe-dev
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://git.example.com/platform/rhbk-spiffe-gitops.git
    targetRevision: main
    path: clusters/dev/applications
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
```

---

## 6. 個別Application例

### 6.1 20-spire

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: 20-spire
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "20"
spec:
  project: default
  source:
    repoURL: https://git.example.com/platform/rhbk-spiffe-gitops.git
    targetRevision: main
    path: spire/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: spiffe-system
  syncPolicy:
    syncOptions:
      - CreateNamespace=false
      - SkipDryRunOnMissingResource=true
    automated:
      prune: false
      selfHeal: true
```

### 6.2 40-keycloak-config

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: 40-keycloak-config
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "40"
spec:
  project: default
  source:
    repoURL: https://git.example.com/platform/rhbk-spiffe-gitops.git
    targetRevision: main
    path: keycloak-config/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: rhbk-demo
  syncPolicy:
    syncOptions:
      - CreateNamespace=false
    automated:
      prune: false
      selfHeal: false
```

`keycloak-config` は、Argo CDがKeycloak内部のRealm/Client/IdP差分を直接検出できないケースが多いため、`selfHeal: false` でもよいです。設定反映はJobやConfig CLIで冪等に実行する設計にします。

---

## 7. 各Applicationの管理対象

### 7.1 00-namespaces

管理対象:

```text
spiffe-system
rhbk-demo
必要に応じてResourceQuota / LimitRange / NetworkPolicy
```

目的:

```text
OperatorGroupやOperand作成の前提Namespaceを先に作成する
```

---

### 7.2 10-operators

管理対象:

```text
Zero Trust Workload Identity Manager Operator
RHBK Operator
必要に応じてcert-manager Operator / External Secrets Operator
```

含めるリソース:

```text
OperatorGroup
Subscription
CatalogSourceが必要な場合はCatalogSource
```

注意:

```text
Operator導入後、CRD登録完了まで待ち時間が発生する。
次段のApplicationではSkipDryRunOnMissingResource=trueを検討する。
```

---

### 7.3 20-spire

管理対象:

```text
ZeroTrustWorkloadIdentityManager
SpireServer
SpireAgent
SpiffeCSIDriver
SpireOIDCDiscoveryProvider
ClusterSPIFFEID
```

今回の成功構成では、SpireServerは必ず `https_web` profileで作成します。

```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: SpireServer
metadata:
  name: cluster
  namespace: spiffe-system
spec:
  trustDomain: example.org
  caKeyType: ec-p256
  federation:
    bundleEndpoint:
      profile: https_web
      refreshHint: 300
      httpsWeb:
        servingCert:
          fileSyncInterval: 86400
    managedRoute: "true"
```

重要:

```text
bundleEndpoint.profile は後から変更できない前提で扱う。
初回構築時から https_web を指定する。
```

---

### 7.4 30-rhbk

管理対象:

```text
Keycloak CR
DB関連リソース
Service
Route
Truststore ConfigMap
Secret参照
```

RHBKでは、以下のFeatureを有効化します。

```yaml
spec:
  features:
    enabled:
      - spiffe
      - client-auth-federated
```

KeycloakからSPIRE Bundle Endpointへアクセスするため、TruststoreにはOpenShift Service CA、またはBundle Endpoint証明書の発行CAを入れます。

Bundle Endpoint URLは、証明書SANと一致する値に固定します。

```text
https://spire-server.spiffe-system.svc.cluster.local:8443
```

または、Service Serving CertificateのSANに合わせて以下でもよいです。

```text
https://spire-server.spiffe-system.svc:8443
```

---

### 7.5 40-keycloak-config

管理対象:

```text
Realm
SPIFFE Identity Provider
Client
Client Authenticator設定
Authentication Flow設定
Protocol Mapper
```

Keycloak内部設定は、以下のいずれかで管理します。

#### 案A: Keycloak Config CLI Job

推奨です。

```text
keycloak-config/
├── realm-spiffe.json
├── idp-spiffe.json
├── client-myclient.json
└── keycloak-config-cli-job.yaml
```

メリット:

```text
Realm / Client / IdP設定をJSONとしてGit管理できる
再現性が高い
別クラスタへ移植しやすい
```

#### 案B: kcadm Job

検証環境から移行しやすい方式です。

```text
keycloak-config/
├── jobs/
│   ├── 01-create-realm-job.yaml
│   ├── 02-create-spiffe-idp-job.yaml
│   └── 03-create-client-job.yaml
└── scripts/
    └── configure-keycloak.sh
```

注意:

```text
kcadm Job方式では冪等性を自前で実装する必要がある。
既存設定がある場合は create ではなく update / upsert できるようにする。
```

---

### 7.6 50-test-workloads

管理対象:

```text
ServiceAccount
jwt-test-client Pod
auth-test Job
検証用ClusterSPIFFEID
```

目的:

```text
JWT-SVID取得
Bundle Endpoint疎通
Token Endpoint認証
Access Token取得確認
```

本番環境では原則無効化します。

```text
test-workloads/overlays/dev      有効
test-workloads/overlays/staging  必要に応じて有効
test-workloads/overlays/prod     無効、またはSmoke Test Jobのみ
```

---

## 8. Kustomize overlay設計

### 8.1 baseに置く値

環境差分が少ない基本設定をbaseに置きます。

```text
trustDomain: example.org
caKeyType: ec-p256
bundleEndpoint profile: https_web
clientAuthenticatorType: federated-jwt
client_assertion_type: jwt-spiffe
Keycloak feature: spiffe, client-auth-federated
```

### 8.2 overlayに置く値

クラスタごとに変わる値はoverlayに置きます。

```text
OpenShift Route hostname
jwtIssuer
Keycloak hostname
bundleEndpoint URL
namespace
resource size
storage size
replicas
```

---

## 9. 環境別valuesの例

`clusters/dev/values.yaml` または `overlays/dev/patches` に切り出します。

```yaml
clusterName: dev
baseDomain: apps.cluster-ds9c5.ds9c5.sandbox1124.opentlc.com

namespaces:
  spiffe: spiffe-system
  keycloak: rhbk-demo

spiffe:
  trustDomain: example.org
  caKeyType: ec-p256
  bundleEndpoint:
    profile: https_web
    host: spire-server.spiffe-system.svc.cluster.local
    port: 8443
  jwtIssuer: https://spire-oidc-discovery-provider-spiffe-system.apps.cluster-ds9c5.ds9c5.sandbox1124.opentlc.com

keycloak:
  hostname: keycloak-rhbk-demo.apps.cluster-ds9c5.ds9c5.sandbox1124.opentlc.com
  realm: spiffe
  clientId: myclient
  spiffeId: spiffe://example.org/myclient
  features:
    - spiffe
    - client-auth-federated
```

---

## 10. Secret管理方針

GitにSecretを平文で置いてはいけません。

選択肢:

```text
1. External Secrets Operator
2. Sealed Secrets
3. SOPS + age/GPG
4. Argo CD Vault Plugin
```

Secret管理対象:

```text
RHBK admin password
DB password
Keycloak bootstrap secret
任意のカスタム証明書秘密鍵
```

一方、SPIRE Bundle Endpoint証明書については、OpenShift Service Serving Certificateを利用することで、秘密鍵をGitに置かずに済みます。

今回の成功構成では、OpenShift Service Serving CertificateがDNS SANs付き証明書を自動生成するため、この方式を推奨します。

---

## 11. Known Good Valuesとして固定すべき値

`docs/known-good-values.md` に、成功構成の値を明記します。

```text
OpenShift version
ZTWIM Operator version
RHBK version
SPIRE Server version
SpireServer profile=https_web
trustDomain
caKeyType=ec-p256
jwtIssuer
bundleEndpoint URL
Keycloak features
Keycloak hostname/proxy設定
SPIFFE IdP alias
SPIFFE IdP bundleEndpoint
SPIFFE IdP trustDomain
clientId
jwt.credential.issuer
jwt.credential.sub
成功したaudience
成功したclient_assertion_type
成功したToken Endpoint URL
```

今回の重要値:

```text
SpireServer federation.bundleEndpoint.profile = https_web
Keycloak feature = spiffe, client-auth-federated
Keycloak SPIFFE IdP alias = spiffe
Keycloak SPIFFE IdP trustDomain = spiffe://example.org
Keycloak SPIFFE IdP bundleEndpoint = https://spire-server.spiffe-system.svc.cluster.local:8443
Client authenticator = federated-jwt
jwt.credential.issuer = spiffe
jwt.credential.sub = spiffe://example.org/myclient
client_assertion_type = urn:ietf:params:oauth:client-assertion-type:jwt-spiffe
```

---

## 12. 検証スクリプト方針

GitOpsで構築した後、以下の検証を自動化します。

### 12.1 Bundle Endpoint疎通

```bash
curl -v https://spire-server.spiffe-system.svc.cluster.local:8443
```

期待結果:

```text
SSL certificate verify ok
HTTP 200
JSONに "use":"jwt-svid" が含まれる
```

### 12.2 JWT-SVID取得

```bash
spire-agent api fetch jwt \
  -audience "<KEYCLOAK_REALM_ISSUER>" \
  -socketPath /spiffe-workload-api/spire-agent.sock
```

期待結果:

```text
JWT-SVIDが取得できる
alg=ES256
sub=spiffe://example.org/myclient
```

### 12.3 Token Endpoint認証

```bash
curl -s -i -X POST "<TOKEN_ENDPOINT>" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-spiffe" \
  --data-urlencode "client_assertion=<JWT_SVID>"
```

期待結果:

```text
HTTP 200
access_token が返る
```

---

## 13. GitOps化時の注意点

### 13.1 Operator生成物はGit管理しない

以下はOperator生成物なので、原則としてGit管理しません。

```text
spire-server ConfigMap
spire-server StatefulSet
spire-agent DaemonSet
Service Serving Certificate Secret
Keycloak StatefulSet
```

これらは、トラブルシューティング用のexportとして保存してもよいですが、再適用用マニフェストとしては扱わない方針です。

### 13.2 SpireServer profileは初回からhttps_webにする

`https_spiffe` で構築後に `https_web` へ変更するのではなく、初回から `https_web` で構築します。

```text
profile is immutable と考えて設計する
変更が必要な場合はSpireServer再作成を前提にする
```

### 13.3 Keycloak内部設定は冪等化する

Realm / IdP / Client設定は、Jobで反映する場合、必ず冪等にします。

```text
既に存在する場合はcreateではなくupdateする
存在しない場合のみcreateする
失敗時に再実行できるようにする
```

### 13.4 本番ではtest-workloadsを無効化する

JWT-SVID認証テスト用PodやJobは、dev/staging中心に配置します。prodではSmoke Testのみ、または無効化します。

---

## 14. 推奨構築フロー

```text
1. Git repositoryを準備
2. clusters/<env>/applications にApplication群を配置
3. 00-namespacesを同期
4. 10-operatorsを同期
5. Operator / CRDのReadyを確認
6. 20-spireを同期
7. SpireServerがhttps_webで起動したことを確認
8. Bundle Endpoint証明書のDNS SANsを確認
9. 30-rhbkを同期
10. KeycloakがReadyになるまで待機
11. 40-keycloak-configを同期
12. Realm / SPIFFE IdP / Client設定を確認
13. 50-test-workloadsを同期
14. JWT-SVID取得とToken Endpoint認証を確認
```

---

## 15. 最終推奨構成

最初のGitOps化では、以下の6 Application分割を推奨します。

```text
00-namespaces
10-operators
20-spire
30-rhbk
40-keycloak-config
50-test-workloads
```

この分割により、以下のメリットがあります。

```text
失敗箇所を切り分けやすい
Operator / CRD依存関係を扱いやすい
Keycloak内部設定の反映タイミングを制御しやすい
テスト用Workloadを本番から切り離せる
他クラスターへの再現性が高い
```

本番環境では、`50-test-workloads` は無効化し、必要であればSmoke Test Jobだけ残します。

---

## 16. まとめ

GitOps化の目的は、単なるバックアップではなく、**別クラスターで同じRHBK + SPIFFE JWT-SVID認証環境を再構築できる状態にすること**です。

そのためには、以下の3点を重視します。

```text
1. 再適用可能なCR / ManifestをGit管理する
2. Keycloak Realm / IdP / Client設定をJSONまたはJobでGit管理する
3. 成功確認コマンドと期待結果をテストとして残す
```

今回の成功構成では、特に以下を固定値として扱うことが重要です。

```text
SpireServer profile=https_web
OpenShift Service Serving CertificateによるDNS SANs付き証明書
Keycloak truststoreへのService CA追加
SPIFFE Identity Provider alias=spiffe
jwt.credential.issuer=spiffe
jwt.credential.sub=spiffe://example.org/myclient
client_assertion_type=jwt-spiffe
```

この方針に沿って構成すれば、他のOpenShiftクラスターでも高い再現性で環境構築できます。
