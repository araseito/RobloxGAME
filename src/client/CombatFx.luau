--!strict
-- 攻撃の手応え（ヒット感）の演出。すべて見た目だけで、結果（ダメージなど）はサーバーが決める。
-- ・腕の振り：4 段コンボで右・左・右と腕を突き出し、4 段目（締め）は大きく振り下ろす
--   本物のアニメーション素材がないため、肩の関節（Motor6D）をコードで回している。
--   アニメーションを作ったら playSwing の中身だけ差し替えればよい
-- ・斬撃の光：攻撃のたびに前方へ光の筋。締めはオレンジで大きく
-- ・当たったとき：相手が一瞬白く光り、ダメージの数字が浮かぶ。締めは画面が揺れる
-- ・ガード中は青、ひるみ中は黄色の縁取り（キャラクターの属性 Guarding / Stunned を見る）

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local CombatFx = {}

local localPlayer = Players.LocalPlayer

local COLOR_SLASH = Color3.fromRGB(200, 230, 255)
local COLOR_FINISHER = Color3.fromRGB(255, 160, 50)
local COLOR_GUARD = Color3.fromRGB(80, 170, 255)
local COLOR_STUN = Color3.fromRGB(255, 220, 60)

local fxFolder: Folder? = nil
local playerGui: PlayerGui? = nil

local function folder(): Folder
	local current = fxFolder
	if current and current.Parent then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = "LocalCombatFx"
	created.Parent = workspace
	fxFolder = created
	return created
end

-- 腕の振り ------------------------------------------------------------------

-- 肩の関節と、腕を前に突き出すための回転（R15 と R6 で向きが違う）
local function shoulderOf(character: Model, side: string): (Motor6D?, CFrame?)
	local upperArm = character:FindFirstChild(side .. "UpperArm")
	local r15 = upperArm and upperArm:FindFirstChild(side .. "Shoulder")
	if r15 and r15:IsA("Motor6D") then
		-- R15：X 軸のプラス回転で腕が前に上がる
		return r15, CFrame.Angles(math.rad(90), 0, 0)
	end
	local torso = character:FindFirstChild("Torso")
	local r6 = torso and torso:FindFirstChild(side .. " Shoulder")
	if r6 and r6:IsA("Motor6D") then
		-- R6：Z 軸で回す。右と左で向きが逆
		local sign = if side == "Right" then 1 else -1
		return r6, CFrame.Angles(0, 0, math.rad(90 * sign))
	end
	return nil, nil
end

-- 肩の元の角度。キャラクターが作り直されたら古い関節は自動で消える（弱参照）
local originalC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function swingArm(character: Model, side: string, raise: number, outTime: number, backTime: number)
	local motor, forward = shoulderOf(character, side)
	if not motor or not forward then
		return
	end
	local base = originalC0[motor]
	if not base then
		base = motor.C0
		originalC0[motor] = base
	end
	-- forward は「90 度前に上げる」回転。raise（0〜1.7 程度）で量を変える
	local axis, angle = forward:ToAxisAngle()
	local target = base * CFrame.fromAxisAngle(axis, angle * raise)
	local out = TweenService:Create(motor, TweenInfo.new(outTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = target })
	out:Play()
	out.Completed:Once(function()
		TweenService:Create(motor, TweenInfo.new(backTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = base }):Play()
	end)
end

local function playSwing(character: Model, step: number, finisher: boolean)
	if finisher then
		-- 締め：右腕を高く振り上げてから振り下ろす
		swingArm(character, "Right", 1.8, 0.07, 0.25)
		swingArm(character, "Left", 0.6, 0.07, 0.25)
	elseif step % 2 == 1 then
		swingArm(character, "Right", 1.0, 0.06, 0.14)
	else
		swingArm(character, "Left", 1.0, 0.06, 0.14)
	end
end

-- 斬撃の光 --------------------------------------------------------------------

local function slash(character: Model, step: number, finisher: boolean)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local side = if finisher then 0 elseif step % 2 == 1 then 1 else -1
	local streak = Instance.new("Part")
	streak.Name = "Slash"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CastShadow = false
	streak.Material = Enum.Material.Neon
	streak.Color = if finisher then COLOR_FINISHER else COLOR_SLASH
	streak.Transparency = 0.15
	streak.Size = if finisher then Vector3.new(7, 0.3, 0.6) else Vector3.new(4, 0.2, 0.4)
	-- 体の前に、斜めに走る筋を出す
	local tilt = if finisher then 0 else math.rad(35 * side)
	streak.CFrame = root.CFrame * CFrame.new(side * 0.8, 0.6, -3) * CFrame.Angles(0, 0, tilt)
	streak.Parent = folder()
	TweenService:Create(streak, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = streak.Size * Vector3.new(1.4, 1, 1),
	}):Play()
	Debris:AddItem(streak, 0.25)
