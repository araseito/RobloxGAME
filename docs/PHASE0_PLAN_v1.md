# Phase 0 実装計画（Step 0：承認待ち）

- 仕様の正：「Claude Code 実装指示書 Phase 0」（以下「指示書」）
- 参照：`docs/blueprint.pdf`「パズルボックス設計図 改訂版」（以下「設計図」）
- 状態：**承認待ち。コードは 1 行も書いていません。**

---

## 0. 作業環境についての報告（先に確認が必要）

| 項目 | 状況 | 提案 |
| --- | --- | --- |
| Roblox Studio / Studio MCP | この作業はクラウドのコンテナで動いており、Studio も Studio MCP もありません。**ここではプレイテストできません** | Step 1 以降は、ダイスケさんの PC 上の Claude Code（Studio MCP が接続できる環境）で進めるのが確実です。このセッションで続ける場合は「ここでコードを書いて GitHub に push → PC 側で Rojo 同期してプレイテスト」の往復になります |
| フォルダ | 作業フォルダは空で、git 管理もまだありません。過去のエラー事例もありません | Step 1 で git 初期化と `CLAUDE.md` 作成を行います |
| Rojo と Argon | どちらも「ファイル → Studio」の同期ツールで、同時に使うと上書き競合します | **Rojo のみ**を使います。Argon は入れません |
| Wally | Phase 0 では外部ライブラリを入れない方針です（出所確認の手間とリスクを避けるため） | `wally.toml` は置くが依存は空。セッションロックも自作の最小実装にします |
| DataStore / Badge | Studio で DataStore を使うには、場所を（非公開で）Roblox に公開し「Studio から API サービスへのアクセス」を有効化する必要があります。Badge は ダイスケさんが Creator Hub で作成し、Badge ID を渡してもらう必要があります | Step 1 開始前にダイスケさんに設定してもらいます。Badge ID は Step 3 までに |

---

## 1. 指示書と設計図の食い違い（判断をお願いしたい点）

指示書を正としつつ、設計図の方が具体的な箇所は設計図で埋める方針です。ただし、下の 9 点は両者が矛盾しているか、どちらにも書いていないので、**勝手に決めずに確認します**。各行の「推奨」で良ければ「推奨どおり」とだけ返してください。

