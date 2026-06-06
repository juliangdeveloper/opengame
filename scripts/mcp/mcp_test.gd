## MCP Test — corre Godot con MCPReceiver y envía un set de requests JSON-RPC.
##
## Imprime PASS/FAIL por cada test. Exit code 0 si todos pasan, 1 si falla alguno.
##
## Uso:
##   godot --headless --quit-after 60 scenes/mcp_test.tscn
extends Node

var _client: StreamPeerTCP
var _results: Dictionary = {}  # test_name -> bool
var _next_id: int = 1
var _pending: Dictionary = {}  # id -> test_name
var _current_test: String = ""
var _timeout_timer: Timer
var _tests_to_run: Array = []
var _test_idx: int = 0


func _ready() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.wait_time = 5.0
	_timeout_timer.one_shot = true
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)
	# Espera a que el MCPReceiver esté listo y se conecte
	call_deferred("_connect_to_server")


func _connect_to_server() -> void:
	_client = StreamPeerTCP.new()
	# MCPReceiver escucha en 9876 (mismo proceso)
	var err: int = _client.connect_to_host("127.0.0.1", 9876)
	if err != OK:
		print("[MCPTest] connect error: %d" % err)
		_fail_all("connect_failed")
		get_tree().quit(1)
		return
	print("[MCPTest] connecting...")
	# Espera la conexión
	_poll_connection()


func _poll_connection() -> void:
	# Espera a STATUS_CONNECTED
	var start := Time.get_ticks_msec()
	while _client.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_client.poll()
		if Time.get_ticks_msec() - start > 3000:
			print("[MCPTest] connection timeout")
			_fail_all("connection_timeout")
			get_tree().quit(1)
			return
		OS.delay_msec(50)
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		print("[MCPTest] not connected (status=%d)" % _client.get_status())
		_fail_all("not_connected")
		get_tree().quit(1)
		return
	print("[MCPTest] connected")
	# Encola los tests
	_tests_to_run = [
		"ping",
		"get_player_state",
		"grant_skill_points",
		"grant_skill",
		"get_player_state_after_grants",
		"spawn_enemy",
		"set_objective",
		"unknown_method",
		"list_skills",
		"create_skill",
		"modify_skill",
		"spawn_challenge",
	]
	_run_next_test()


func _run_next_test() -> void:
	if _test_idx >= _tests_to_run.size():
		_finish()
		return
	_current_test = _tests_to_run[_test_idx]
	_test_idx += 1
	_timeout_timer.start()
	var req: Dictionary
	match _current_test:
		"ping":
			req = _make_request("ping", {})
		"get_player_state":
			req = _make_request("get_player_state", {})
		"grant_skill_points":
			req = _make_request("grant_skill_points", {"amount": 5})
		"grant_skill":
			req = _make_request("grant_skill", {"skill_id": "kamehameha_001"})
		"get_player_state_after_grants":
			req = _make_request("get_player_state", {})
		"spawn_enemy":
			req = _make_request("spawn_enemy", {"scene": "res://scenes/dummy.tscn", "position": {"x": 2.0, "y": 1.0, "z": 0.0}})
		"set_objective":
			req = _make_request("set_objective", {"text": "Test objective from MCP"})
		"unknown_method":
			req = _make_request("nonexistent_method", {})
		"list_skills":
			req = _make_request("list_skills", {})
		"create_skill":
			req = _make_request("create_skill", {
				"id": "fireball_test_001",
				"name": "Fireball (test)",
				"description": "A simple fire projectile",
				"type": "damage",
				"category": "damage",
				"target_resolver": {"kind": "projectile_carrier"},
				"atoms": [
					{"type": "hit", "params": {"amount": 80.0, "knockback": 5.0}, "applies_to_target": true}
				],
				"designed_max": {"amount": 100.0, "cooldown": 5.0, "stamina": 30.0},
				"costs": {"stamina": 30.0, "cooldown": 5.0},
			})
		"modify_skill":
			req = _make_request("modify_skill", {
				"id": "fireball_test_001",
				"name": "Fireball (modified)",
			})
		"spawn_challenge":
			req = _make_request("spawn_challenge", {
				"enemy_count": 2,
				"radius": 4.0,
				"objective": "Defeat 2 test dummies to earn Fireball!",
				"reward_skill": "fireball_test_001",
				"reward_points": 2,
			})
	_send_request(req)


