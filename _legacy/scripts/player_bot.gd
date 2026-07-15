extends Node
## Player bot: simulates a real player by sending real InputEventKey / InputEventMouseButton /
## InputEventMouseMotion events. Uses a decision FSM to choose actions based on
## player and enemy state. Logs every decision for review.
##
## Bound skills: W/A/S/D, sprint (Shift), attack (LMB), block (RMB), parry (F), dodge (Ctrl).

var player: CharacterBody3D
var enemy: Node3D
var bot_enabled := true
var decision_cooldown := 0.0
var current_decision: String = "IDLE"

# Decision config
const DECISION_INTERVAL := 0.15
const APPROACH_DIST := 6.0
const ENGAGE_DIST := 2.6
const FACE_MAX_PX_PER_TICK := 1000.0  # essentially unlimited; in sim, we want full facing each tick

# Track what we last sent so release_all is correct
var _keys_held: Dictionary = {}      # keycode -> true
var _mouse_btns_held: Dictionary = {}  # button_index -> true

# Counters for end-of-sim stats
var stat_decisions := 0
var stat_attacks := 0
var stat_parries_attempted := 0
var stat_parries_succeeded := 0
var stat_dodges := 0
var stat_blocks := 0
var stat_enemy_kills := 0
var stat_player_deaths := 0
var stat_damage_dealt := 0.0
var stat_damage_taken := 0.0

var _t0_ms: int = 0


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	await get_tree().process_frame
	player = get_tree().root.find_child("Player", true, false)
	if player == null:
		push_error("[bot] Player not found!")
		set_process(false)
		return
	# Connect to player signals for stat tracking
	player.parry_succeeded.connect(_on_player_parry_succeeded)
	player.attack_hit.connect(_on_player_attack_hit)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)
	_acquire_enemy()
	# Initial decision after a short settle
	await get_tree().create_timer(0.3).timeout
	_log("BOT_READY player=%s enemy=%s" % [player.name, enemy.name if enemy else "none"])


# --- Signal handlers (player -> bot stat counters) ---

func _on_player_parry_succeeded(_enemy: Node) -> void:
	stat_parries_succeeded += 1

func _on_player_attack_hit(_target: Node, damage: float) -> void:
	stat_damage_dealt += damage

func _on_player_damaged(_amount: float, _final_amount: float, blocked: bool) -> void:
	stat_damage_taken += _final_amount
	if not blocked:
		pass  # we already track total

func _on_player_died() -> void:
	stat_player_deaths += 1
	release_all()

func _on_player_respawned() -> void:
	release_all()


func _physics_process(delta: float) -> void:
	if not bot_enabled:
		return
	decision_cooldown -= delta
	if decision_cooldown > 0.0:
		return
	decision_cooldown = DECISION_INTERVAL
	_decide()


# --- Decision FSM ---

func _decide() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().root.find_child("Player", true, false)
		if player == null: return
	if player.is_dying:
		release_all()
		_log_decision("DEAD_WAIT", "player respawning")
		return
	if enemy == null or not is_instance_valid(enemy):
		_acquire_enemy()
	if enemy == null or enemy.state == EnemyAI.State.DEAD:
		release_all()
		_log_decision("NO_ENEMY", "all enemies down")
		return

	var dist: float = player.global_position.distance_to(enemy.global_position)
	var enemy_state: String = EnemyAI.State.keys()[enemy.state]
	var enemy_windup_left: float = enemy.state_timer if enemy.state == EnemyAI.State.WINDUP else 0.0

	_log_observe(dist, enemy_state, enemy_windup_left)
	_face_enemy()

	stat_decisions += 1

	# ---- Movement decisions ----
	if dist > APPROACH_DIST:
		current_decision = "APPROACH"
		_log_decision("APPROACH", "dist=%.2f" % dist)
		_approach(dist)
		return
	elif dist > ENGAGE_DIST:
		current_decision = "CLOSE"
		_log_decision("CLOSE", "dist=%.2f" % dist)
		_close()
		return

	# ---- Engagement decisions ----
	current_decision = "ENGAGE"
	_release_movement()  # don't walk while fighting

	# If we're busy with our own action, don't do anything
	if player.is_attacking or player.is_dodging or player.is_parrying:
		_log_decision("BUSY", "player is acting")
		return

	match enemy.state:
		enemy.State.WINDUP:
			_react_to_windup(enemy_windup_left)
		enemy.State.ACTIVE:
			_react_to_active()
		enemy.State.RECOVER:
			_release_block_if_held()
			_react_to_recover()
		enemy.State.STAGGER:
			_release_block_if_held()
			_react_to_stagger()
		enemy.State.IDLE, enemy.State.CHASE:
			_release_block_if_held()
			_react_to_idle(dist)
		_:
			_release_block_if_held()
			pass


