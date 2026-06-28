# GitOps改善履歴

このドキュメントは、JWT-SVID認証テストの手動作業をGitOps化した改善履歴を記録します。

**改善結果: 手動作業を4ステップから2ステップに削減しました。**

## 改善実施状況

| 提案 | 状態 | 実施日 | 効果 |
|------|------|--------|------|
| 提案1: ClusterSPIFFEID削除 | ✅ 完了 | 2026-06-27 | 設定一貫性向上 |
| 提案2: Keycloak Job修正 | ✅ 完了 | 2026-06-27 | 手動Step 2, 3不要 |
| 提案3: spire-agent CLI提供 | ⚠️ 未実装 | - | 手動Step 1が残る |

## 実施した改善

### ✅ 提案1: ClusterSPIFFEID削除（完了）

**実施内容:**
- `spire/base/clusterspiffeid-myclient.yaml`を削除
- `spire/base/kustomization.yaml`から参照を削除
- デフォルトClusterSPIFFEID (`zero-trust-workload-identity-manager-spire-default`) を使用

**効果:**
- SPIFFE ID生成がOperator管理のデフォルトテンプレートに統一
- カスタムClusterSPIFFEIDとデフォルトの優先順位問題を解消
- 設定の一貫性向上

**実施日:** 2026-06-27

---

### ✅ 提案2: Keycloak config Job修正（完了）

**実施内容:**
- Job名: `configure-keycloak-v2` → `configure-keycloak-v3`
- BUNDLE_ENDPOINT修正: `spiffe-system` → `zero-trust-workload-identity-manager`
- CLIENT_SPIFFE_ID修正: `spiffe://example.org/myclient` → `spiffe://example.org/ns/rhbk-demo/sa/myclient`

**変更箇所:**
```yaml
# keycloak-config/base/configure-keycloak-job.yaml
env:
  - name: BUNDLE_ENDPOINT
    value: "https://spire-server.zero-trust-workload-identity-manager.svc.cluster.local:8443"
  - name: CLIENT_SPIFFE_ID
    value: "spiffe://example.org/ns/rhbk-demo/sa/myclient"
```

**効果:**
- Keycloak Client設定が自動的に正しく設定される
- 手動修正スクリプト（`fix-keycloak-client-config.sh`）が不要
- Keycloak Pod再起動が不要

**実施日:** 2026-06-27

---

### ⚠️ 提案3: spire-agent CLI提供（未実装）

**✅ 2026-06-29 UPDATE: カスタムイメージ導入により完全自動化達成**

カスタムコンテナイメージ（`quay.io/kamori/jwt-svid-test-client:v1.0`）を導入し、spire-agentバイナリを事前組み込みしました。

**解決した問題:**
- `oc cp`によるバイナリ破損（segfault exit code 139）
- Pod再起動のたびの手動インストール
- ベースイメージの互換性問題

**カスタムイメージ詳細:**
- Multi-stage Dockerfileで公式SPIRE Agent RHEL9イメージからバイナリを抽出
- ベースイメージ: `registry.redhat.io/ubi9/ubi:latest` (RHEL9互換)
- spire-agentバイナリ: `/usr/local/bin/spire-agent` (58MB)
- ビルド時に`--platform linux/amd64`指定（OpenShiftクラスターのアーキテクチャに対応）

**運用:**
- Pod再起動後も自動的に動作
- 手動インストールスクリプト（`install-spire-agent-binary.sh`）は不要（DEPRECATED）
- GitOps完全自動化達成

---

## 改善前後の比較

### Before（改善前 - 4ステップ）

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

### After（改善後 - 1ステップ）

```bash
# 認証テスト実行（spire-agentバイナリは既にカスタムイメージに組み込み済み）
./scripts/test-jwt-svid-complete.sh
```

**削減された手動作業:**
- ~~Step 1: spire-agentバイナリインストール~~ → カスタムイメージに事前組み込み
- ~~Step 2: Keycloak Client設定修正~~ → GitOps自動化
- ~~Step 3: Keycloak Pod再起動~~ → 不要（最初から正しい設定）

---

## 検証結果

### 最終デプロイテスト（2026-06-27）

**環境:**
- OpenShift 4.x
- RHBK 26.6.4
- ZTWIM Operator v1.0.1

**デプロイ:**
```bash
oc apply -f clusters/dev/applications/app-of-apps.yaml
```

**結果:**
- 全Application: `Synced` & `Healthy` ✅
- configure-keycloak-v3 Job: `Complete` ✅
- Keycloak Client設定: 自動的に正しく設定 ✅