func _make_request(method: String, params: Dictionary) -> Dictionary:
	var id_v := _next_id
	_next_id += 1
	var req := {"jsonrpc": "2.0", "method": method, "params": params, "id": id_v}
	_pending[id_v] = _current_test
	return req


func _send_request(req: Dictionary) -> void:
	var s := JSON.stringify(req)
	print("[MCPTest] -> %s" % s)
	var err := _client.put_data((s + "\n").to_utf8_buffer())
	if err != OK:
		print("[MCPTest] send error: %d" % err)
		_results[_current_test] = false
		_run_next_test()


func _process(_delta: float) -> void:
	if _client == null:
		return
	_client.poll()
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var avail := _client.get_available_bytes()
	if avail <= 0:
		return
	var bytes: PackedByteArray = _client.get_data(avail)[1]
	if bytes.size() == 0:
		return
	var text := bytes.get_string_from_utf8()
	for line in text.split("\n", false):
		if line.strip_edges() == "":
			continue
		_handle_response(line)


func _handle_response(line: String) -> void:
	_timeout_timer.stop()
	var resp: Variant = JSON.parse_string(line)
	if resp == null or not resp is Dictionary:
		print("[MCPTest] <- invalid response: %s" % line)
		_results[_current_test] = false
		_run_next_test()
		return
	var id_v: Variant = resp.get("id", null)
	var test_name: String = _pending.get(id_v, _current_test)
	_pending.erase(id_v)
	print("[MCPTest] <- %s" % JSON.stringify(resp))
	# Validación
	var ok := _validate(test_name, resp)
	_results[test_name] = ok
	if ok:
		print("  [PASS] %s" % test_name)
	else:
		print("  [FAIL] %s" % test_name)
	_run_next_test()


func _validate(test_name: String, resp: Dictionary) -> bool:
	if test_name == "unknown_method":
		# Debe tener "error"
		return resp.has("error") and int(resp.get("error", {}).get("code", 0)) == -32601
	var result: Variant = resp.get("result", null)
	if result == null:
		return false
	match test_name:
		"ping":
			return result.get("pong", false) == true
		"get_player_state":
			return result.has("skill_points") and result.has("owned_skills")
		"grant_skill_points":
			return int(result.get("granted", 0)) == 5
		"grant_skill":
			return String(result.get("granted_skill", "")) == "kamehameha_001"
		"get_player_state_after_grants":
			return int(result.get("skill_points", 0)) >= 5 and result.has("owned_skills") and (result.get("owned_skills", []).size() >= 1)
		"spawn_enemy":
			return int(result.get("instance_id", 0)) != 0
		"set_objective":
			return String(result.get("objective_set", "")) == "Test objective from MCP"
		"list_skills":
			return int(result.get("count", 0)) >= 5
		"create_skill":
			return String(result.get("id", "")) == "fireball_test_001" and int(result.get("atoms_count", 0)) == 1
		"modify_skill":
			return String(result.get("id", "")) == "fireball_test_001"
		"spawn_challenge":
			return String(result.get("challenge_id", "")).begins_with("challenge_") and int(result.get("enemies_spawned", 0)) == 2
		_:
			return false


func _on_timeout() -> void:
	print("[MCPTest] timeout on test: %s" % _current_test)
	_results[_current_test] = false
	_run_next_test()


func _fail_all(reason: String) -> void:
	for t in _tests_to_run:
		_results[t] = false
	print("[MCPTest] all failed: %s" % reason)


func _finish() -> void:
	var pass_count := 0
	var fail_count := 0
	for k in _results.keys():
		if _results[k]:
			pass_count += 1
		else:
			fail_count += 1
	print("\n=== MCP Test Result: %d PASS / %d FAIL ===" % [pass_count, fail_count])
	if _client:
		_client.disconnect_from_host()
	get_tree().quit(0 if fail_count == 0 else 1)