func _release_block_if_held() -> void:
	if _mouse_btns_held.get(MOUSE_BUTTON_RIGHT, false):
		_release_block()


func _approach(dist: float) -> void:
	_release_block_if_held()
	_release_sprint()
	# Edge-avoidance: if near the floor edge, move toward the center instead of the enemy
	var away := _edge_avoid_vector()
	if away.length() > 0.01:
		_log_decision("EDGE_RETURN", "near edge -> toward center")
		_move_along(away)
		return
	if dist > 9.0 and player.stamina > 30 and randf() < 0.7:
		_press_sprint()
	_press_w()
	_release_s()
	_release_a()
	_release_d()


func _close() -> void:
	_release_block_if_held()
	_release_sprint()
	var away := _edge_avoid_vector()
	if away.length() > 0.01:
		_log_decision("EDGE_RETURN", "near edge -> toward center")
		_move_along(away)
		return
	_press_w()
	_release_s()
	_release_a()
	_release_d()


func _edge_avoid_vector() -> Vector2:
	# Floor is 500x500 centered at origin. Keep a safe margin.
	var p := player.global_position
	var xz := Vector2(p.x, p.z)
	var limit := 240.0  # floor half-size 250 minus safety margin
	if absf(xz.x) > limit or absf(xz.y) > limit:
		# Push toward center
		return -xz.normalized()
	return Vector2.ZERO


func _move_along(world_dir: Vector2) -> void:
	# Convert world XZ to local input keys given current facing
	var forward := -player.global_transform.basis.z
	forward.y = 0
	if forward.length() < 0.01: return
	forward = forward.normalized()
	var right := player.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	# dot products
	var f_dot := world_dir.x * forward.x + world_dir.y * forward.z
	var r_dot := world_dir.x * right.x + world_dir.y * right.z
	# For simplicity: snap to 8-way input
	if absf(f_dot) > absf(r_dot):
		if f_dot > 0: _press_s(); _release_w()
		else: _press_w(); _release_s()
		_release_a(); _release_d()
	else:
		if r_dot > 0: _press_d(); _release_a()
		else: _press_a(); _release_d()
		_release_w(); _release_s()


func _react_to_windup(windup_left: float) -> void:
	# Parry window covers 0.4s; enemy ACTIVE starts at end of windup.
	# Press parry when state_timer < 0.35 to land in ACTIVE.
	# Parry is cheaper (18) than dodge (28) — prioritize it to keep stamina for the next exchange.
	if windup_left < 0.35 and windup_left > 0.05 and player.stamina >= 22 and not player.is_parrying:
		if randf() < 0.75:
			_log_decision("PARRY", "windup_left=%.2f" % windup_left)
			stat_parries_attempted += 1
			_tap_parry()
			return
	# Dodge: only if stamina is high enough to recover before the next attack
	if player.stamina >= 45 and randf() < 0.55:
		_log_decision("DODGE", "windup_left=%.2f" % windup_left)
		stat_dodges += 1
		_tap_dodge_random()
		return
	# Block (hold) - only if we have stamina to spare
	if player.stamina > 35 and randf() < 0.6:
		_log_decision("BLOCK_HOLD", "windup_left=%.2f" % windup_left)
		stat_blocks += 1
		_press_block()
		return
	# Back off
	_log_decision("BACK_OFF", "windup_left=%.2f" % windup_left)
	_press_s()


func _react_to_active() -> void:
	# Already too late for parry. Block if not already, else take the hit.
	if _mouse_btns_held.get(MOUSE_BUTTON_RIGHT, false):
		_log_decision("BLOCK_LATE", "enemy in ACTIVE")
		return
	if player.stamina > 5 and randf() < 0.4:
		_log_decision("BLOCK_PANIC", "enemy in ACTIVE")
		_press_block()
		return
	_log_decision("EAT_HIT", "enemy in ACTIVE")


func _react_to_recover() -> void:
	if player.stamina >= 22 and randf() < 0.85:
		_log_decision("ATTACK", "enemy in RECOVER")
		stat_attacks += 1
		_tap_attack()
		return
	_log_decision("WAIT", "enemy in RECOVER")


func _react_to_stagger() -> void:
	if player.stamina >= 22 and randf() < 0.95:
		_log_decision("ATTACK", "enemy STAGGERED")
		stat_attacks += 1
		_tap_attack()
		return
	_log_decision("WAIT_STAGGER", "enemy staggered")


