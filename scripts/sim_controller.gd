extends Node
## Sim controller: tracks elapsed time, prints end-of-sim stats, and quits after a fixed duration.

@export var sim_duration := 180.0  # 3 minutes
@onready var bot: Node = get_parent().get_node_or_null("PlayerBot")

var _t0_ms: int = 0
var _finished: bool = false

func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	print("[sim] START duration=%.0fs" % sim_duration)

func _process(_delta: float) -> void:
	if _finished: return
	var elapsed := (Time.get_ticks_msec() - _t0_ms) / 1000.0
	if elapsed >= sim_duration:
		_finished = true
		_finish()

func _finish() -> void:
	set_process(false)
	print("[sim] DONE elapsed=%.2fs" % ((Time.get_ticks_msec() - _t0_ms) / 1000.0))
	if bot:
		bot.bot_enabled = false
		bot.release_all()
		print("[sim] STATS decisions=%d attacks=%d parries=%d/%d dodges=%d blocks=%d dmg_dealt=%.0f dmg_taken=%.0f enemy_kills=%d player_deaths=%d" % [
			bot.stat_decisions, bot.stat_attacks,
			bot.stat_parries_succeeded, bot.stat_parries_attempted,
			bot.stat_dodges, bot.stat_blocks,
			bot.stat_damage_dealt, bot.stat_damage_taken,
			bot.stat_enemy_kills, bot.stat_player_deaths,
		])
	# Give a tiny moment for final prints
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