| # | 論点 | 指示書 | 設計図 | 推奨 |
| --- | --- | --- | --- | --- |
| A | 能力 3 種の中身 | 付与型 1 種＋単純攻撃 2 種 | 疾風付与・剛力付与・鉄壁付与（3 種すべて付与型） | **設計図の付与 3 種**を能力とし、「単純攻撃」は全員共通の通常攻撃として別に持たせる。必殺技が「自分の付与を消費して撃つ」ので、能力が付与型でないと必殺技と結びつかないため。プレイヤーは 3 種すべてを持ち、選択中の能力の必殺技を撃つ |
| B | モンスターの数 | 3 種（うち 1 体がボス格） | 通常 3 種＋ボス 1 種（完成の定義でも「図鑑 4 種」） | **通常 3＋ボス 1 の 4 体**。3 体だとクラフト素材（葉・枝・牙・羽）の入手先が足りず、レシピ 3 種の素材がそろわないため |
| C | 呪文 6 種の内訳 | 移動 2・奪取 1・防御 1・情報 1・その他 1 | 移動 2（帰還の翼・追跡の翼）・罠 1（茨の結界）・強化 1（炎剣の加護）・防御 1（奪取封じ）・妨害 1（霧隠れ） | 下の D とセットで決める必要があります。推奨は **設計図の 6 種**。「奪取」はカードではなく宣言バトルの結果として扱う（設計図の考え方）。指示書の「呪文の在庫があるときだけ奪取できる」は「1 日の宣言回数」で代替 |
| D | 奪取の流れ | 奪取の宣言 → 相手に通知 → 防御呪文を切る猶予 → 成立。宣言が戦闘状態の開始 | 宣言 → 相手が承諾したときだけ対人戦 → 勝者が相手の**未装着ピース**を 1 つ奪う。断れば何も起きない | **両方を合わせる**：宣言 → 相手に通知（猶予 15 秒）→ 承諾で戦闘開始／拒否・無応答なら何も起きない → 勝者が敗者の未装着ピースを 1 つ奪う。猶予中か戦闘中に「奪取封じ」を使えば、負けても奪われない。1 日回数・24 時間免疫・図鑑差制限・町では宣言不可は指示書どおり入れる。**※懸念**：断るのに代価がないと、誰も承諾しない可能性があります。これは検証で見るべき点として残します（仕組みは足しません） |
| E | ピースを「はめる」工程 | 記載なし（持っていれば絵が見える） | 取得 → 町でボックスにはめる。はめたピースは奪われない | **設計図どおり採用**。D の「未装着ピースだけ奪える」に必要なため。UI は「はめた＝絵」「持っているが未装着＝光るシルエット」「未所持＝暗いシルエット」の 3 状態 |
| F | モンスター戦の戦闘状態 | モンスター戦は対人ルールの対象外 | モンスターに攻撃した／されたとき戦闘状態に入る。必殺技は戦闘状態のときだけ撃てる | **両方採用**。戦闘状態を「対モンスター（PvE）」と「対人（PvP）」に分けて管理し、プレイヤーへのダメージは PvP 戦闘状態の相手同士の間でのみ通す |
| G | エリア構成 | 町・自然フィールド・小ダンジョンの 3 つ | 町・里山フィールド・渓谷ダンジョン。ただしサンドホーンは「渓谷フィールド」（Phase 0 に存在しない）に棲む | **町・里山フィールド・渓谷ダンジョン**。サンドホーンは渓谷ダンジョンの入口側に置く。アオハネは里山の上空 |
| H | 他者への付与 | 記載なし | 自分＋他者 1 名まで。照準先は自分／味方／敵／装備カード | Phase 0 は「自分・装備カード・他プレイヤー 1 名」に付与可。**他プレイヤーへの付与（強化を渡すだけ）は戦闘状態でなくても可**、**他人の付与を剥がすのは PvP 戦闘状態の相手だけ**。敵（モンスター）への付与は入れない |
| I | サービス名 | `BattleStateService` `GrantService` `PuzzleBoxService` 等 | `CombatStateService` `AbilityService` `PieceService` 等 | **指示書の名前**を使う |

---

## 2. 仮置きする数値（すべて `shared/Config` 系の定義ファイルに集約）

| 区分 | 項目 | 仮の値 | 出典 |
| --- | --- | --- | --- |
| 付与 | 総量上限 | 10 | 設計図 |
| 付与 | 疾風／剛力／鉄壁のコスト・効果 | 3 / 移動 +30%、4 / 攻撃 +25%、4 / 被ダメ −25% | 設計図 |
| 付与 | 解除後の再付与不可 | 5 秒 | 設計図 |
| 付与 | 他人の付与を剥がす代価 | 自分の付与を 1 つ失う（最もコストの低いもの。仮） | 設計図＋仮 |
| 必殺技 | ゲージ | 0〜100。与ダメ +1/10dmg、被ダメ +1/10dmg、付与 +8、解除 +5、剥がし +12、モンスター撃破 +15。戦闘終了で 0 | 設計図＋配分は仮 |
| 必殺技 | 威力 | 基礎威力＋消費した付与コスト合計 × 倍率（基礎 30、倍率 8。仮） | 設計図＋仮 |
| 必殺技 | 詠唱 | 1.2 秒。詠唱中に剥がされると消費コストが減り威力低下（中断はしない） | 設計図 |
| 必殺技 | 対人ダメージ上限 | 最大 HP の 35%（仮）。モンスターには上限なし | 設計図＋仮 |
| 戦闘 | 最大 HP / 通常攻撃 | 100 / 10 ダメージ、間隔 0.6 秒、射程 8 stud（仮） | 仮 |
| 戦闘状態 | 終了条件 | どちらかの HP 0、相手から 80 stud 以上離れて 10 秒、60 秒無攻撃、エリア移動、帰還の翼使用 | 指示書＋仮 |
| 戦闘状態 | 終了後 | 敗北者は 10 秒戦闘不可、同じ相手への再宣言は 300 秒不可 | 設計図＋仮 |
| 奪取 | 1 日の宣言回数 | 3 回（UTC 日付で区切る） | 指示書＋仮 |
| 奪取 | 免疫 | 奪われた側に 24 時間 | 指示書 |
| 奪取 | 図鑑差制限 | 「はめたピース数」の差が 3 以上なら宣言不可（仮） | 指示書＋仮 |
| 奪取 | 宣言の猶予 | 15 秒 | 仮 |
| カード | 所持上限 | 種別ごとに 20 枚 | 設計図 |
| カード | 戦闘中に使える呪文 | 1 戦闘 2 枚まで | 設計図 |
| 装備 | 枠 | 武器 1・防具 1。各カードに付与スロット 1 | 設計図 |
| 死亡 | 戦闘不能時 | 町へ戻される。カード・ピースは失わない（宣言バトルの敗北時の奪取を除く） | 仮 |