func _react_to_idle(_dist: float) -> void:
	if player.stamina >= 22 and randf() < 0.4:
		_log_decision("ATTACK_FEINT", "enemy idle/chase")
		stat_attacks += 1
		_tap_attack()
		return
	_log_decision("WAIT_IDLE", "enemy idle/chase")


# --- Input injection (real events) ---

func _send_key(keycode: int, pressed: bool) -> void:
	if _keys_held.get(keycode, false) == pressed:
		return  # no state change, skip
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	Input.parse_input_event(e)
	_keys_held[keycode] = pressed
	_log("key keycode=%d %s" % [keycode, "down" if pressed else "up"])


func _send_mouse_button(button: int, pressed: bool) -> void:
	if _mouse_btns_held.get(button, false) == pressed:
		return  # no state change, skip
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	_mouse_btns_held[button] = pressed
	_log("mouse_btn button=%d %s" % [button, "down" if pressed else "up"])


func _send_mouse_motion(relative: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = relative
	Input.parse_input_event(e)
	if absf(relative.x) > 5.0 or absf(relative.y) > 5.0:
		_log("mouse_motion rel=%s" % str(relative))


# Higher-level press / tap helpers
func _press_w():  _send_key(KEY_W, true)
func _release_w(): _send_key(KEY_W, false)
func _press_s():  _send_key(KEY_S, true)
func _release_s(): _send_key(KEY_S, false)
func _press_a():  _send_key(KEY_A, true)
func _release_a(): _send_key(KEY_A, false)
func _press_d():  _send_key(KEY_D, true)
func _release_d(): _send_key(KEY_D, false)
func _press_sprint():  _send_key(KEY_SHIFT, true)
func _release_sprint(): _send_key(KEY_SHIFT, false)
func _press_block():  _send_mouse_button(MOUSE_BUTTON_RIGHT, true)
func _release_block(): _send_mouse_button(MOUSE_BUTTON_RIGHT, false)

func _tap_dodge() -> void:
	_send_key(KEY_CTRL, true)
	await get_tree().create_timer(0.04).timeout
	_send_key(KEY_CTRL, false)

func _tap_dodge_random() -> void:
	# 60% back-dodge, 40% left/right
	var r := randf()
	_send_key(KEY_W if r < 0.6 else (KEY_A if r < 0.8 else KEY_D), true)
	_send_key(KEY_CTRL, true)
	await get_tree().create_timer(0.04).timeout
	_send_key(KEY_CTRL, false)
	_send_key(KEY_W if r < 0.6 else (KEY_A if r < 0.8 else KEY_D), false)

func _tap_parry() -> void:
	_send_key(KEY_F, true)
	await get_tree().create_timer(0.04).timeout
	_send_key(KEY_F, false)

func _tap_attack() -> void:
	_send_mouse_button(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.04).timeout
	_send_mouse_button(MOUSE_BUTTON_LEFT, false)

func _release_movement() -> void:
	_release_w(); _release_s(); _release_a(); _release_d(); _release_sprint()

func release_all() -> void:
	_release_movement()
	_release_block()
	# Also release dodge/parry/attack in case they're held
	_send_key(KEY_CTRL, false)
	_send_key(KEY_F, false)
	_send_mouse_button(MOUSE_BUTTON_LEFT, false)


# --- Facing ---

func _face_enemy() -> void:
	if enemy == null or player == null: return
	var to_enemy := enemy.global_position - player.global_position
	to_enemy.y = 0
	if to_enemy.length() < 0.01: return
	var desired_yaw: float = atan2(-to_enemy.x, -to_enemy.z)
	var current_yaw: float = player.rotation.y
	var delta: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	# Convert radians to mouse pixels (negative because rotate_y uses -event.relative.x)
	var px: float = -delta / player.mouse_sensitivity
	# Cap per-tick motion
	if absf(px) > FACE_MAX_PX_PER_TICK:
		px = sign(px) * FACE_MAX_PX_PER_TICK
	_send_mouse_motion(Vector2(px, 0))


# --- Helpers ---

func _acquire_enemy() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.state != e.State.DEAD:
			enemy = e
			return
	enemy = null


func _log_observe(dist: float, estate: String, windup_left: float) -> void:
	_log("observe dist=%.2f enemy_state=%s windup_left=%.2f player_hp=%.0f stam=%.0f enemy_hp=%.0f" % [
		dist, estate, windup_left, player.hp, player.stamina, enemy.hp
	])


func _log_decision(action: String, reason: String) -> void:
	_log("decision %s reason=%s" % [action, reason])


func _log(msg: String) -> void:
	print("[%7.3f] [bot] %s" % [_ts(), msg])


func _ts() -> float:
	return (Time.get_ticks_msec() - _t0_ms) / 1000.0
