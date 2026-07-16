## player.gd — RuleBook-driven player body.
extends EntityCharacter
class_name Player

var _stamina_bar: ProgressBar = null
var _hp_bar: ProgressBar = null

# === HP (RuleBook: every entity has life) ===
var current_hp: float = 100.0
var max_hp_stat: float = 100.0
var hp_regen_rate: float = 3.0  # points/sec (slower than stamina's 15/s)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if data == null:
		var player_res: Resource = load("res://data/characters/player.tres")
		if player_res != null:
			data = player_res
	super._ready()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	# Load max_hp from data
	if data != null and data.max_hp > 0:
		max_hp_stat = data.max_hp
	current_hp = max_hp_stat
	# UI refs
	_stamina_bar = get_node_or_null("HUD/StaminaBar")
	_hp_bar = get_node_or_null("HUD/HPBar")
	_log("=== Player ready ===")
	_log("data=%s hp=%.0f/%.0f" % [String(data.id) if data else "(none)", current_hp, max_hp_stat])
	_log("controller=%s" % (
		controller.get_script().resource_path.get_file() if controller else "(none)"
	))


func _physics_process(delta: float) -> void:
	# Walk + jump + stamina + move_and_slide
	if controller != null and controller.has_method("process_movement"):
		controller.process_movement(delta)
	# HP regeneration (slower than stamina)
	if current_hp < max_hp_stat:
		current_hp = minf(max_hp_stat, current_hp + hp_regen_rate * delta)
	# Report position to SceneManager for RuleBook sync
	if SceneManager != null:
		SceneManager.report_position(self)
	# Update UI
	if _stamina_bar != null and controller != null:
		_stamina_bar.max_value = controller.max_stamina
		_stamina_bar.value = controller.current_stamina
	if _hp_bar != null:
		_hp_bar.max_value = max_hp_stat
		_hp_bar.value = current_hp


## Called by hitbox or any damage source.
func take_damage(amount: float, _attacker: Node = null, _element: StringName = &"") -> float:
	current_hp = maxf(0.0, current_hp - amount)
	_log("took %.0f damage → hp=%.0f/%.0f" % [amount, current_hp, max_hp_stat])
	if current_hp <= 0.0:
		_log("DEAD")
	return amount


func _log(msg: String) -> void:
	print("[player] %s" % msg)
