--!strict
-- 画面上部に短い通知を出す（仮の見た目）

local Toast = {}

local label: TextLabel? = nil
local token = 0

function Toast.mount(gui: ScreenGui)
	local l = Instance.new("TextLabel")
	l.Name = "Toast"
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 64)
	l.Size = UDim2.fromOffset(0, 32)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	l.BackgroundTransparency = 0.15
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Visible = false
	l.ZIndex = 20
	l.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = l
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = l
	label = l
end

function Toast.show(text: string, seconds: number?)
	local l = label
	if not l then
		return
	end
	token += 1
	local myToken = token
	l.Text = text
	l.Visible = true
	task.delay(seconds or 2, function()
		if token == myToken then
			l.Visible = false
		end
	end)
end

return Toast