end

-- 当たったとき ----------------------------------------------------------------

local function flash(model: Model, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.Name = "HitFlash"
	highlight.FillColor = color
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = folder()
	Debris:AddItem(highlight, 0.1)
end

local function popNumber(model: Model, text: string, color: Color3, big: boolean)
	local gui = playerGui
	local anchor = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	if not gui or not anchor or not anchor:IsA("BasePart") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(140, 40)
	billboard.AlwaysOnTop = true
	billboard.StudsOffset = Vector3.new((math.random() - 0.5) * 2, 3, 0)
	billboard.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if big then 30 else 20
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = billboard.StudsOffset + Vector3.new(0, 2.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(billboard, 0.65)
end

-- 画面を短く揺らす（自分が締めを当てた・受けたとき）
local shakeToken = 0
local function shake(strength: number, seconds: number)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	shakeToken += 1
	local myToken = shakeToken
	task.spawn(function()
		local elapsed = 0
		while elapsed < seconds and shakeToken == myToken do
			local dx = (math.random() - 0.5) * strength
			local dy = (math.random() - 0.5) * strength
			humanoid.CameraOffset = Vector3.new(dx, dy, 0)
			elapsed += task.wait()
		end
		if shakeToken == myToken then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

local function onHit(payload: any)
	local target = payload.target
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	local model = target :: Model
	local amount = if type(payload.amount) == "number" then payload.amount else 0

	if payload.broken then
		flash(model, COLOR_STUN)
		popNumber(model, "ガードブレイク！", COLOR_STUN, true)
	elseif payload.guarded then
		flash(model, COLOR_GUARD)
		popNumber(model, ("ガード %d"):format(math.ceil(amount)), COLOR_GUARD, false)
	else
		flash(model, Color3.new(1, 1, 1))
		popNumber(model, tostring(math.ceil(amount)), if payload.finisher then COLOR_FINISHER else Color3.new(1, 1, 1), payload.finisher == true)
	end

	-- 自分が受けた、または締めが当たったときは画面を揺らす
	local mine = localPlayer.Character
	if mine and model == mine then
		shake(if payload.finisher or payload.broken then 1.2 else 0.5, 0.15)
	elseif payload.finisher then
		shake(0.6, 0.12)
	end
end

local function onSwing(payload: any)
	if type(payload.userId) ~= "number" or type(payload.step) ~= "number" then
		return
	end
	local attacker = Players:GetPlayerByUserId(payload.userId)
	local character = attacker and attacker.Character
	if not character then
		return
	end
	local finisher = payload.finisher == true
	playSwing(character, payload.step, finisher)
	slash(character, payload.step, finisher)
end

-- ガード・ひるみの縁取り --------------------------------------------------------

local outlines: { [Model]: Highlight } = {}

local function refreshOutline(character: Model)
	local guarding = character:GetAttribute("Guarding") == true
	local stunned = character:GetAttribute("Stunned") == true
	local highlight = outlines[character]
	if not guarding and not stunned then
		if highlight then
			highlight:Destroy()
			outlines[character] = nil
		end
		return
	end
	if not highlight then
		local created = Instance.new("Highlight")
		created.Name = "StateOutline"
		created.FillTransparency = 0.75
		created.OutlineTransparency = 0
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.Adornee = character
		created.Parent = folder()
		highlight = created
		outlines[character] = created
	end
	local color = if stunned then COLOR_STUN else COLOR_GUARD
	local h = highlight :: Highlight
	h.OutlineColor = color
	h.FillColor = color
end

local function watchCharacter(character: Model)
	character:GetAttributeChangedSignal("Guarding"):Connect(function()
		refreshOutline(character)
	end)
	character:GetAttributeChangedSignal("Stunned"):Connect(function()
		refreshOutline(character)
	end)
	character.AncestryChanged:Connect(function()
		if not character.Parent and outlines[character] then
			outlines[character]:Destroy()
			outlines[character] = nil
		end
	end)
	refreshOutline(character)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

function CombatFx.mount(gui: PlayerGui)
	playerGui = gui
	Net.getEvent("Combat_Fx").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.t == "swing" then
			onSwing(payload)
		elseif payload.t == "hit" then
			onHit(payload)
		end
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

-- 必殺技を撃ったとき（UltimateFx から呼ぶ）：自分の画面を強めに揺らす
function CombatFx.bigShake()
	shake(1.5, 0.3)
end

return CombatFx
