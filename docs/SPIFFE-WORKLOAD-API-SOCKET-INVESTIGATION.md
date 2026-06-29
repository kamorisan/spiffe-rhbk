# SPIFFE Workload API Socketの調査方法

`/spiffe-workload-api/spire-agent.sock` がどこを指しているかを調べる方法を説明します。

## TL;DR

**エンドポイントは隠蔽されています。**

- アプリケーションからは `/spiffe-workload-api/spire-agent.sock` というパスでアクセス
- 実際の通信先は **同じNode上のSPIRE Agent DaemonSet Pod**
- **SPIFFE CSI Driver** が自動的にマウント・接続を管理
- アプリケーションはソケットの実体がどこにあるか知る必要がない

---

## 調査方法

### 方法1: Pod定義のVolumesを確認

```bash
CLIENT_POD=$(oc get pod -n rhbk-demo -l app=jwt-test-client --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')

# Volumes定義を確認
oc get pod $CLIENT_POD -n rhbk-demo -o jsonpath='{.spec.volumes}' | jq .

# VolumeMounts定義を確認
oc get pod $CLIENT_POD -n rhbk-demo -o jsonpath='{.spec.containers[0].volumeMounts}' | jq .
```

**出力例:**
```json
// Volumes
[
  {
    "csi": {
      "driver": "csi.spiffe.io",
      "readOnly": true
    },
    "name": "spiffe-workload-api"
  }
]

// VolumeMounts
[
  {
    "mountPath": "/spiffe-workload-api",
    "name": "spiffe-workload-api",
    "readOnly": true
  }
]
```

**重要なポイント:**
- `csi.driver: "csi.spiffe.io"` → **SPIFFE CSI Driver**が管理
- `mountPath: "/spiffe-workload-api"` → Podからはこのパスでアクセス
- 実際のソケットファイルは CSI Driver が自動的に配置

---

### 方法2: Pod内部で実際のマウント状態を確認

```bash
# マウントポイントを確認
oc exec $CLIENT_POD -n rhbk-demo -c client -- mount | grep spiffe

# ディレクトリの中身を確認
oc exec $CLIENT_POD -n rhbk-demo -c client -- ls -la /spiffe-workload-api/

# ソケットファイルの詳細を確認
oc exec $CLIENT_POD -n rhbk-demo -c client -- stat /spiffe-workload-api/spire-agent.sock
```

**出力例:**
```
# mount
tmpfs on /spiffe-workload-api type tmpfs (ro,seclabel,size=12889304k,mode=755)

# ls -la
total 0
drwxr-xr-x. 2 root       root 60 Jun 28 22:11 .
dr-xr-xr-x. 1 root       root 44 Jun 28 23:51 ..
srwxrwxrwx. 1 1000960000 root  0 Jun 28 22:11 spire-agent.sock

# stat
  File: /spiffe-workload-api/spire-agent.sock
  Size: 0         	Blocks: 0          IO Block: 4096   socket
Device: 18h/24d	Inode: 6160        Links: 1
Access: (0777/srwxrwxrwx)  Uid: (1000960000/ UNKNOWN)   Gid: (    0/    root)
```

**重要なポイント:**
- `tmpfs` → 一時ファイルシステム（メモリ上）
- `socket` タイプ → UNIXドメインソケット
- 実際の通信先はこのソケットを通じて**同じNode上のSPIRE Agent**

---

### 方法3: SPIRE Agent DaemonSetを確認

```bash
# SPIRE Agent DaemonSetの確認
oc get daemonset -n zero-trust-workload-identity-manager -l app.kubernetes.io/name=spire-agent

# jwt-test-clientと同じNode上のSPIRE Agent Podを特定
NODE=$(oc get pod $CLIENT_POD -n rhbk-demo -o jsonpath='{.spec.nodeName}')
echo "Node: $NODE"

SPIRE_AGENT_POD=$(oc get pod -n zero-trust-workload-identity-manager \
  -l app.kubernetes.io/name=spire-agent \
  --field-selector spec.nodeName=$NODE \
  -o jsonpath='{.items[0].metadata.name}')
echo "SPIRE Agent Pod: $SPIRE_AGENT_POD"
```

**出力例:**
```
Node: ip-10-0-31-21.us-east-2.compute.internal
SPIRE Agent Pod: spire-agent-2xz7h
```

**重要なポイント:**
- SPIRE AgentはDaemonSet → **各Nodeに1つずつ**配置
- アプリケーションPodと**同じNode上のSPIRE Agent**と通信
- クロスNode通信は発生しない（ローカルUNIXソケット）

---

### 方法4: SPIRE AgentのSocket配置場所を確認

```bash
# SPIRE Agent Podのvolume定義を確認
oc get pod $SPIRE_AGENT_POD -n zero-trust-workload-identity-manager \
  -o jsonpath='{.spec.volumes}' | jq '.[] | select(.name | contains("socket"))'

# SPIRE Agent PodのvolumeMountsを確認
oc get pod $SPIRE_AGENT_POD -n zero-trust-workload-identity-manager \
  -o jsonpath='{.spec.containers[0].volumeMounts}' | jq '.[] | select(.name | contains("socket"))'
```

**出力例:**
```json
// Volumes
{
  "hostPath": {
    "path": "/run/spire/agent-sockets",
    "type": "DirectoryOrCreate"
  },
  "name": "spire-agent-socket-dir"
}

// VolumeMounts
{
  "mountPath": "/tmp/spire-agent/public",
  "name": "spire-agent-socket-dir"
}
```

**重要なポイント:**
- `hostPath: "/run/spire/agent-sockets"` → **Node上の実際のパス**
- SPIRE Agentはこのディレクトリにソケットを作成
- SPIFFE CSI Driverがこのソケットをアプリケーションに接続

