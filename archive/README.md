# Archive

このディレクトリには、開発・検証過程で使用したが、最終的には不要になったファイルが保存されています。

## アーカイブされたスクリプト (scripts/)

### test-jwt-svid-auth.sh
- **理由**: `test-jwt-svid-complete.sh`に統合されました
- **状態**: 初期バージョンの認証テストスクリプト
- **参考**: 完全版は`../scripts/test-jwt-svid-complete.sh`を使用してください

### enable-keycloak-trace-logging.sh
- **理由**: デバッグ用スクリプト（本番環境では不要）
- **状態**: `kcadm.sh set-log-level`コマンドがRHBK 26.6.4に存在せず動作しませんでした
- **参考**: Keycloakログは標準のoc logsコマンドで確認できます

### fix-spiffe-idp-endpoint.sh
- **理由**: Bundle Endpointは既に正しく設定されており、修正不要でした
- **状態**: 検証用に作成したが実際には使用しませんでした
- **参考**: Bundle Endpointは`keycloak-config`で正しく設定されています

## アーカイブされたドキュメント (docs/)

### manual-test-procedure.md
- **理由**: 新しい[JWT-SVID-AUTHENTICATION-GUIDE.md](../docs/JWT-SVID-AUTHENTICATION-GUIDE.md)に統合されました
- **状態**: 古い手動テスト手順（情報が不完全）
- **参考**: 最新の完全なガイドは`../docs/JWT-SVID-AUTHENTICATION-GUIDE.md`を使用してください

## アーカイブされた図 (images/)

### auth-flow.mmd / auth-flow.svg (v1統合図)
- **アーカイブ日:** 2026-06-29
- **理由**: 実測値ベースのv2図に置き換えられました
- **内容**: 初期バージョンの認証フロー図（推測値含む）
- **代替**: `../images/auth-flow-v2.svg`（実測値ベース）を使用

**v1とv2の主な違い:**
- v1: 推測値や仮説ベースの構成
- v2: 実際の成功ログから取得した実測値
- v2: `client_id`送信不要を明記
- v2: 公開鍵取得先をSPIRE Server Bundle Endpointと明示

### auth-flow-step1.mmd / auth-flow-step1.svg
- **アーカイブ日:** 2026-06-29
- **理由**: v2統合認証フロー図に統合されました
- **内容**: Step 1（JWT-SVID取得）のみの詳細フロー図
- **代替**: `../images/auth-flow-v2.svg`が完全なフローを含みます

### auth-flow-step2-4.mmd / auth-flow-step2-4.svg
- **アーカイブ日:** 2026-06-29
- **理由**: v2統合認証フロー図に統合されました
- **内容**: Step 2-4（Keycloak認証）のみの詳細フロー図
- **代替**: `../images/auth-flow-v2.svg`が完全なフローを含みます

**保持理由:**
- ステップ別の詳細説明が必要な場合の参考資料
- 教育・トレーニング用途での利用可能性
- 設計・検証過程の履歴として保存

## 現在使用中のファイル

### スクリプト (../scripts/)
1. `test-jwt-svid-complete.sh` - 完全な認証テスト（1ステップのみ）

**廃止されたスクリプト:**
- `install-spire-agent-binary.sh` → `../deprecated/scripts/`（カスタムイメージ導入により不要）
- `fix-keycloak-client-config.sh` → `../deprecated/scripts/`（GitOps自動化により不要）

### ドキュメント (../docs/)
1. `JWT-SVID-AUTHENTICATION-GUIDE.md` - 認証テスト完全ガイド（メイン）
2. `GITOPS-IMPROVEMENTS.md` - GitOps改善履歴
3. `design/rhbk_spiffe_gitops_environment_guidelines.md` - GitOps環境設計ガイドライン
4. `report/` - 過去の成功レポート（参考資料）

### 図 (../images/)
1. `architecture.svg` - システムアーキテクチャ図
2. `auth-flow-v2.svg` - JWT-SVID認証フロー図（推奨版・実測値ベース）
3. `auth-flow.svg` - JWT-SVID認証フロー図（v1・参考用）

---

**最終更新日:** 2026-06-29  
**理由:** コードベースの整理とメンテナンス性向上、GitOps完全自動化達成
