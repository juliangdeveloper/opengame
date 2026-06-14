extends SceneTree
## Regression test: arsenal no muestra armas del catálogo (solo owned).
## + Atributos: D-down desde ResetButton debe llegar al primer row
##   (antes el foco se perdía porque reset_button.focus_neighbor_bottom
##   no estaba seteado).

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")

func _find_master_menu() -> Node:
	var n: Node = root.find_child("Menu", true, false)
	if n == null:
		n = root.find_child("SkillBook", true, false)
	return n

func _find_menu_container() -> Node:
	var n: Node = root.find_child("MenuContainer", true, false)
	if n == null:
		n = root.find_child("MenuLayer", true, false)
	if n == null:
		n = root.find_child("SkillBookContainer", true, false)
	return n


func _initialize() -> void:
	print("=== REGRESSION: arsenal=no_catalog + atributos=focus_chain ===\n")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var ps: Node = root.get_node_or_null("ProgressionState")
	var failures := 0

	# === TEST 1: Arsenal solo muestra armas owned, no del catálogo ===
	# Add 1 owned weapon (a dagger), then open arsenal tab
	ps.grant_weapon(&"dagger")
	var sb: Node = SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = _find_menu_container()
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame
	# Navigate to armas (idx 5: skills → mision → objetivos → elementos → atributos → armas)
	for _i in 5:
		sb._on_next_tab()
		await process_frame

	var wa: Node = layer.get_node_or_null("WeaponAllocator")
	if wa == null:
		print("  [T1] FAIL: WeaponAllocator not created")
		failures += 1
	else:
		# Arsenal debe mostrar SOLO owned_weapons (no del catálogo).
		# Si el catálogo se mostrara, habría MUCHAS más rows que
		# ps.owned_weapons.size().
		var wcount: int = wa.weapons_container.get_child_count()
		var owned_count: int = ps.owned_weapons.size()
		if wcount == owned_count:
			print("  [T1] PASS: arsenal shows only owned weapons (rows=%d == owned=%d, no catalog)" % [wcount, owned_count])
		else:
			print("  [T1] FAIL: arsenal has %d rows (expected %d = owned_weapons.size, no catalog)" % [wcount, owned_count])
			failures += 1

	# Close menu
	sb._close()
	await process_frame
	awaits_done()

	# === TEST 2: Atributos focus chain — D-down from ResetButton → first row ===
	# Reopen menu and go to atributos (idx 4)
	sb.open()
	await process_frame
	for _i in 4:
		sb._on_next_tab()
		await process_frame

	var aa: Node = layer.get_node_or_null("AttributeAllocator")
	if aa == null:
		print("  [T2] FAIL: AttributeAllocator not created")
		failures += 1
	else:
		# Focus the reset button
		aa.reset_button.grab_focus()
		await process_frame
		var owner_before: Control = root.gui_get_focus_owner()
		var path_before: String = str(owner_before.get_path()) if owner_before else "<null>"
		if "ResetButton" not in path_before:
			print("  [T2] FAIL: couldn't grab focus on ResetButton (got %s)" % path_before)
			failures += 1
		else:
			# Send D-down via Viewport.push_input (works in headless mode).
			# Button 12 = D-pad down. We feed the master menu's _input directly
			# (same hybrid pattern as test_controller_navigation.gd).
			var ev_down := InputEventJoypadButton.new()
			ev_down.button_index = 12  # D-pad down
			ev_down.pressed = true
			root.push_input(ev_down)
			await process_frame
			await process_frame
			var ev_up := InputEventJoypadButton.new()
			ev_up.button_index = 12
			ev_up.pressed = false
			root.push_input(ev_up)
			await process_frame
			var owner_after: Control = root.gui_get_focus_owner()
			var path_after: String = str(owner_after.get_path()) if owner_after else "<null>"
			# Focus should have MOVED AWAY from ResetButton to a row button
			if owner_after == null:
				print("  [T2] FAIL: focus LOST after D-down from ResetButton (was %s, now <null>)" % path_before)
				failures += 1
			elif "ResetButton" in path_after:
				print("  [T2] FAIL: focus stayed on ResetButton (path=%s). D-down from ResetButton must reach a row." % path_after)
				failures += 1
			elif "AttributeAllocator" in path_after:
				print("  [T2] PASS: D-down from ResetButton → %s" % path_after.split("/")[-1])
			else:
				print("  [T2] FAIL: D-down from ResetButton went to wrong control: %s" % path_after)
				failures += 1

	# Cleanup
	sb._close()
	await process_frame

	var result: String = "ALL PASS" if failures == 0 else "BUG STILL PRESENT"
	print("\n=== %s (%d failures) ===" % [result, failures])
	quit(0 if failures == 0 else 1)


func awaits_done() -> void:
	await process_frame
	await process_frame
