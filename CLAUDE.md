# CLAUDE.md — パズルボックス Phase 0

仕様の正：`docs/PHASE0_PLAN_v2.md`（推奨どおり承認済み。⚠ の変更 5 つも採用、決闘リングは町の広場、賭けピースは自動選択）。
参照：`docs/blueprint.pdf`、`docs/PHASE0_PLAN_v1.md`。

## 進め方
- Step 単位で実装する。Step の終わりに Studio MCP でプレイテストし、`docs/STEP_REPORTS.md` に 4 点（変更ファイル／テスト結果／仮置き／迷った点）を書く
- 書く前に `docs/ERROR_LOG.md` を読み、同じ失敗を繰り返さない。新しいエラーはそこに追記する
- 仕様にない機能は足さない。迷ったら仮置きして報告する

## 絶対に守ること
- 持ち物・ピース・付与・ゲージ・戦闘状態はサーバー権威。クライアントからは ID だけを受け取り、数値は受け取らない
- ダメージは `CombatService`、カードとピースの増減は `InventoryService` だけを通す
- 決闘リングの対戦相手以外のプレイヤーには、ダメージ・ノックバック・剥がしを一切入れない（サーバーで弾く）
- 固有名詞・技名・モンスター名は自作だけを使う。Toolbox のモデルや外部スクリプトは入れない
- 呪文カード・トレード・課金・NFT・外部 URL は Phase 0 に入れない

## 構成
- `src/shared` → ReplicatedStorage.Shared（定義データと `Logic/` の純粋ロジック）
- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayerScripts.Client
- 地形と配置物は Studio 側で扱う（Rojo はスクリプトだけを同期）
- 数値はすべて `src/shared/Config.luau`
- Remote 名は `src/shared/Net.luau` 以外に書かない

## コマンド
- 単体テスト：`lune run tests/run`（`src/shared/Logic` と Defs の整合性）
- ビルド確認：`rojo build -o build.rbxl`
- Studio 同期：`rojo serve`

## `Logic/` のルール
`Logic/` のモジュールは `require` を使わない（Lune で直接読み込むため）。定義データは引数で渡す。
