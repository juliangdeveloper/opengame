extends SceneTree

func _find_master_menu() -> Node:
	var n: Node = root.find_child("Menu", true, false)
	if n == null:
		n = _find_master_menu()
	return n
## Test de navegación end-to-end con la play scene cargada (carga el InputMap real).

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")
const BalanceScript := preload("res://scripts/skill/balance.gd")
const WeaponCatalogScript := preload("res://scripts/skill/weapon_catalog.gd")
const ElementsScript := preload("res://scripts/skill/elements.gd")
const AttributeCompScript := preload("res://scripts/attribute_component.gd")

var _passed := 0
var _failed := 0

func _check(name: String, cond: bool, hint: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s %s" % [name, hint])

func _initialize() -> void:
	# Cargar la play scene para que el InputMap se registre
	var play_scene := load("res://scenes/play.tscn") as PackedScene
	if play_scene:
		var inst := play_scene.instantiate()
		root.add_child(inst)
		await process_frame
		await process_frame  # Dar 2 frames para que los autoloads y el InputMap estén listos
		print("Play scene loaded")
	else:
		print("WARNING: play scene not loadable, running without it")

	BalanceScript.load_config()
	WeaponCatalogScript.initialize()

	print("\n=== TEST 1: InputMap (con play scene cargada) ===")
	# Verificar que las acciones existen y tienen los button_index correctos
	var all_actions := InputMap.get_actions()
	_check("InputMap has actions", all_actions.size() > 10, "(got %d actions)" % all_actions.size())

	# Verificar que attack NO tiene joypad (legacy mouse-only)
	var attack_has_joypad := false
	for e in InputMap.action_get_events("attack"):
		if e is InputEventJoypadButton:
			attack_has_joypad = true
	_check("attack has NO joypad events (legacy mouse-only)", not attack_has_joypad)

	# Verificar que block NO tiene joypad
	var block_has_joypad := false
	for e in InputMap.action_get_events("block"):
		if e is InputEventJoypadButton:
			block_has_joypad = true
	_check("block has NO joypad events (legacy mouse-only)", not block_has_joypad)

	# Verificar parry/dodge sin joypad
	var parry_has_joypad := false
	for e in InputMap.action_get_events("parry"):
		if e is InputEventJoypadButton:
			parry_has_joypad = true
	_check("parry has NO joypad events", not parry_has_joypad)
	var dodge_has_joypad := false
	for e in InputMap.action_get_events("dodge"):
		if e is InputEventJoypadButton:
			dodge_has_joypad = true
	_check("dodge has NO joypad events", not dodge_has_joypad)

	# Verificar modifier_l1/r1/l2
	var mod_l1_btn := -1
	for e in InputMap.action_get_events("modifier_l1"):
		if e is InputEventJoypadButton:
			mod_l1_btn = e.button_index
	_check("modifier_l1 = button 9", mod_l1_btn == 9, "(got %d)" % mod_l1_btn)
	var mod_r1_btn := -1
	for e in InputMap.action_get_events("modifier_r1"):
		if e is InputEventJoypadButton:
			mod_r1_btn = e.button_index
	_check("modifier_r1 = button 10", mod_r1_btn == 10, "(got %d)" % mod_r1_btn)
	var mod_l2_btn := -1
	for e in InputMap.action_get_events("modifier_l2"):
		if e is InputEventJoypadButton:
			mod_l2_btn = e.button_index
	_check("modifier_l2 = button 7 (L2)", mod_l2_btn == 7, "(got %d)" % mod_l2_btn)

	# Verificar cast_skill_x/square/circle/triangle
	var expected := {"cast_skill_x": 0, "cast_skill_square": 2, "cast_skill_circle": 1, "cast_skill_triangle": 3}
	for action in expected:
		var found := -1
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton:
				found = e.button_index
		_check("%s = button %d" % [action, expected[action]], found == expected[action], "(got %d)" % found)

	# Verificar open_skill_book = button 4 (Share)
	var osb_btn := -1
	for e in InputMap.action_get_events("open_skill_book"):
		if e is InputEventJoypadButton:
			osb_btn = e.button_index
	_check("open_skill_book = button 4 (Share)", osb_btn == 4, "(got %d)" % osb_btn)

	# Verificar ui_scroll_up = button 11 (D-pad Up) y down = 12
	var usc_up := -1
	for e in InputMap.action_get_events("ui_scroll_up"):
		if e is InputEventJoypadButton:
			usc_up = e.button_index
	_check("ui_scroll_up = button 11 (D-pad Up)", usc_up == 11, "(got %d)" % usc_up)
	var usc_down := -1
	for e in InputMap.action_get_events("ui_scroll_down"):
		if e is InputEventJoypadButton:
			usc_down = e.button_index
	_check("ui_scroll_down = button 12 (D-pad Down)", usc_down == 12, "(got %d)" % usc_down)

	print("\n=== TEST 2: NO button collisions in caster actions ===")
	var caster_actions := ["attack", "block", "parry", "dodge",
		"cast_skill_x", "cast_skill_square", "cast_skill_circle", "cast_skill_triangle"]
	var btn_to_caster: Dictionary = {}
	for a in caster_actions:
		if not InputMap.has_action(a): continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton:
				var btn: int = e.button_index
				if not btn_to_caster.has(btn):
					btn_to_caster[btn] = []
				btn_to_caster[btn].append(a)
	var collisions: Array = []
	for btn in btn_to_caster:
		if btn_to_caster[btn].size() > 1:
			collisions.append("button %d in %s" % [btn, btn_to_caster[btn]])
	_check("NO button collisions in caster actions", collisions.is_empty(), "(%s)" % "; ".join(collisions))

	print("\n=== TEST 3: Player skill_bar defaults ===")
	# Cargar la play scene ya carga el Player. Acceder a él.
	var player: Node = root.find_child("Player", true, false)
	_check("Player exists in play scene", player != null)
	if player:
		_check("skill_bar has 8 slots", "skill_bar" in player and player.skill_bar.size() == 8)
		if player.skill_bar.size() >= 8:
			_check("slot 0 = light_attack_001", str(player.skill_bar[0]) == "light_attack_001")
			_check("slot 1 = empty", str(player.skill_bar[1]) == "")
			_check("slot 2 = esquivar_001", str(player.skill_bar[2]) == "esquivar_001")
			_check("slot 3 = defenderse_001", str(player.skill_bar[3]) == "defenderse_001")
			_check("slot 4 = kamehameha_001", str(player.skill_bar[4]) == "kamehameha_001")

	print("\n=== TEST 4: SkillBook ready in play scene ===")
	var sb: Node = _find_master_menu()
	# SkillBook solo existe si fue abierto. Esperar un frame más.
	# Verificar el tab_id via la scene file
	# (no se puede hasta que se abra)
	# En su lugar, verificar que el script tiene tab_id = "skills" por default
	var sb_src := FileAccess.get_file_as_string("res://scripts/ui/menu.gd")
	_check("menu.gd is_master_tab in _initialize",
		"is_master_tab = true" in sb_src)
	_check("menu.gd sets tab_id = &\"skills\"",
		"tab_id = &\"skills\"" in sb_src)

	print("\n=== TEST 5: HUD is smaller ===")
	var hud: Node = root.find_child("HUD", true, false)
	_check("HUD exists in play scene", hud != null)
	if hud:
		var sk := hud.get_node_or_null("SkillHUD")
		_check("HUD SkillHUD child exists", sk != null)
		if sk:
			# offset_left = -360.0
			_check("SkillHUD offset_left = -360.0", absf(sk.offset_left - (-360.0)) < 0.1,
				"(got %.1f)" % sk.offset_left)
			_check("SkillHUD offset_right = 360.0", absf(sk.offset_right - 360.0) < 0.1,
				"(got %.1f)" % sk.offset_right)
			_check("SkillHUD offset_top = -68.0", absf(sk.offset_top - (-68.0)) < 0.1,
				"(got %.1f)" % sk.offset_top)
			_check("SkillHUD offset_bottom = -12.0", absf(sk.offset_bottom - (-12.0)) < 0.1,
				"(got %.1f)" % sk.offset_bottom)
			# 8 cards + 1 separator = 9 children
			_check("SkillHUD has 9 children (8 cards + 1 separator)", sk.get_child_count() == 9,
				"(got %d)" % sk.get_child_count())

	print("\n=== TEST 6: Equipping weapons via PS ===")
	var ps: Node = root.get_node_or_null("ProgressionState")
	_check("ProgressionState autoload exists", ps != null)
	if ps:
		# Grant dagger para que equip funcione
		ps.call("grant_weapon", &"dagger")
		_check("dagger granted", &"dagger" in ps.owned_weapons)
		var ok: bool = ps.call("equip_weapon", &"dagger")
		_check("equip dagger", ok)
		_check("dagger is equipped", ps.equipped_weapon != null and str(ps.equipped_weapon.id) == "dagger")
		ps.call("equip_weapon", &"short_sword")
		_check("re-equip short_sword", str(ps.equipped_weapon.id) == "short_sword")

		# Allocate weapon points
		ps.skill_points = 5
		var alloc_ok: bool = ps.call("allocate_weapon", &"short_sword", &"dmg", 1)
		_check("allocate 1 pt to short_sword.dmg", alloc_ok)
		_check("skill_points consumed", int(ps.skill_points) == 4)
		ps.call("deallocate_weapon", &"short_sword", &"dmg", 1)
		_check("deallocate refunds", int(ps.skill_points) == 5)

	print("\n=== TEST 7: Esquivar/Defenderse skill atoms correct ===")
	var esquivar := load("res://data/skills/esquivar_001.tres")
	var defenderse := load("res://data/skills/defenderse_001.tres")
	if esquivar:
		_check("esquivar_001.tres loads", true)
		_check("esquivar has move atom with i_frames",
			esquivar.atoms.size() >= 1
			and esquivar.atoms[0].get("type", "") == "move"
			and esquivar.atoms[0].get("params", {}).get("i_frames", false))
		_check("esquivar has blink", esquivar.atoms[0].params.get("blink", false))
		_check("esquivar costs 18 stamina",
			float(esquivar.costs.get("stamina", 0.0)) == 18.0)
		_check("esquivar has 0.4s cooldown",
			float(esquivar.costs.get("cooldown", 0.0)) == 0.4)
	if defenderse:
		_check("defenderse_001.tres loads", true)
		_check("defenderse has status atom with parry_window",
			defenderse.atoms.size() >= 1
			and defenderse.atoms[0].get("type", "") == "status"
			and defenderse.atoms[0].get("params", {}).get("kind", "") == "parry_window")
		_check("defenderse parry_window duration 0.4",
			float(defenderse.atoms[0].params.get("duration", 0.0)) == 0.4)
		_check("defenderse costs 12 stamina",
			float(defenderse.costs.get("stamina", 0.0)) == 12.0)
		_check("defenderse has combo_trigger parry_riposte",
			defenderse.combo_triggers.size() >= 1
			and str(defenderse.combo_triggers[0].get("trigger_skill_id", "")) == "parry_riposte_001")

	print("\n=== TEST 8: Weapon damage calc with weapon + stats ===")
	# Test E2E: una short_sword (dmg=15) + 3 strength points
	# = (15 + 0) * (1 + 0.20*3) * 1.0 = 15 * 1.6 = 24
	# Con otro valor de strength:
	if ps:
		ps.skill_points = 0
		var sw := WeaponCatalogScript.get_weapon(&"short_sword")
		if sw and sw.has_method("get_scaled_damage"):
			var dmg_3str: float = sw.call("get_scaled_damage", 3.0, 0.0)
			_check("short_sword scaled with 3 str ≈ 24",
				absf(dmg_3str - 24.0) < 0.5,
				"(got %.2f, expected ~24)" % dmg_3str)
			var dmg_0str: float = sw.call("get_scaled_damage", 0.0, 0.0)
			_check("short_sword scaled with 0 str = 15",
				absf(dmg_0str - 15.0) < 0.1,
				"(got %.2f)" % dmg_0str)
			var dmg_5str: float = sw.call("get_scaled_damage", 5.0, 0.0)
			_check("short_sword scaled with 5 str ≈ 30",
				absf(dmg_5str - 30.0) < 0.5,
				"(got %.2f)" % dmg_5str)

	print("\n=== TEST 9: 6 tabs in menu ===")
	var menu_src := FileAccess.get_file_as_string("res://scripts/ui/menu.gd")
	_check("menu.gd has 6 TABS (skills, mision, objetivos, elementos, atributos, armas)",
		'&"skills"' in menu_src
		and '&"mision"' in menu_src
		and '&"objetivos"' in menu_src
		and '&"elementos"' in menu_src
		and '&"atributos"' in menu_src
		and '&"armas"' in menu_src)

	print("\n=== TOTAL: %d/%d passed ===" % [_passed, _passed + _failed])
	if _failed > 0:
		print("\nFAILED %d tests" % _failed)
		quit(1)
	else:
		print("\nALL PASS")
		quit(0)
