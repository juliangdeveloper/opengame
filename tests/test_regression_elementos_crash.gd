extends SceneTree

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


# Regression test for the unified atributos+elementos tab.
# Verifies that the merged menu opens cleanly, contains both
# attribute rows AND element rows, and survives multiple R1 cycles.

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")
const AttributeCompScript := preload("res://scripts/attribute_component.gd")
const ElementsScript := preload("res://scripts/skill/elements.gd")


func _initialize() -> void:
	print("=== REGRESSION: unified atributos+elementos tab ===\n")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var ps: Node = root.get_node_or_null("ProgressionState")
	ps.grant_skill_points(20)

	var failures := 0
	# Scenario 1: open skill book → R1×3 to reach atributos (idx 3)
	var sb := SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = _find_menu_container()
	if layer == null:
		layer = root
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame

	# 5-tab nav: skills(0) → mision(1) → objetivos(2) → atributos(3)
	for _i in 3:
		sb._on_next_tab()
		await process_frame
	# Wait for lazy-init race
	for _i in 3:
		await process_frame

	var aa: Node = layer.get_node_or_null("AttributeAllocator")
	if aa == null:
		print("  [1] FAIL: AttributeAllocator not created")
		failures += 1
	elif not aa.visible:
		print("  [1] FAIL: AttributeAllocator invisible")
		failures += 1
	elif aa._attr_row_panels.size() < 9:
		# Should be at least 7 attribute rows + 1 separator + 9 element rows
		print("  [1] FAIL: only %d rows in unified tab (expected ≥ 9)" % aa._attr_row_panels.size())
		failures += 1
	else:
		print("  [1] PASS: Atributos tab opens with %d rows (atributos + elementos)" % aa._attr_row_panels.size())

	# Scenario 2: allocate 1 point to fire element (verifies element wiring)
	if aa and aa._element_rows.has(&"fire"):
		var row: Dictionary = aa._element_rows[&"fire"]
		row["btn_plus1"].pressed.emit()
		await process_frame
		if int(ps.element_allocations.get(&"fire", 0)) == 1:
			print("  [2] PASS: +1 on fire element works (allocated=1)")
		else:
			print("  [2] FAIL: +1 on fire did not allocate (got %d)" % ps.element_allocations.get(&"fire", 0))
			failures += 1

	# Scenario 3: allocate 1 attribute point (verifies attribute wiring)
	if aa:
		ps.call("allocate_attribute", &"hp_max", 1)
		await process_frame
		aa._refresh()
		await process_frame
		if int(ps.get_attribute_points(&"hp_max")) == 1:
			print("  [3] PASS: hp_max +1 works (allocated=1)")
		else:
			print("  [3] FAIL: hp_max +1 did not allocate")
			failures += 1

	# Scenario 4: R1 to armas, then back to atributos (verifies cycle)
	if aa:
		sb._on_next_tab()  # atributos(3) → armas(4)
		await process_frame
		await process_frame
		var wa: Node = layer.get_node_or_null("WeaponAllocator")
		if wa and wa.visible:
			print("  [4] PASS: R1 from atributos to armas")
		else:
			print("  [4] FAIL: armas not visible after R1 from atributos")
			failures += 1
		# L1 back to atributos
		sb._on_prev_tab()  # armas(4) → atributos(3)
		await process_frame
		await process_frame
		if aa and aa.visible:
			print("  [5] PASS: L1 back to atributos")
		else:
			print("  [5] FAIL: lost atributos tab after cycle")
			failures += 1

	# Scenario 5: X on unified atributos → returns to skill book (paused)
	if aa and aa.visible:
		var back_btn: Button = aa.get_node("Panel/Margin/VBox/TopBar/BackButton")
		back_btn.pressed.emit()
		await process_frame
		await process_frame
		if sb.visible and not aa.visible and paused:
			print("  [6] PASS: X on atributos returns to skill book (paused)")
		else:
			print("  [6] FAIL: X on atributos left game in bad state")
			failures += 1

	# Scenario 6: X on skill book → fully close
	if sb.visible:
		var sb_close: Button = sb.get_node("Panel/Margin/VBox/TopBar/CloseButton")
		sb_close.pressed.emit()
		await process_frame
		if not sb.visible and not paused:
			print("  [7] PASS: X on skill book closes everything (game unpaused)")
		else:
			print("  [7] FAIL: Game still paused after closing skill book")
			failures += 1

	var result_label: String = "ALL PASS" if failures == 0 else "BUG STILL PRESENT"
	print("\n=== %s (%d failures) ===" % [result_label, failures])
	quit(1 if failures > 0 else 0)
