--!strict
-- Remote ごと・プレイヤーごとのトークンバケット

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

type Bucket = { tokens: number, last: number }

local RateLimiter = {}

local buckets: { [Player]: { [string]: Bucket } } = {}

function RateLimiter.allow(player: Player, key: string): boolean
	local rule = Config.RateLimit[key] or Config.RateLimit.Default
	local now = os.clock()

	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end

	local bucket = perPlayer[key]
	if not bucket then
		bucket = { tokens = rule.Burst, last = now }
		perPlayer[key] = bucket
	end

	bucket.tokens = math.min(rule.Burst, bucket.tokens + (now - bucket.last) * rule.Rate)
	bucket.last = now

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimiter
