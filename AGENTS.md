# AGENTS.md — パズルボックス Phase 0

仕様の正：`docs/PHASE0_PLAN_v2.md`（推奨どおり承認済み。⚠ の変更 5 つも採用、決闘リングは町の広場、賭けピースは自動選択）。
参照：`docs/blueprint.pdf`、`docs/PHASE0_PLAN_v1.md`。

## 進め方
- GitHub（origin）を正とする。作業の前に `git fetch` し、他（クラウドのセッションなど）から入った変更と、今のブランチの遅れ・未 push を確かめる。遅れていたら、取り込む前に利用者に伝える
- Step 単位で実装する。Step の終わりに Studio MCP でプレイテストし、`docs/STEP_REPORTS.md` に 4 点（変更ファイル／テスト結果／仮置き／迷った点）を書く
- 書く前に `docs/ERROR_LOG.md` を読み、同じ失敗を繰り返さない。新しいエラーはそこに追記する
- 仕様にない機能は足さない。迷ったら仮置きして報告する

## 絶対に守ること
- 持ち物・ピース・付与・ゲージ・戦闘状態はサーバー権威。クライアントからは ID だけを受け取り、数値は受け取らない
- ダメージは `CombatService`、カードとピースの増減は `InventoryService` だけを通す
- 決闘リングの対戦相手以外のプレイヤーには、ダメージ・ノックバック・剥がしを一切入れない（サーバーで弾く）
- 固有名詞・技名・モンスター名は自作だけを使う。Toolbox のモデルや外部スクリプトは入れない
- 呪文カード・トレード・課金・NFT・外部 URL は Phase 0 に入れない

## 共通の約束（Claude と Codex の両方が守る）
- このファイルと `AGENTS.md` は同じ中身にする（違うのは 1 行目の見出しだけ）。片方を直したら、もう片方も同じに直す。`lune run tests/run` で一致を確かめている
- 利用者への返答・途中経過・確認の質問・PR・Issue・docs は、すべて日本語で書く（コードの識別子やコマンドはそのまま）
- 1 回に変えるのは 1 つだけにして、変えるたびにプレイテストで確かめる。同じ不具合を 3 回直して直らなければ、深追いせずに動いていた 1 つ前の状態（git）に戻す
- 出力に出た赤いエラーは、利用者に貼ってもらえば直せると伝える
- マップ・看板・文言に、お酒を連想させるもの（居酒屋・酒樽・徳利・「酒」の字ののれんなど）を置かない。お酒の表現があると 18 歳以上限定になる。茶屋・甘味処・団子屋などにする
- ドロップ率などの確率は、抽選を `Logic/` の純粋関数にして乱数を引数で渡し、`tests/run.luau` で 10〜20 万回まわして確かめる
- 1 人で遊べる部分（モンスター・パズルボックス・クラフト）を後回しにしない。決闘リングだけを磨き込まない
- 放置で増える仕組み・時間で来るイベント・ゆるい対人・拠点での見せびらかしなどは Phase 1 の候補。提案はしてよいが、勝手に実装しない
- git は `core.autocrlf=input` にする（true だと LF のファイルがすべて変更ありに見える）

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