---

## 3. ファイル構成

```text
project/
  CLAUDE.md                     # 指示書の要約・禁止事項・進め方
  default.project.json          # Rojo 設定（スクリプトだけを同期。地形・配置物は Studio 側）
  wally.toml                    # 依存なし
  docs/
    blueprint.pdf
    PHASE0_PLAN.md              # この計画
    STEP_REPORTS.md             # 各 Step の報告（変更ファイル／テスト結果／仮置き／迷った点）
  src/
    shared/                     # ReplicatedStorage.Shared
      Config.luau               # 全数値（上の表）を 1 か所に
      AbilityDefs.luau          # 能力 3 種
      UltimateDefs.luau         # 必殺技 3 種
      PieceDefs.luau            # ピース 9 個と入手経路
      SpellDefs.luau            # 呪文 6 種
      MaterialDefs.luau         # 素材カード（葉・枝・牙・布・羽・薬草）※指示書の構成に追加
      GearDefs.luau             # 武器・防具・アイテムカード
      RecipeDefs.luau           # レシピ 3 種
      MonsterDefs.luau          # モンスター 4 体
      AreaDefs.luau             # エリア 3 つ（解放条件・接続先）
      QuestDefs.luau            # クエスト 3〜5 本 ※追加
      Net.luau                  # Remote 名の一覧と引数の型定義（ここ以外で Remote 名を書かない）
      Logic/                    # Roblox API に依存しない純粋ロジック（単体テスト可能）
        GrantLogic.luau         # 上限計算・配分・解除可否
        UltimateLogic.luau      # ゲージ増減・威力計算
        StealLogic.luau         # 宣言可否（回数・免疫・図鑑差・セーフゾーン）
        CraftLogic.luau         # レシピ充足判定
        PuzzleLogic.luau        # 完成判定
    server/                     # ServerScriptService.Server
      Main.server.luau          # 起動順の制御だけ
      DataService.luau          # DataStore 読み書き・セッションロック・自動保存
      MetricsService.luau       # 計測ログ
      InventoryService.luau     # カード増減の唯一の窓口（原子的な消費・付与）※追加
      BattleStateService.luau   # PvE / PvP 戦闘状態、対人攻撃の可否
      CombatService.luau        # ダメージ・ノックバック・剥奪の唯一の窓口 ※追加
      GrantService.luau         # 付与／解除
      UltimateService.luau      # 必殺技ゲージ・詠唱・発動
      PuzzleBoxService.luau     # ピース取得・はめる・完成・Badge・称号・引き換えコード
      SpellService.luau         # 呪文使用・宣言バトル（奪取）
      TravelService.luau        # 選択式移動
      MonsterService.luau       # 出現・AI・撃破・ドロップ・図鑑
      CraftService.luau         # ワンタップ合成
      QuestService.luau         # NPC 会話・クエスト受付／報告 ※追加
      ExploreService.luau       # 探索の隠し場所（日替わり再配置）※追加
    client/                     # StarterPlayerScripts.Client
      Main.client.luau
      StateStore.luau           # サーバーから届いた状態の受け皿（表示専用）
      InputController.luau      # 付与・解除・攻撃・必殺技ボタン
      PuzzleBoxUI.luau
      GrantUI.luau              # 配分表示・必殺技ゲージ
      UltimateFx.luau           # 技名表示とカットイン（自分以外の発動も表示）
      SpellUI.luau
      TravelUI.luau
      MonsterDexUI.luau
      CraftUI.luau
      BattleUI.luau             # 宣言の通知・承諾／拒否
      QuestUI.luau
  tests/                        # Lune で動かす Logic/ の単体テスト
```