**認証テスト:**
```
✅ SUCCESS: Keycloak authentication successful!

JWT-SVID Claims:
  sub: spiffe://example.org/ns/rhbk-demo/sa/myclient
  iss: https://spire-oidc-discovery-provider-spiffe-system.apps...
  aud: https://keycloak-rhbk-demo.apps...

HTTP Status: 200
Access Token: eyJhbGci...
Token Type: Bearer
Expires In: 300s

Result saved to: logs/SUCCESS-GITOPS-20260627-164556.json
```

---

## その他の改善

### Application Finalizer追加

**実施内容:**
全6つのchild Applicationに`resources-finalizer.argocd.argoproj.io`を追加

**対象ファイル:**
- `clusters/dev/applications/00-namespaces.yaml`
- `clusters/dev/applications/10-operators.yaml`
- `clusters/dev/applications/20-spire.yaml`
- `clusters/dev/applications/30-rhbk.yaml`
- `clusters/dev/applications/40-keycloak-config.yaml`
- `clusters/dev/applications/50-test-workloads.yaml`

**効果:**
- App-of-Apps削除時にchild Applicationも自動削除
- リソースクリーンアップの改善

**注意:**
- Operator管理CR（SpireServer等）はforegroundDeletion finalizerを持つため、削除がブロックされる場合がある
- エラー状態のDeploymentがある場合は手動削除が必要

**実施日:** 2026-06-27

### Namespace整理

**実施内容:**
- `platform/namespaces/spiffe-system.yaml`を削除
- Operatorは`zero-trust-workload-identity-manager` namespaceを自動作成

**理由:**
- `spiffe-system` namespaceは使用されていない
- 不要なリソース定義を削除

**実施日:** 2026-06-27

### 不要なJob無効化

**実施内容:**
- `test-workloads/base/jwt-svid-full-auth-test-job.yaml`を無効化
- `test-workloads/base/kustomization.yaml`から削除

**理由:**
- initContainerがspire-agentバイナリ抽出に失敗
- 同じラベルを持つため、Pod選択スクリプトがJob Podを誤選択
- auth-test-job（SPIFFE socket確認のみ）で十分

**実施日:** 2026-06-27

### スクリプト改善

**実施内容:**

1. **Pod選択ロジック改善**
   - `ownerReferences`でDeployment Podを明示的に選択
   - JobとDeploymentの誤選択を防止

2. **spire-agentバイナリパス修正**
   - RHBK Operator imageの実際のパス`/spire-agent`を最初にチェック
   - コピー先を`/tmp/spire-agent`に変更（権限問題回避）

**対象スクリプト:**
- `scripts/install-spire-agent-binary.sh`
- `scripts/test-jwt-svid-complete.sh`

**実施日:** 2026-06-27

---

## ~~残存する手動作業（将来の改善候補）~~

### ~~1. spire-agentバイナリのインストール~~

**✅ 2026-06-29 RESOLVED: カスタムイメージ導入により完全自動化**

~~**現状**: `install-spire-agent-binary.sh`で手動インストール~~

**解決策:** カスタムコンテナイメージ導入（`quay.io/kamori/jwt-svid-test-client:v1.0`）

**実施内容:**
- Multi-stage Dockerfileで公式SPIRE Agent RHEL9イメージからバイナリを抽出
- UBI9ベースイメージでRHEL9互換性を確保
- AMD64プラットフォーム指定（OpenShiftクラスター対応）
- spire-agentバイナリを`/usr/local/bin/spire-agent`に配置

**結果:**
- Pod再起動後も自動的に動作
- 手動インストールスクリプト不要
- GitOps完全自動化達成

**関連ファイル:**
- `test-workloads/docker/Dockerfile`
- `test-workloads/docker/README.md`
- `test-workloads/docker/build-and-push.sh`

---

---

## 元の改善提案（参考）

以下は当初の提案内容です。提案1と提案2は実施完了しました。

### 提案1: ClusterSPIFFEIDの修正（✅ 実施完了）

**問題**:
現在のClusterSPIFFEID `jwt-test-client`は使用されていません。

```yaml
# spire/base/clusterspiffeid.yaml (現在)
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: jwt-test-client
spec:
  spiffeIDTemplate: spiffe://{{ .TrustDomain }}/myclient  # 使用されていない
  podSelector:
    matchLabels:
      app: jwt-test-client
```

実際には、デフォルトのClusterSPIFFEID (`zero-trust-workload-identity-manager-spire-default`) が優先されています：

```yaml
# Operator管理のデフォルトClusterSPIFFEID
spiffeIDTemplate: spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}
```

**解決策A: ClusterSPIFFEIDを削除**

デフォルトテンプレートを明示的に使用する：

```yaml
# spire/base/kustomization.yamlから削除
resources:
  # - clusterspiffeid.yaml  # 削除
```

