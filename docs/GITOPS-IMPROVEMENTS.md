# GitOps改善提案

現在のJWT-SVID認証テストには手動作業が必要です。このドキュメントでは、これらをGitOps化する改善案を提案します。

## 現在の手動作業

### 1. spire-agentバイナリのインストール
**現状**: `install-spire-agent-binary.sh`で手動インストール

**理由**: 
- Operator管理のSPIRE Agent imageにCLIツールが含まれていない
- initContainerでの抽出が失敗

### 2. Keycloak Client設定の修正
**現状**: `fix-keycloak-client-config.sh`で手動修正

**理由**:
- keycloak-config Jobが誤ったSPIFFE IDを設定している
- 設定値: `spiffe://example.org/myclient`
- 実際の値: `spiffe://example.org/ns/rhbk-demo/sa/myclient`

### 3. Keycloak Pod再起動
**現状**: 手動で`oc delete pod`

**理由**:
- 設定変更後のキャッシュクリアが必要

---

## 改善提案

### 提案1: ClusterSPIFFEIDの修正（推奨）

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

### 提案2: Keycloak config Jobの修正

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

### 提案3: spire-agent CLIの提供

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

## 実装優先度

### 高優先度（推奨）

✅ **提案1: ClusterSPIFFEIDの削除**
- 影響: 小
- 作業: `spire/base/kustomization.yaml`から1行削除
- 効果: 設定の一貫性向上

✅ **提案2: Keycloak config Jobの修正**
- 影響: 中
- 作業: `keycloak-config/base/configure-keycloak-job.yaml`を修正
- 効果: 手動作業（Step 2）が不要になる

### 中優先度

⚠️ **提案3: spire-agent CLIの提供**
- 影響: 中
- 作業: カスタムイメージのビルドとメンテナンス
- 効果: 手動作業（Step 1）が不要になる

---

## 実装後の手順

提案1と提案2を実装した場合、認証テストは以下のようになります：

### Before（現在）
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

### After（提案1+2実装後）
```bash
# Step 1: spire-agentバイナリをインストール（手動）
./scripts/install-spire-agent-binary.sh

# Step 2: 認証テスト実行
./scripts/test-jwt-svid-complete.sh
```

### After（提案1+2+3実装後）
```bash
# 認証テスト実行のみ
./scripts/test-jwt-svid-complete.sh
```

または、カスタムイメージにテストスクリプトを含めれば：
```bash
# Podの中で実行
oc exec jwt-test-client-xxx -n rhbk-demo -c client -- /opt/test-jwt-svid.sh
```

---

## まとめ

| 提案 | 作業量 | 効果 | 推奨度 |
|------|--------|------|--------|
| 1. ClusterSPIFFEID削除 | 小 | 設定一貫性向上 | ★★★ |
| 2. Keycloak Job修正 | 中 | Step 2不要 | ★★★ |
| 3. spire-agent CLI提供 | 大 | Step 1不要 | ★☆☆ |

**推奨実装順序**:
1. まず提案1と2を実装（手動作業を削減）
2. 必要に応じて提案3を検討（完全自動化）

---

**作成日:** 2026-06-27  
**関連ドキュメント:** [JWT-SVID-AUTHENTICATION-GUIDE.md](JWT-SVID-AUTHENTICATION-GUIDE.md)
