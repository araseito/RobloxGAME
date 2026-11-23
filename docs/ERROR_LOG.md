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