**解決策B: ClusterSPIFFEIDを正しいテンプレートに修正**

```yaml
# spire/base/clusterspiffeid.yaml (修正後)
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: jwt-test-client
spec:
  # デフォルトテンプレートと同じものを明示的に使用
  spiffeIDTemplate: spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}
  podSelector:
    matchLabels:
      app: jwt-test-client
  workloadSelectorTemplates:
    - k8s:ns:{{ .PodMeta.Namespace }}
    - k8s:sa:{{ .PodSpec.ServiceAccountName }}
    - k8s:pod-label:app:jwt-test-client
```

**推奨**: 解決策A（削除）。デフォルトテンプレートを使用することで、他のワークロードと一貫性が保たれます。

---

### 提案2: Keycloak config Jobの修正（✅ 実施完了）

**問題**:
`keycloak-config/base/configure-keycloak-job.yaml`が誤ったSPIFFE IDを設定しています。

```bash
# 現在のJob (抜粋)
/opt/keycloak/bin/kcadm.sh create clients -r spiffe \
  -s clientId=myclient \
  -s attributes."jwt.credential.sub"="spiffe://example.org/myclient"  # 誤り
```

**修正**:

```bash
# 修正後
/opt/keycloak/bin/kcadm.sh create clients -r spiffe \
  -s clientId=myclient \
  -s attributes."jwt.credential.sub"="spiffe://example.org/ns/rhbk-demo/sa/myclient"  # 正しい
```

または、環境変数を使用して動的に設定：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: configure-keycloak-v3
spec:
  template:
    spec:
      containers:
      - name: configure
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: SERVICE_ACCOUNT
          value: "myclient"
        - name: TRUST_DOMAIN
          value: "example.org"
        command:
        - /bin/bash
        - -c
        - |
          # SPIFFE ID を動的に構築
          SPIFFE_ID="spiffe://${TRUST_DOMAIN}/ns/${NAMESPACE}/sa/${SERVICE_ACCOUNT}"
          
          /opt/keycloak/bin/kcadm.sh create clients -r spiffe \
            -s clientId=myclient \
            -s attributes."jwt.credential.sub"="${SPIFFE_ID}"
```

---

### 提案3: spire-agent CLIの提供（⚠️ 未実装）

**Option A: カスタムイメージをビルド**

spire-agent CLIを含むカスタムイメージを作成：

```dockerfile
# Dockerfile
FROM cgr.dev/chainguard/wolfi-base:latest

# SPIRE Agent バイナリをコピー（別途ビルドまたはダウンロード）
COPY spire-agent /usr/local/bin/spire-agent
RUN chmod +x /usr/local/bin/spire-agent

CMD ["/bin/sh", "-c", "sleep infinity"]
```

```yaml
# test-workloads/base/jwt-test-client.yaml (修正後)
spec:
  containers:
  - name: client
    image: your-registry/jwt-test-client:latest  # カスタムイメージ
```

**メリット**: 完全にGitOps化
**デメリット**: カスタムイメージの管理が必要

**Option B: initContainerで動的抽出**

実行中のSPIRE Agent podからバイナリを抽出：

```yaml
# test-workloads/base/jwt-test-client.yaml (修正後)
spec:
  initContainers:
  - name: copy-spire-agent
    image: registry.redhat.io/ubi9/ubi-minimal:latest
    command:
    - sh
    - -c
    - |
      # SPIRE Agent podからバイナリをコピー
      # 注: これには追加のRBACが必要
      oc cp zero-trust-workload-identity-manager/spire-agent-xxx:/spire-agent /shared/spire-agent
      chmod +x /shared/spire-agent
    volumeMounts:
    - name: shared-bin
      mountPath: /shared
  containers:
  - name: client
    command: ["/bin/sh", "-c", "sleep infinity"]
    volumeMounts:
    - name: shared-bin
      mountPath: /usr/local/bin
    env:
    - name: PATH
      value: /usr/local/bin:/usr/bin:/bin
  volumes:
  - name: shared-bin
    emptyDir: {}
```

**メリット**: 最新のバイナリを自動取得
**デメリット**: 複雑、RBAC設定が必要

**Option C: 認証テストを別の方法で実施**

spire-agent CLIを使わない方法：

1. **gRPC Workload APIクライアント**: Goなどでクライアントを実装
2. **spiffe-helper**: SPIFFE Helperを使用（別ツール）
3. **テストをKeycloak側で実施**: Keycloakログで検証

**推奨**: Option A（カスタムイメージ）。最もシンプルで管理しやすい。

---

---

**最終更新:** 2026-06-27  
**関連ドキュメント:** [JWT-SVID-AUTHENTICATION-GUIDE.md](JWT-SVID-AUTHENTICATION-GUIDE.md)