**追加した理由**：`CombatService` と `InventoryService` は、「対人攻撃の無効化」と「カードの二重消費・複製防止」を 1 か所でしか通らない窓口に集めるためです。ダメージやカード増減を各サービスに散らすと、どこかで検証漏れが起きます。`MaterialDefs` `QuestDefs` `QuestService` `ExploreService` は指示書の範囲（素材カード・クエスト・探索）を置く場所がなかったため追加しました。

---

## 4. データ構造

### 4.1 保存するデータ（DataStore `PlayerData_v1`、キー `u_<UserId>`）

```lua
{
  schema = 1,
  lock = { jobId = "...", at = 1732300000 },     -- セッションロック
  pieces = {
    owned  = { ["p01"] = { at = 1732300000 } },   -- 持っているが未装着（奪取対象）
    placed = { ["p01"] = { at = 1732300000 } },   -- はめた（奪取されない）
    dex    = { ["p01"] = true },                  -- 一度でも入手した記録（奪われても残る）
    completedAt = nil, redeemCode = nil,
  },
  cards = {                                       -- 種別ごとの枚数
    spell    = { travel_home = 1 },
    material = { twig = 2 },
    item     = { potion = 0 },
  },
  gear = {                                        -- 武器・防具は個体ごとに管理（付与スロットがあるため）
    instances = { ["g_8f3a"] = { def = "wooden_blade", createdAt = 1732300000 } },
    equipped  = { weapon = "g_8f3a", armor = nil },
  },
  monsterDex = { moripon = { seen = true, kills = 3 } },
  titles = { "box_complete_p0" }, activeTitle = nil,
  areas = { unlocked = { town = true, satoyama = true } },
  quests = { ["q01"] = { state = "done" } },
  steal = { dayKey = "2026-11-23", declaredToday = 1, immuneUntil = 0, lastByTarget = {} },
  metricsId = "a1b2c3...",                         -- ランダムな仮名 ID（UserId は計測に使わない）
}
```

保存しないもの（サーバーのメモリだけ）：付与の状態、必殺技ゲージ、戦闘状態、HP。設計図どおりです。

### 4.2 サーバー内の実行時状態

```lua
grants[player] = {
  used = 7,                                       -- 総量上限 10 に対する使用量
  list = { { id, ability, cost, target = {kind="self"|"player"|"gear", ref} } },
  releaseCooldownUntil = 0,
}
ultimate[player] = { gauge = 0..100, castingUntil = nil }
battle[player] = { kind = "none"|"pve"|"pvp", opponent = Player?, startedAt, lastHitAt, spellsUsed = 0 }
```

---

## 5. Remote 一覧

すべて `ReplicatedStorage.Net` フォルダに置き、名前は `Net.luau` でだけ定義します。**すべての受信で、型チェック・回数制限（1 秒あたりの上限）・サーバー側の再検証を行います。** クライアントからは「やりたいこと」と ID だけを受け取り、数値（ダメージ・コスト・枚数）は一切受け取りません。

### クライアント → サーバー

