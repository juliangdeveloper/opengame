extends SceneTree
## E2E realista: cargar play scene, abrir skill book, navegar a cada tab,
## y reportar qué pasa.

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")

var _passed := 0
var _failed := 0
var _errors: Array = []

func _check(name: String, cond: bool, hint: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s %s" % [name, hint])

func _initialize() -> void:
	# Cargar play scene PRIMERO (con autoloads, Player, etc.)
	var play_scene := load("res://scenes/play.tscn") as PackedScene
	var inst := play_scene.instantiate()
	root.add_child(inst)
	for i in 5:
		await process_frame

	var player: Node = root.find_child("Player", true, false)
	var ps: Node = root.get_node_or_null("ProgressionState")
	print("Player: %s, PS: %s" % [player != null, ps != null])

	# 1. Open skill book via _toggle_skill_book (como si presionara Share)
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	var sb: Node = null
	for c in root.get_children():
		if c.name == "SkillBook":
			sb = c
			break
	if not sb:
		# Buscar en layers
		for sub in root.find_children("*", "", true, false):
			if sub.name == "SkillBook":
				sb = sub
				break
	if not sb:
		print("ABORT")
		quit(1)
		return

	# 2. Verify master tab config
	print("master_tab=%s, tab_id=%s, _current_tab=%d" % [sb.is_master_tab, sb.tab_id, sb._current_tab])

	# 3. Click NextTabButton (avanza a elementos)
	print("\n--- Clicking NextTabButton (advance to elementos) ---")
	var next_btn: Button = sb.find_child("NextTabButton", true, false)
	print("NextTabButton: %s" % (next_btn != null))
	if next_btn:
		# Simular click
		next_btn.pressed.emit()
		for i in 3:
			await process_frame
	# Buscar EA
	var ea: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "ElementAllocator":
			ea = c
			break
	print("After NextTab: ElementAllocator found: %s, visible: %s" % [ea != null, ea.visible if ea else false])
	if ea:
		print("  ea.tab_id = %s" % ea.tab_id)
		print("  ea children count = %d" % ea.get_child_count())
		# Check if it's in the tree
		print("  ea is inside tree: %s" % ea.is_inside_tree())

	# 4. Press R1 to advance from elementos to atributos
	print("\n--- Calling _on_next_tab on master (R1 from elementos to atributos) ---")
	if sb.has_method("_on_next_tab"):
		sb._on_next_tab()
		for i in 3:
			await process_frame
	var aa: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "AttributeAllocator":
			aa = c
			break
	print("After R1: AttributeAllocator found: %s, visible: %s" % [aa != null, aa.visible if aa else false])

	# 5. Press R1 again to advance to Armas
	print("\n--- Calling _on_next_tab on master (R1 from atributos to armas) ---")
	if sb.has_method("_on_next_tab"):
		sb._on_next_tab()
		for i in 3:
			await process_frame
	var wa: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "WeaponAllocator":
			wa = c
			break
	print("After R1: WeaponAllocator found: %s" % (wa != null))
	if wa:
		print("  visible: %s" % wa.visible)
		print("  tab_id: %s" % wa.tab_id)
		print("  is inside tree: %s" % wa.is_inside_tree())
		print("  children: %d" % wa.get_child_count())
	else:
		print("  >>> WeaponAllocator is NULL!")
		# Buscar cualquier error en stderr buscando líneas SCRIPT ERROR
		# No podemos, así que vamos a buscar el script del WA
		var WA_SCRIPT := load("res://scripts/ui/weapon_allocator.gd")
		print("  weapon_allocator.gd loaded: %s" % (WA_SCRIPT != null))

	# 6. Press R1 to cycle back to skills
	print("\n--- Calling _on_next_tab on master (R1 from armas back to skills) ---")
	if sb.has_method("_on_next_tab"):
		sb._on_next_tab()
		for i in 3:
			await process_frame
	print("After R1: SkillBook visible: %s" % sb.visible)
	print("  _current_tab = %d" % sb._current_tab)

	# 7. Close via X button
	print("\n--- Clicking X (CloseButton) ---")
	var x_btn: Button = sb.find_child("CloseButton", true, false)
	print("CloseButton: %s" % (x_btn != null))
	if x_btn:
		x_btn.pressed.emit()
		for i in 3:
			await process_frame
	print("After X: SkillBook visible: %s" % sb.visible)
	print("  Game paused: %s" % paused)

	# 8. Re-open via toggle, close via toggle
	print("\n--- Re-open via toggle, close via toggle ---")
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	var sb2: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "SkillBook":
			sb2 = c
			break
	print("Re-opened SkillBook visible: %s" % (sb2.visible if sb2 else false))
	# Now toggle close
	player._toggle_skill_book()
	for i in 3:
		await process_frame
	var sb3: Node = null
	for c in root.find_children("*", "", true, false):
		if c.name == "SkillBook":
			sb3 = c
			break
	print("After second toggle: visible: %s" % (sb3.visible if sb3 else false))
	print("  Game paused: %s" % paused)

	print("\n=== TOTAL: %d/%d passed ===" % [_passed, _passed + _failed])
	quit(0 if _failed == 0 else 1)
