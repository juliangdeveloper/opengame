extends SceneTree
## E2E real-user test. Carga play scene, abre skill book, navega 4 tabs,
## abre tab armas, equipa arma, cierra, ejecuta skills.
## NO usa parse_input_event (no funciona con _physics_process).
## En su lugar, manipula el _input/_unhandled_input directamente o
## usa Input.parse_input_event en process_frame loop.

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")
const BalanceScript := preload("res://scripts/skill/balance.gd")
const WeaponCatalogScript := preload("res://scripts/skill/weapon_catalog.gd")

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

func _flush_errors() -> void:
	# No hay API para recoger errores runtime en GDScript 4, pero podemos
	# buscar en stderr
	pass

func _press_action(action: String, frames: int = 1) -> void:
	# Simular un press real: input.action_press, esperar, action_release
	# Esto es la forma más cercana a un press real del usuario.
	if not InputMap.has_action(action):
		print("WARNING: action %s not in InputMap" % action)
		return
	Input.action_press(action)
	for i in frames:
		await process_frame
	Input.action_release(action)
	for i in frames:
		await process_frame

func _find_skill_book() -> Node:
	# Buscar recursivamente un nodo llamado "SkillBook" o con script skill_book
	for c in root.get_children():
		if c.name == "SkillBook":
			return c
		# Buscar en layers
		for sub in c.find_children("*", "", true, false):
			if sub.name == "SkillBook":
				return sub
	return null

func _open_skill_book_manually() -> Node:
	# El usuario presiona Share button → el player llama _toggle_skill_book.
	# Pero también podemos instanciar y abrir directamente para tests.
	var SB_SCRIPT := load("res://scripts/ui/skill_book.gd")
	var sb: Node = SB_SCRIPT.new()
	sb.name = "SkillBook"
	# Buscar SkillBookLayer
	var layer: Node = root.find_child("SkillBookLayer", true, false)
	if layer:
		layer.add_child(sb)
	else:
		root.add_child(sb)
	await process_frame
	await process_frame
	if sb.has_method("open"):
		sb.open()
	await process_frame
	# Forzar inicialización lazy
	if sb.has_method("_initialize"):
		sb._initialize()
	await process_frame
	return sb