---

### 方法5: SPIFFE CSI Driver Podを確認

```bash
# CSI Driver Podの確認
oc get pod -n zero-trust-workload-identity-manager | grep spiffe-csi-driver

# 同じNode上のCSI Driver Podを特定
CSI_DRIVER_POD=$(oc get pod -n zero-trust-workload-identity-manager \
  -l app.kubernetes.io/name=spiffe-csi-driver \
  --field-selector spec.nodeName=$NODE \
  -o jsonpath='{.items[0].metadata.name}')
echo "CSI Driver Pod: $CSI_DRIVER_POD"
```

**出力例:**
```
CSI Driver Pod: spire-spiffe-csi-driver-4twt2
```

---

## アーキテクチャ図

```
┌─────────────────────────────────────────────────────────────┐
│ Node: ip-10-0-31-21.us-east-2.compute.internal             │
│                                                             │
│  ┌───────────────────────────────────────────────────┐     │
│  │ jwt-test-client Pod (rhbk-demo namespace)        │     │
│  │                                                   │     │
│  │  ┌─────────────────────────────────────────┐     │     │
│  │  │ Container: client                        │     │     │
│  │  │                                          │     │     │
│  │  │  /spiffe-workload-api/                  │     │     │
│  │  │    └── spire-agent.sock (tmpfs mount)   │     │     │
│  │  │          ↓                               │     │     │
│  │  │      UNIXソケット通信                     │     │     │
│  │  └──────────────────────────────────────────┘     │     │
│  └───────────────────────────────────────────────────┘     │
│                       ↓                                     │
│  ┌───────────────────────────────────────────────────┐     │
│  │ SPIFFE CSI Driver Pod (DaemonSet)                │     │
│  │  - CSI Driver が自動的にソケット接続を管理         │     │
│  └───────────────────────────────────────────────────┘     │
│                       ↓                                     │
│  ┌───────────────────────────────────────────────────┐     │
│  │ SPIRE Agent Pod (DaemonSet)                      │     │
│  │                                                   │     │
│  │  /tmp/spire-agent/public/                        │     │
│  │    └── spire-agent.sock                          │     │
│  │         ↑                                         │     │
│  │         │ (実際のソケットファイル)                 │     │
│  └─────────┼─────────────────────────────────────────┘     │
│            │                                               │
│  ┌─────────┴─────────────────────────────────────────┐     │
│  │ Node hostPath                                     │     │
│  │  /run/spire/agent-sockets/                        │     │
│  └───────────────────────────────────────────────────┘     │
│                       ↓                                     │
│                   gRPC (mTLS)                              │
└─────────────────────────┼──────────────────────────────────┘
                          ↓
         ┌────────────────────────────────────────┐
         │ SPIRE Server (Deployment)             │
         │ Namespace: zero-trust-workload-       │
         │            identity-manager           │
         └────────────────────────────────────────┘
```

---

## 重要なポイント

### 1. エンドポイントは隠蔽されている

✅ **アプリケーション視点:**
- `/spiffe-workload-api/spire-agent.sock` にアクセス
- 実際の通信先は知る必要がない
- SPIFFE CSI Driverが自動管理

✅ **実際の通信経路:**
- 同じNode上のSPIRE Agent DaemonSet Pod
- UNIXドメインソケット（ローカル通信）
- クロスNode通信は発生しない

### 2. CSI Driverの役割

SPIFFE CSI Driverが以下を自動的に処理：

1. **ソケットファイルのマウント**
   - Podに `/spiffe-workload-api` ディレクトリをマウント
   - SPIRE Agentのソケットを接続

2. **アクセス制御**
   - Pod単位でWorkload APIへのアクセスを管理
   - セキュリティポリシーの適用

3. **ライフサイクル管理**
   - Pod作成時に自動マウント
   - Pod削除時に自動クリーンアップ

### 3. 従来のhostPathマウントとの違い

**SPIFFE CSI Driver（現在）:**
```yaml
volumes:
- name: spiffe-workload-api
  csi:
    driver: csi.spiffe.io
    readOnly: true
```
- ✅ Kubernetes標準のCSI
- ✅ セキュリティポリシー適用可能
- ✅ 自動管理
- ✅ Pod単位のアクセス制御

**hostPath（レガシー）:**
```yaml
volumes:
- name: spiffe-workload-api
  hostPath:
    path: /run/spire/sockets
    type: Directory
```
- ❌ Node全体のパスを露出
- ❌ セキュリティリスク
- ❌ 手動管理が必要

---

## まとめ

### 質問: `/spiffe-workload-api/spire-agent.sock` がどこを指しているか？

**回答:**

1. **Pod内部のパス**: `/spiffe-workload-api/spire-agent.sock` (tmpfs mount)
2. **実際の通信先**: 同じNode上のSPIRE Agent Pod (`/tmp/spire-agent/public/spire-agent.sock`)
3. **Node上のパス**: `/run/spire/agent-sockets/`（hostPath）
4. **最終的な通信先**: SPIRE Server (gRPC over mTLS)

### 質問: エンドポイントは隠蔽されている？

**回答: YES**

- **アプリケーションから見える部分**: `/spiffe-workload-api/spire-agent.sock`
- **実際の通信経路**: SPIFFE CSI Driverが自動管理（アプリケーションは意識不要）
- **セキュリティ**: 最小権限の原則（アプリケーションはローカルソケットのみアクセス）
- **抽象化**: Kubernetesの標準CSI機構による隠蔽化

この設計により、アプリケーションは**SPIFFE Workload API**という抽象化されたインターフェースのみを意識すれば良く、インフラストラクチャの詳細（ソケットの実体、SPIRE Agentの配置、通信経路）を知る必要がありません。
