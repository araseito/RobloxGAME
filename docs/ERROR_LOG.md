# エラー記録

コードを書く前に読む。新しく起きたエラーは「現象 / 原因 / 対処 / 再発防止」の形で追記する。

## #1 サーバーが起動直後に止まる（Step 1、2026-11-24）

- **現象**：Studio でプレイすると HUD は出るが「読み込み中…」のまま。出力に `Script 'ServerScriptService.Server.Main', Line 6` のスタックと、クライアントの `Infinite yield possible on 'ReplicatedStorage:WaitForChild("Net")'`
- **原因**：`src/server/Remotes.luau` の構文エラー。`assert(...)` の次の行が `(getRemote(name) :: RemoteEvent):FireAllClients(...)` と `(` で始まっていた。Luau は前の行の関数呼び出しの続きと区別できず、「Ambiguous syntax」で読み込みに失敗する。そのため `Main` の `require(Server.Remotes)` が失敗し、`Net` フォルダが作られなかった
- **対処**：`local remote = getRemote(name) :: RemoteEvent` と変数に入れてから呼ぶ形に直した
- **再発防止**：
  - **行の先頭を `(` で始めない**。キャストした値のメソッドを呼ぶときは、いったん local に入れる
  - `tests/run.luau` に、src 以下の全 `.luau` ファイルを `luau.compile` で構文チェックするテストを足した。push の前に必ず `lune run tests/run` を通す
  - 単体テストが通っても、サーバーとクライアントのスクリプトは読み込まれていなかった。テストで確かめていない範囲を報告に書く

## #2 Config に Roblox の型を書きかけた（Step 2、2026-11-24、未然に防いだ）

- **現象**：木人の位置を `Config.Dummy.DefaultPosition = Vector3.new(...)` と書きかけた
- **原因**：`Config.luau` は Lune の単体テストでも読み込む。Lune には `Vector3` などの Roblox の型がないので、テストが読み込みで失敗する
- **対処**：`{ 0, 3, -20 }` のただの数の表にして、使う側（TrainingDummy）で `Vector3.new` に直す
- **再発防止**：`src/shared` の Config・Defs・Logic には `Vector3`・`Color3`・`CFrame`・`Enum`・`game` などの Roblox の型を書かない

## 予防のために足したチェック（Step 2）

- `tests/run.luau` に参照チェックを足した。`require(script.Parent.X)` の X が実在するか、コードに書いた Remote 名が `Net.luau` の一覧にあるかを調べる。わざと打ち間違いを入れたコピーで、両方とも検出できることを確かめた

## #3 剥がした木人の鉄壁がすぐ戻る（Step 2、2026-11-29）

- **現象**：G で木人の鉄壁を剥がしても、0.5 秒ほどで戻ることがある。剥がしたあとの 4 段目で吹き飛ばせない
- **原因**：`TrainingDummy.luau` のかけ直しが「10 秒ごとに必ずかける」ループだった。`Config.Dummy.RegrantSeconds` の説明は「剥がされてからかけ直すまでの秒数」なのに、剥がした時刻を見ていなかった。そのため、剥がしてから 0〜10 秒のどこかで戻っていた
- **対処**：`Grants` 属性の変化で剥がされた時刻を覚え、その時刻から `RegrantSeconds` 秒たったらかけ直す形にした
- **再発防止**：
  - 「〜してから N 秒」という仕様は、決まった間隔のループで作らず、起点の時刻を覚えて比べる
  - 単体テストは `Logic/` しか見ていないので、時間の流れが関わる動き（クールダウン・かけ直し・予備動作）は Studio のプレイテストで、属性の変化を時刻つきで記録して確かめる

## #4 倒れたプレイヤーの体をモンスターが攻撃し続ける（Step 5、2026-11-29）

- **現象**：プレイヤーが倒れたあと、HP が 0 と 1 を行き来し、モンスターが倒れた体を攻撃し続けた
- **原因**：狙う相手の判定を `Health > 0` だけで見ていた。倒れた体も既定の自然回復で HP が 1 に戻ることがあり、生きているとみなしていた
- **対処**：`MonsterService` の `isAlive` で、`Health > 0` に加えて `GetState() ~= Dead` も確かめる
- **再発防止**：プレイヤーが生きているかは、HP だけでなく Humanoid の状態でも確かめる

## #5 Lune に Roblox の Random がない（Step 5、2026-11-29）

- **現象**：単体テストで `Random.new` が nil になり、20 万回のシミュレーションが失敗した
- **原因**：Lune は Roblox の型（`Random` など）を持たない（#2 の `Vector3` と同じ）
- **対処**：テストでは種を固定した `math.random` を使う。サーバーは `Random.new():NextNumber` を、抽選の関数に引数で渡す
- **再発防止**：`Logic/` の乱数は必ず引数で受け取る。テストで使う乱数は `math.randomseed` で種を固定する
