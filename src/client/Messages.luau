--!strict
-- サーバーから返る理由コードを、画面に出す日本語に変える

local Messages = {}

local TEXT: { [string]: string } = {
	not_in_battle = "戦闘状態でない相手には効きません",
	unknown_ability = "その能力はありません",
	already_active = "その付与はもう付いています",
	cooldown = "解除したばかりなので、まだ付け直せません",
	over_capacity = "付与の上限を超えます",
	not_active = "その付与は付いていません",
	no_grant_to_pay = "剥がすには、自分の付与が 1 つ必要です",
	no_target = "剥がす相手がいません（先に攻撃してください）",
	out_of_range = "相手が遠すぎます",
	dead = "倒れています",
	casting = "必殺技の詠唱中です",
	not_in_combat = "必殺技は戦闘中にだけ撃てます",
	gauge_not_full = "ゲージがまだ溜まっていません",
	not_owned = "その装備を持っていません",
	already_equipped = "もう装備しています",
	capacity_exceeded = "付与を減らしてから外してください",
	not_equipped = "何も装備していません",
	stunned = "ひるんでいて動けません",
	guarding = "ガード中は攻撃できません",
	dash_cooldown = "ダッシュはまだ使えません",
	already_placed = "そのピースはもうはまっています（重複した分は賭けに使えます）",
	piece_not_owned = "そのピースを持っていません",
	not_in_town = "ピースは町でだけはめられます",
	pieces_full = "未装着のピースがいっぱいです。先にボックスにはめてください",
	already_found = "ここのピースはもう拾いました",
	unknown_id = "見つかりません",
	not_loaded = "読み込み中です。少し待ってください",
	ring_need_piece = "リングに乗るには、未装着のピースが 1 つ必要です（ピースを持ってきて）",
	ring_cooldown = "負けたばかりなので、少し待ってから乗ってください",
	ring_locked = "決闘の台にいる間は、ピースをはめられません",
	area_locked = "まだ行けない場所です",
	ring_locked_travel = "決闘の台にいる間は移動できません",
	travel_cooldown = "少し待ってから移動してください",
	insufficient = "素材が足りません",
	category_full = "その種類のカードはもう持てません（上限 20）",
	item_combat_only = "回復薬は戦闘中にだけ使えます",
	item_not_in_ring = "決闘リングでは回復薬を使えません",
	item_full_health = "HP は満タンです",
	rate_limited = "操作が速すぎます",
	not_implemented = "まだ作っていない機能です",
	server_error = "サーバーでエラーが起きました",
}

function Messages.text(reason: any): string
	if type(reason) ~= "string" then
		return "うまくいきませんでした"
	end
	return TEXT[reason] or reason
end

return Messages
