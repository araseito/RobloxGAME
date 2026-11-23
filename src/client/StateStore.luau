--!strict
-- サーバーから届いた状態の受け皿（表示専用。ここを書き換えても何も増えない）

local StateStore = {}

StateStore.state = {} :: { [string]: any }

local changedEvent = Instance.new("BindableEvent")
StateStore.Changed = changedEvent.Event -- (sections: { string })

function StateStore.replace(full: { [string]: any })
	StateStore.state = full
	local sections = {}
	for key in full do
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