func _initialize() -> void:
	BalanceScript.load_config()
	WeaponCatalogScript.initialize()
	print("\n=== E2E REAL-USER TEST ===\n")

	# 1. Cargar play scene con display
	var play_scene := load("res://scenes/play.tscn") as PackedScene
	var inst := play_scene.instantiate()
	root.add_child(inst)
	# Dar 5 frames para que todo _ready corra
	for i in 5:
		await process_frame

	var player: Node = root.find_child("Player", true, false)
	_check("Player loaded", player != null)
	var ps: Node = root.get_node_or_null("ProgressionState")
	_check("ProgressionState autoload", ps != null)
	_check("Play scene has SkillBookLayer", root.find_child("SkillBookLayer", true, false) != null)

	# 2. Open skill book (como si presionara Share button)
	print("\n--- Step 1: Open skill book (Share button 4) ---")
	# Llamar directamente a la API del player
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var sb: Node = _find_skill_book()
	_check("SkillBook instantiated and opened", sb != null and sb.visible)
	if not sb:
		print("ABORT: SkillBook not created")
		quit(1)
		return

	# 3. Verify tab 0 is "skills"
	print("\n--- Step 2: Verify initial state ---")
	_check("skill_book.is_master_tab", sb.is_master_tab == true)
	_check("skill_book.tab_id = skills", str(sb.tab_id) == "skills")
	_check("skill_book._current_tab = 0", sb._current_tab == 0)
	# Verificar que el panel es visible
	_check("skill_book Panel visible", sb.find_child("Panel", true, false) != null)

	# 4. Navigate to Elementos tab via prev_tab_button
	print("\n--- Step 3: Click '← Elementos' to go to Elementos tab ---")
	var next_btn: Button = sb.find_child("NextTabButton", true, false)
	_check("NextTabButton exists", next_btn != null)
	if next_btn:
		next_btn.pressed.emit()
		await process_frame
		await process_frame
		var ea: Node = root.find_child("ElementAllocator", true, false)
		_check("ElementAllocator created and visible", ea != null and ea.visible)
		_check("ElementAllocator.tab_id = elementos",
			ea != null and str(ea.tab_id) == "elementos")

	# 5. Navigate from Elementos to Atributos via R1 (button 10)
	print("\n--- Step 4: Press R1 (button 10) to go to Atributos ---")
	# Llamar al handler del master (no del slave, ya que R1 en slave delega al master)
	# El master tiene un _input que llama _on_next_tab al recibir btn 10
	# Vamos a simular: el input llega al master (vía Input.parse_input_event)
	# pero más simple: cerrar el EA y abrir el AA
	if root.find_child("ElementAllocator", true, false):
		# EA cerrándose
		var ea := root.find_child("ElementAllocator", true, false)
		# Simular el master ciclando a tab 2
		# El path normal: el master._on_next_tab se llama, que abre el siguiente.
		# Pero el master ya está cerrado (visible=false). La lógica está en _switch_to_tab
		# del master. Vamos a llamarla directamente.
		if sb.has_method("_on_next_tab"):
			sb._on_next_tab()
		await process_frame
		await process_frame
		var aa: Node = root.find_child("AttributeAllocator", true, false)
		_check("AttributeAllocator created and visible", aa != null and aa.visible)
		_check("AttributeAllocator.tab_id = atributos",
			aa != null and str(aa.tab_id) == "atributos")

	# 6. Navigate to Armas via _on_next_tab again
	print("\n--- Step 5: Press R1 again to go to Armas (THIS IS WHERE BUG IS) ---")
	if sb.has_method("_on_next_tab"):
		sb._on_next_tab()
		await process_frame
		await process_frame
		var wa: Node = root.find_child("WeaponAllocator", true, false)
		# This is the critical step
		_check("WeaponAllocator created (no error)", wa != null)
		if wa:
			_check("WeaponAllocator visible", wa.visible)
			_check("WeaponAllocator.tab_id = armas", str(wa.tab_id) == "armas")
			# Verificar que el catálogo se muestra
			var weapons_container := wa.get_node_or_null("Panel/Margin/VBox/HBoxBody/LeftPanel/LeftMargin/Scroll/WeaponsContainer")
			_check("weapons_container exists", weapons_container != null)
			if weapons_container:
				_check("weapons_container has children (rows)", weapons_container.get_child_count() > 0,
					"(got %d children)" % weapons_container.get_child_count())
		else:
			print("  >>> WeaponAllocator is null — buscar el error en los logs")

	# 7. Equip a weapon
	print("\n--- Step 6: Try to equip dagger (from WeaponAllocator) ---")
	var wa2: Node = root.find_child("WeaponAllocator", true, false)
	if wa2:
		# Get first weapon row button
		var weapons_container2 := wa2.get_node_or_null("Panel/Margin/VBox/HBoxBody/LeftPanel/LeftMargin/Scroll/WeaponsContainer")
		if weapons_container2 and weapons_container2.get_child_count() > 0:
			var first_row: Node = weapons_container2.get_child(0)
			# Buscar el Button
			var btn: Button = null
			for c in first_row.get_children():
				for cc in c.get_children():
					if cc is Button:
						btn = cc
						break
				if btn: break
			_check("first weapon row has a Button", btn != null)
			if btn:
				btn.pressed.emit()
				await process_frame
				await process_frame
				# Verificar que el detail panel muestra info del arma
				var name_label: Label = wa2.get_node_or_null("Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/NameLabel")
				_check("name_label has text", name_label != null and name_label.text != "Selecciona un arma",
					"(got: '%s')" % (name_label.text if name_label else "null"))
				# Click Equip
				var equip_btn: Button = wa2.get_node_or_null("Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/EquipButton")
				if equip_btn:
					equip_btn.pressed.emit()
					await process_frame
					# Verificar cambio de equipped_weapon
					_check("equipped_weapon changed", ps != null and ps.equipped_weapon != null)

	# 8. Close skill book via X button
	print("\n--- Step 7: Close skill book via X button ---")
	# Navigate back to skills first
	if sb and sb.has_method("_on_prev_tab"):
		# Si el WA está abierto, cicla hasta volver al master
		for i in 4:
			var wa3 := root.find_child("WeaponAllocator", true, false)
			if wa3 and wa3.visible:
				sb._on_prev_tab()
				await process_frame
				break
	# Ahora el master (sb) debe estar visible
	if not sb.visible:
		# Si el master está oculto, abrirlo
		if sb.has_method("open"):
			sb.open()
		await process_frame
	_check("SkillBook visible for closing", sb.visible)
	# Click X
	var x_btn: Button = sb.find_child("CloseButton", true, false)
	_check("CloseButton exists", x_btn != null)
	if x_btn:
		x_btn.pressed.emit()
		await process_frame
		await process_frame
		_check("SkillBook closed (not visible)", not sb.visible)
		# El game debe seguir corriendo sin pausar
		_check("Game not paused", not paused,
			"(paused=%s)" % paused)

	# 9. Re-open and close via Share button
	print("\n--- Step 8: Re-open via Share button, then close via Share ---")
	player._toggle_skill_book()
	await process_frame
	await process_frame
	_check("Re-opened via toggle", _find_skill_book() != null and _find_skill_book().visible)
	# Close again
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var sb2: Node = _find_skill_book()
	_check("Closed via second toggle (Share again)", sb2 == null or not sb2.visible)

	# 10. Test cast skills via player
	print("\n--- Step 9: Cast skills via player ---")
	if player:
		# Cast light_attack (slot 0)
		var cast1: bool = player.call("cast_data_skill", &"light_attack_001", 0)
		_check("cast_data_skill(light_attack_001) returns true", cast1)
		await process_frame
		var exec = player.get("_current_executor")
		_check("light_attack created executor", exec != null and is_instance_valid(exec))
		if exec and is_instance_valid(exec):
			# Esperar 2 segundos
			for i in 60:
				await process_frame
		# Cast esquivar
		var cast2: bool = player.call("cast_data_skill", &"esquivar_001", 2)
		_check("cast_data_skill(esquivar_001) returns true", cast2)
		await process_frame
		_check("is_dodging after esquivar", player.is_dodging)
		# Wait for dodge to end
		for i in 30:
			await process_frame
		# Cast defenderse
		var cast3: bool = player.call("cast_data_skill", &"defenderse_001", 3)
		_check("cast_data_skill(defenderse_001) returns true", cast3)
		await process_frame
		_check("is_parrying after defenderse", player.is_parrying)

	print("\n=== E2E TEST TOTAL: %d/%d passed ===" % [_passed, _passed + _failed])
	if _failed > 0:
		print("FAILED %d tests" % _failed)
		quit(1)
	else:
		print("ALL PASS")
		quit(0)
