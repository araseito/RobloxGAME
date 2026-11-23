# Step ごとの報告

## Step 1：土台（2026-11-23）

### 1. 変更したファイル

| ファイル | 内容 |
| --- | --- |
| `default.project.json` | Rojo 設定。スクリプトの 3 フォルダだけを同期し、Studio 側の配置物には触れない |
| `wally.toml` | 依存なし |
| `.gitignore` | ビルド成果物などを除外 |
| `CLAUDE.md` | 進め方、禁止事項、コマンド |
| `docs/ERROR_LOG.md` | エラー記録（まだ記録なし） |
| `src/shared/Config.luau` | 数値をすべて集めた（仮の値） |
| `src/shared/*Defs.luau`（8 ファイル） | 能力 3、必殺技 3、ピース 9、モンスター 4、カード 6、レシピ 3、エリア 3、クエスト 3 の定義データ |
| `src/shared/Net.luau` | Remote の名前の一覧（Function 7、クライアントからのイベント 1、サーバーからのイベント 4） |
| `src/shared/Logic/ProfileSchema.luau` | 保存データの形、古いデータの補完、クライアントに見せる範囲 |
| `src/shared/Logic/SessionLock.luau` | セッションロックの判定 |
| `src/shared/Logic/InventoryLogic.luau` | カードとピースの増減の計算（不正な値の拒否、上限、全部成功か全部取りやめ） |
| `src/server/Main.server.luau` | サーバーの起動順と GetSnapshot の受け口 |
| `src/server/Remotes.luau` | Remote の受け口。レート制限と pcall。中身がまだない Remote には not_implemented を返す |
| `src/server/RateLimiter.luau` | プレイヤーごと・Remote ごとのレート制限 |
| `src/server/DataService.luau` | DataStore への保存、セッションロック、定期保存、退出時と終了時の保存 |
| `src/server/StateSync.luau` | 変わった部分をクライアントへ送る |
| `src/server/InventoryService.luau` | カードとピースの増減を受け持つ唯一の窓口 |
| `src/server/Metrics.luau` | AnalyticsService への計測（カスタムイベント 11、最初の 60 秒のファネル 4 段） |
| `src/server/DevTools.luau` | Studio 専用の開発コマンド（本番では作られない） |
| `src/client/Main.client.luau` / `StateStore.luau` / `HUD.luau` | 状態の受け取りと、仮の HUD（3×3 のボックスとカード一覧） |
| `tests/run.luau` | Lune で動かす単体テスト |

### 2. テスト結果

| 確認 | 結果 |
| --- | --- |
| 単体テスト（`lune run tests/run`） | **26 件すべて成功**。保存データの補完、セッションロック、カードの増減（不足・不正な値・上限・全部取りやめ）、ピースの増減、定義データの整合性（ピースの入手経路 9 つがすべて実在する先を指す、素材すべてに入手先がある、など） |
| Rojo のビルド（`rojo build`） | 成功 |
| 型チェック（luau-lsp） | **未実施**。このクラウド環境ではツールのダウンロードが許可されなかった。Studio のスクリプト解析で確認してほしい |
| Studio でのプレイテスト | **未実施**。このクラウド環境には Studio と Studio MCP がない |

### 3. 残っている仮置き

- 数値はすべて仮（`Config.luau`）
- 種別ごとのカード上限 20 は「種別の合計枚数」と解釈した（設計図の「種別ごとに上限 20」）
- 地名（ひだまり通り、こもれび里山、赤岩渓谷の洞）、必殺技とクエストの英語名、ピース名は仮
- Badge ID は 0（Step 3 までに差し替えが必要）
- Studio で DataStore が使えないときは、メモリ上の仮ストアに自動で切り替わる。その場合、テストサーバーを閉じるとデータは消える（警告が出力される）

### 4. 仕様と迷った点

- 計測の「再戦」は、負けてから 10 分以内にリングに再び参加したことと定義した（`Config.Ring.RematchWindowSeconds`）
- 公式の分析機能は、テスターが少ないと数字が表示されない可能性がある。Step 6 までに確かめる

### Studio でのプレイテスト手順（ダイスケさん用）

1. Studio で場所を開き、Game Settings → Security →「Enable Studio Access to API Services」をオンにする（場所が Roblox に公開済みであることが前提。非公開でよい）
2. プロジェクトのフォルダで `rojo serve` を実行し、Studio の Rojo プラグインから Connect する
3. Test → Clients and Servers で、プレイヤー 1 人でテストを始める
4. 出力に「[Server] Phase 0 起動完了」が出ること、画面の上に 3×3 のボックス（すべて「?」）、左下に「（カードなし）」が出ることを確認する
5. サーバー側のコマンドバーで次を実行し、画面の表示が変わることを確認する
   - `game.ServerStorage.DevTools:Invoke("give", "Player1", "leaf", 3)` → 左下に「葉 ×3」
   - `game.ServerStorage.DevTools:Invoke("piece", "Player1", "p01")` → 1 マス目が青く光って「!」
   - `game.ServerStorage.DevTools:Invoke("give", "Player1", "leaf", 30)` → 戻り値が false, category_full で、表示は変わらない
6. テストを終了し、もう一度テストを始める → 「葉 ×3」と 1 マス目が残っていれば、保存と読み込みが動いている
   - 出力に「メモリ上の仮ストア」という警告が出ている場合は、手順 1 の設定が効いていない
