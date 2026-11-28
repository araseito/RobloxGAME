--!strict
-- コードで作る配置物（掲示板・探索ピース・決闘リング）の置き場所を決める。
-- Studio 側に印の Part があればその場所、なければスポーン地点を基準にした仮の場所に置く。

local WorldMarkers = {}

function WorldMarkers.toVector(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- 置き場所の基準にするスポーン地点（なければ原点）
function WorldMarkers.spawnCFrame(): CFrame
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			return d.CFrame
		end
	end
	return CFrame.new()
end

-- Workspace 直下の印の Part（なければ nil）
function WorldMarkers.find(name: string): BasePart?
	local marker = workspace:FindFirstChild(name)
	if marker and marker:IsA("BasePart") then
		return marker
	end
	return nil
end

return WorldMarkers
