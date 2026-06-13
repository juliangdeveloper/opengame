extends Node
## Playtest harness: drives the player via simulated input, snapshots viewport, logs state.
## Run with:  godot scenes/play.tscn
## Output:    ~/.local/share/godot/app_userdata/MCP Souls Game/playtest/<label>.png + log

var player: CharacterBody3D
var snapshot_dir: String
var step_idx := 0
var had_error := false

func _ready() -> void:
	# Snapshot dir under user://playtest so the same path works in WSL/Linux and Windows builds.
	snapshot_dir = ProjectSettings.globalize_path("user://playtest")
	DirAccess.make_dir_recursive_absolute(snapshot_dir)
	print("[harness] snapshots -> ", snapshot_dir)

	# Hook script errors so we can see them
	# (no global hook in GDScript; we just rely on stdout/stderr.)

	# Find the Player in the active scene
	await get_tree().process_frame
	player = get_tree().root.find_child("Player", true, false)
	if player == null:
		print("[harness] FATAL: Player not found in scene tree")
		had_error = true
		get_tree().quit(2)
		return
	print("[harness] player found: %s at %s" % [player.name, str(player.global_position)])

	# Keep mouse captured so the player script accepts InputEventMouseMotion for look.
	# (Player._ready sets it to CAPTURED; do NOT override it here.)

	# Run the sequence
	await _run_sequence()
	print("[harness] DONE ok=%s" % str(not had_error))
	get_tree().quit(0 if not had_error else 1)


func _run_sequence() -> void:
	# Settle 5 frames
	for i in 5:
		await get_tree().physics_frame
	await _step("00_idle", [])

	# W held 0.5s -> should move player -Z (forward in current setup)
	await _step("01_W_500ms", [press("move_forward")])
	await get_tree().create_timer(0.5).timeout
	await _step("02_after_W_release", [release("move_forward")])

	# Reset position
	await _reset_player()

	# D held 0.5s -> should move player +X
	await _step("03_D_500ms", [press("move_right")])
	await get_tree().create_timer(0.5).timeout
	await _step("04_after_D_release", [release("move_right")])

	await _reset_player()

	# Mouse-look right 300px -> body should rotate so camera is on player's left
	await _step("05_look_right_300", [mouse_look(Vector2(300, 0))])
	await get_tree().physics_frame
	await _step("06_look_right_settled", [])

	# Reset
	await _reset_player()

	# Sprint W 0.6s (hold move_forward + sprint)
	await _step("07_sprint_500ms", [press("move_forward"), press("sprint")])
	await get_tree().create_timer(0.5).timeout
	await _step("08_after_sprint", [release("move_forward"), release("sprint")])

	await _reset_player()

	# Tap jump
	await _step("09_jump_tap", [tap("jump", 0.04)])
	await get_tree().create_timer(0.15).timeout
	await _step("10_mid_jump", [])

	# Wait to land
	await get_tree().create_timer(0.5).timeout
	await _step("11_after_landing", [])

	# Tap dodge (Circle) - THE BUG CASE
	await _step("12_dodge_tap", [tap("dodge", 0.04)])
	await get_tree().create_timer(0.05).timeout
	await _step("13_dodge_mid", [])

	await get_tree().create_timer(0.6).timeout
	await _step("14_post_dodge", [])

	# Tap attack
	await _step("15_attack_tap", [tap("attack", 0.04)])
	await get_tree().create_timer(0.18).timeout
	await _step("16_attack_active", [])

	await get_tree().create_timer(0.5).timeout
	await _step("17_post_attack", [])


# --- Sequence helpers ---

class Cmd:
	var kind: String
	var arg = null


func press(action: String) -> Cmd:
	var c := Cmd.new(); c.kind = "press"; c.arg = action; return c

func release(action: String) -> Cmd:
	var c := Cmd.new(); c.kind = "release"; c.arg = action; return c

func tap(action: String, hold_s: float) -> Cmd:
	var c := Cmd.new(); c.kind = "tap"; c.arg = [action, hold_s]; return c

func mouse_look(rel: Vector2) -> Cmd:
	var c := Cmd.new(); c.kind = "mouse"; c.arg = rel; return c


func _step(label: String, cmds: Array) -> void:
	step_idx += 1
	# Apply commands
	for c in cmds:
		match c.kind:
			"press":
				_press_action(c.arg)
			"release":
				_release_action(c.arg)
			"tap":
				_tap_action(c.arg[0], c.arg[1])
			"mouse":
				_mouse_look(c.arg)
	# Wait a couple frames for state to settle + render
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_snapshot(label)
	_log_state(label)


func _reset_player() -> void:
	player.global_position = Vector3(0, 1, 0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.model.rotation = Vector3.ZERO
	await get_tree().physics_frame


# --- Input injection ---

func _press_action(action: String) -> void:
	Input.action_press(action)

func _release_action(action: String) -> void:
	Input.action_release(action)

func _tap_action(action: String, hold: float) -> void:
	Input.action_press(action)
	# Schedule release
	get_tree().create_timer(hold).timeout.connect(func(): Input.action_release(action), CONNECT_ONE_SHOT)

func _mouse_look(rel: Vector2) -> void:
	# Inject several small motions so it's processed
	for i in 3:
		var e := InputEventMouseMotion.new()
		e.relative = rel / 3.0
		Input.parse_input_event(e)
		await get_tree().process_frame


# --- Snapshot + log ---

func _snapshot(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		print("[snap] %s EMPTY viewport" % label)
		had_error = true
		return
	var path := "%s/%02d_%s.png" % [snapshot_dir, step_idx, label]
	var err := img.save_png(path)
	if err != OK:
		print("[snap] %s save err=%d" % [label, err])
		had_error = true
	else:
		print("[snap] %s -> %s" % [label, path])

func _log_state(label: String) -> void:
	if player == null:
		return
	var m := player.get_node_or_null("Model")
	var line := "[state] %-22s pos=%-30s vel=%-26s model_yaw=%6.2f body_yaw=%6.2f floor=%s attacking=%s dodging=%s blocking=%s stam=%5.1f" % [
		label,
		"(%5.2f,%5.2f,%5.2f)" % [player.global_position.x, player.global_position.y, player.global_position.z],
		"(%5.2f,%5.2f,%5.2f)" % [player.velocity.x, player.velocity.y, player.velocity.z],
		m.rotation.y if m else 0.0,
		player.rotation.y,
		player.is_on_floor(),
		player.is_attacking,
		player.is_dodging,
		player.is_blocking,
		player.stamina,
	]
	print(line)