| 名前 | 種類 | 引数 | サーバーの検証 |
| --- | --- | --- | --- |
| `GetSnapshot` | RemoteFunction | なし | 自分の状態だけ返す |
| `Grant_Apply` | RemoteFunction | abilityId, target（self / gearInstanceId / Player） | 上限、クールダウン、対象の妥当性、他者 1 名まで |
| `Grant_Release` | RemoteFunction | grantId または "all" | 自分が付けた付与か |
| `Grant_Strip` | RemoteFunction | 相手 Player, grantId | **PvP 戦闘状態の相手か**、代価の付与があるか |
| `Attack_Basic` | RemoteEvent | 対象（Model） | 射程・間隔・戦闘可否（`CombatService` 経由） |
| `Ultimate_Cast` | RemoteFunction | 対象（任意） | ゲージ 100、戦闘状態、詠唱中でない |
| `Ability_Select` | RemoteEvent | abilityId | 定義に存在するか（必殺技の種類を決める） |
| `Gear_Equip` / `Gear_Unequip` | RemoteFunction | gearInstanceId / slot | 所持しているか、種別が合うか |
| `Item_Use` | RemoteFunction | itemId | 所持、戦闘状態のみ使用可（回復薬） |
| `Spell_Use` | RemoteFunction | spellId, 引数 | 所持、使用条件、1 戦闘 2 枚まで |
| `Battle_Declare` | RemoteFunction | 相手 Player | 町でない、回数、免疫、図鑑差、再宣言不可時間 |
| `Battle_Respond` | RemoteFunction | declareId, accept | 宣言の宛先本人か、猶予内か |
| `Piece_Place` | RemoteFunction | pieceId | 町にいるか、未装着で所持しているか |
| `Travel_Request` | RemoteFunction | areaId | 解放済みか、戦闘中でないか |
| `Craft_ViewOpened` | RemoteEvent | なし | 計測用（開いたが合成しなかった回数） |
| `Craft_Execute` | RemoteFunction | recipeId | 直前に所持を再確認 → 原子的に消費・付与 |
| `Quest_Accept` / `Quest_TurnIn` | RemoteFunction | questId | NPC の近くにいるか、条件達成 |

探索の拾得・NPC との会話開始は `ProximityPrompt`（サーバー側で発火を受け取る）で行い、Remote を使いません。

### サーバー → クライアント

| 名前 | 種類 | 内容 |
| --- | --- | --- |
| `State_Delta` | RemoteEvent | 自分の状態の差分（カード・ピース・付与・ゲージ・図鑑） |
| `Battle_Notify` | RemoteEvent | 宣言が届いた／戦闘開始／終了 |
| `Ultimate_Broadcast` | RemoteEvent（全員） | 誰が何の必殺技を撃ったか（技名表示とカットイン。同居しているので他人の演出も見える） |
| `Puzzle_Completed` | RemoteEvent | 完成演出・称号・引き換えコード |
| `Toast` | RemoteEvent | 拒否理由などの短い通知 |

---

## 6. 守り方の方針（不正・バグ対策）

1. **対人攻撃の無効化は `CombatService` の 1 か所で判定**：通常攻撃・必殺技・罠・剥奪は、プレイヤーに効果を及ぼす前に必ず `BattleStateService:CanAffect(attacker, victim)` を通します。HP の書き換えはサーバーだけが行います。
2. **カードの増減は `InventoryService` の 1 か所**：消費は「全部そろっているか確認 → 全部減らす → 成果物を足す」を待ち（yield）なしで一気に行い、途中で他の処理が割り込めないようにします。合成の連打は処理中フラグで弾きます。
3. **セッションロック**：読み込み時に `UpdateAsync` でロックを取り、別サーバーがロック中なら少し待ってから再試行、期限切れなら奪います。保存は定期（60 秒）＋退出時＋サーバー終了時（`BindToClose`）。
4. **Toolbox のモデル・外部スクリプトは使わない**。見た目は単純な Part で組みます。

