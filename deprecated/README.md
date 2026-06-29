# Deprecated Scripts and Documentation

このディレクトリには、GitOps改善により不要になったスクリプトとドキュメントが含まれています。

## 廃止されたスクリプト

### scripts/fix-keycloak-client-config.sh

**廃止日:** 2026-06-27

**理由:** 
- configure-keycloak-v3 Jobによる完全自動化
- GitOps App-of-Appsデプロイ時に正しい設定が自動適用される
- 手動修正が不要

**関連改善:**
- Keycloak Client SPIFFE ID自動設定
- Bundle Endpoint自動設定
- デフォルトClusterSPIFFEID使用

---

### scripts/install-spire-agent-binary.sh

**廃止日:** 2026-06-29

**理由:**
- カスタムコンテナイメージ（`quay.io/kamori/jwt-svid-test-client:v1.0`）導入
- spire-agentバイナリが事前組み込み済み（`/usr/local/bin/spire-agent`）
- Pod再起動後も自動的に動作
- `oc cp`によるバイナリ破損問題を解決

**関連改善:**
- Multi-stage Dockerfileで公式SPIRE Agent RHEL9イメージからバイナリ抽出
- UBI9ベースでRHEL9完全互換
- AMD64プラットフォーム対応

**代替手段:**
- テスト実行: `./scripts/test-jwt-svid-complete.sh`（1ステップのみ）

---

## 保持理由

これらのファイルは以下の理由で削除せず保持しています：

1. **履歴参照**: 過去の実装方法を理解するための参考資料
2. **トラブルシューティング**: 問題発生時の調査用
3. **ロールバック**: 緊急時の一時的な回避策として利用可能

## 現在の推奨手順

GitOps完全自動化により、手動作業は以下の1ステップのみ：

```bash
# JWT-SVID認証テスト実行
./scripts/test-jwt-svid-complete.sh
```

詳細は [JWT-SVID Authentication Guide](../docs/JWT-SVID-AUTHENTICATION-GUIDE.md) を参照してください。
