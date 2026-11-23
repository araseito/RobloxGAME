--!strict
-- セッションロックの判定。require を使わない。
-- 戻り値：
--   "free"    ロックなし
--   "ours"    このサーバーのロック
--   "expired" 他サーバーのロックだが期限切れ（奪ってよい）
--   "locked"  他サーバーが使用中（待つ）

local SessionLock = {}

function SessionLock.state(lock: any, jobId: string, now: number, timeout: number): string
	if type(lock) ~= "table" or type(lock.jobId) ~= "string" then
		return "free"
	end
	if lock.jobId == jobId then
		return "ours"
	end
	local at = if type(lock.at) == "number" then lock.at else 0
	if now - at >= timeout then
		return "expired"
	end
	return "locked"
end

function SessionLock.canAcquire(state: string): boolean
	return state == "free" or state == "ours" or state == "expired"
end

return SessionLock