---

## 7. 計測ログの形式（Step 1 で固定）

DataStore `Metrics_v1` にセッション単位で 1 件保存。個人を特定しないよう、UserId ではなくプロフィール内のランダムな `metricsId` を使います。

```lua
{
  v = 1, mid = "a1b2c3...", sessionId = "...", start = 1732300000, ["end"] = 1732301800,
  counters = {
    piecesGained = 0, completed = false,
    stealDone = 0, stealTaken = 0, rematchAfterSteal = 0,
    ultimateCast = 0, monsterKills = 0,
    craftExecuted = 0, craftOpenedNoCraft = 0,
  },
  events = { { t = 120, e = "steal_taken", by = "<相手の mid>" } },  -- 上限 200 件
}
```

「奪われた後の再戦」は、奪われた側が 30 分以内に同じ相手、または誰かに宣言・承諾したら 1 と数えます（仮）。出力は Step 6 で、Open Cloud の DataStore API か Studio のコマンドで CSV にします。

---

## 8. テストの進め方

- **単体テスト**：`shared/Logic/` の純粋ロジックを Lune で実行します（Studio がなくても動くので、このクラウド環境でも確認できます）。
- **プレイテスト**：各 Step の終わりに Studio MCP で 2 人以上のローカルサーバーを起動して確認します。**毎回必ず含める確認**：戦闘状態でない相手に、通常攻撃・必殺技・罠・剥奪を当ててもダメージ 0・ノックバックなし・付与が残ること。
- 報告は `docs/STEP_REPORTS.md` に「変更したファイル／プレイテスト結果／残っている仮置き／仕様と迷った点」の 4 点で残します。

---

## 9. Step ごとの作業範囲

| Step | 作るもの |
| --- | --- |
| 1 土台 | git 初期化、`CLAUDE.md`、Rojo 構成、`Net`、`Config`、全 Defs の骨組み、`DataService`（セッションロック）、`InventoryService`、`MetricsService`、`GetSnapshot`／`State_Delta`、仮 HUD |
| 2 付与と必殺技 | `BattleStateService`（PvE 部分）、`CombatService`、通常攻撃、`GrantService`、`UltimateService`、装備と装備への付与、練習用の木人（モンスター実装前の仮の相手）、GrantUI、UltimateFx |
| 3 パズルボックス | `PuzzleBoxService`、PuzzleBoxUI（3 状態表示）、はめる操作、完成判定、Badge・称号・引き換えコード |
| 4 呪文・奪取・戦闘状態 | 呪文 6 種、宣言バトル、奪取封じ、免疫・回数・図鑑差、PvP 戦闘状態と終了条件、セーフゾーン、BattleUI、SpellUI |
| 5 世界・モンスター・クラフト | エリア 3 つ（日米混在の仮配置）、`TravelService`／TravelUI、モンスター 4 体と図鑑、探索、クエスト、`CraftService`／CraftUI |
| 6 テスト準備 | テスト用ビルド、計測の出力、アンケート導線（ゲーム内には外部 URL を置かない。アンケートは配布側の案内で渡す） |

---

## 10. 自作名称（すべて仮称。設計図の名前をそのまま使用）

- 能力：疾風付与・剛力付与・鉄壁付与
- 必殺技：蒼嵐・天駆け／震天・大地割り／不動・鉄壁聖域
- 呪文：帰還の翼・追跡の翼・茨の結界・炎剣の加護・奪取封じ・霧隠れ
- モンスター：モリポン・サンドホーン・アオハネ・オオヌシ（ボス）
- 装備：木刀・旅の外套・回復薬
- 素材：葉・枝・牙・布・羽・薬草（布と薬草は設計図に入手先がないので、布＝クエスト報酬と探索、薬草＝里山の探索に仮置き）

内部 ID は英字（例：`ability_gale`）、表示名は日英二重表記（設計図 8 章）にします。英語名は仮で私が付け、Muse さんの名称一覧が届いたら差し替えます。
