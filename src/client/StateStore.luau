--!strict
-- サーバーから届いた状態の受け皿（表示専用。ここを書き換えても何も増えない）

local StateStore = {}

StateStore.state = {} :: { [string]: any }

local changedEvent = Instance.new("BindableEvent")
StateStore.Changed = changedEvent.Event -- (sections: { string })

-- スナップショットを反映する。スナップショットに含まれないキー（combat など、
-- 先に差分で届いたもの）は消さずに残す
function StateStore.replace(full: { [string]: any })
	local sections = {}
	for key, value in full do
		StateStore.state[key] = value
		table.insert(sections, key)
	end
	changedEvent:Fire(sections)
end

function StateStore.apply(delta: { [string]: any })
	local sections = {}
	for key, value in delta do
		StateStore.state[key] = value
		table.insert(sections, key)
	end
	changedEvent:Fire(sections)
end

return StateStore
