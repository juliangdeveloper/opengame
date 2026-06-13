extends SceneTree

# Final regression test for the user-reported bug:
# "Abrir la tabla de elementos en el Skill Book mata el juego"

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/skill_book.tscn")


func _initialize() -> void:
	print("=== REGRESSION: 'Elementos tab kills the game' ===\n")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var prog: Node = root.get_node_or_null("ProgressionState")
	prog.grant_skill_points(20)

	var failures := 0
	# Scenario 1: open skill book → press R1 → reach Elementos → verify it's visible and stays visible
	var sb := SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = root.find_child("SkillBookContainer", true, false)
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame

	# Press R1 to go to elementos
	sb._on_next_tab()
	# Wait enough frames for the buggy lazy-init race to surface (1+ frame)
	for i in 3:
		await process_frame

	var ea: Node = layer.get_node_or_null("ElementAllocator")
	if ea == null:
		print("  [1] FAIL: ElementAllocator was not created")
		failures += 1
	elif not ea.visible:
		print("  [1] FAIL: ElementAllocator invisible (the bug: visible=false after init)")
		failures += 1
	elif not ea._element_rows or ea._element_rows.size() != 9:
		print("  [1] FAIL: Element rows not built (size=%d, expected 9)" % ea._element_rows.size())
		failures += 1
	else:
		print("  [1] PASS: Elementos tab is open and showing 9 element rows")

	# Scenario 2: click +1 on physical, verify it works (would have crashed before fix? no, but verify)
	if ea and ea._element_rows and ea._element_rows.has(&"physical"):
		var row: Dictionary = ea._element_rows[&"physical"]
		row["btn_plus1"].pressed.emit()
		await process_frame
		if int(prog.element_allocations.get(&"physical", 0)) == 1:
			print("  [2] PASS: +1 button on physical element works (allocated=1)")
		else:
			print("  [2] FAIL: +1 did not allocate (got %d)" % prog.element_allocations.get(&"physical", 0))
			failures += 1

	# Scenario 3: cycle further: R1 to atributos, R1 to armas, then back to elementos
	if ea:
		sb._on_next_tab()  # elementos → atributos
		await process_frame
		await process_frame
		var aa: Node = layer.get_node_or_null("AttributeAllocator")
		if aa and aa.visible:
			print("  [3] PASS: Navigated from elementos to atributos")
		else:
			print("  [3] FAIL: Atributos not visible after R1 from elementos")
			failures += 1
		# Cycle back
		sb._on_next_tab()  # atributos → armas
		await process_frame
		await process_frame
		var wa: Node = layer.get_node_or_null("WeaponAllocator")
		if wa and wa.visible:
			print("  [4] PASS: Navigated from atributos to armas")
		else:
			print("  [4] FAIL: Armas not visible")
			failures += 1
		# Cycle back to elementos
		sb._on_next_tab()  # armas → skills
		sb._on_next_tab()  # skills → elementos
		await process_frame
		await process_frame
		if ea and ea.visible:
			print("  [5] PASS: Cycled back to elementos (still visible, not stuck)")
		else:
			print("  [5] FAIL: Lost the elementos tab after cycle")
			failures += 1

	# Scenario 4: press X on elementos → should go back to skill book (not crash)
	if ea and ea.visible:
		var close_btn: Button = ea.get_node("Panel/Margin/VBox/TopBar/CloseButton")
		close_btn.pressed.emit()
		await process_frame
		await process_frame
		if sb.visible and not ea.visible and paused:
			print("  [6] PASS: X on elementos returns to skill book (paused)")
		else:
			print("  [6] FAIL: X on elementos left game in bad state (sb=%s, ea=%s, paused=%s)" % [sb.visible, ea.visible, paused])
			failures += 1

	# Scenario 5: press X on skill book → should close everything
	if sb.visible:
		var sb_close: Button = sb.get_node("Panel/Margin/VBox/TopBar/CloseButton")
		sb_close.pressed.emit()
		await process_frame
		if not sb.visible and not paused:
			print("  [7] PASS: X on skill book closes everything (game unpaused)")
		else:
			print("  [7] FAIL: Game still paused after closing skill book (sb=%s, paused=%s)" % [sb.visible, paused])
			failures += 1

	var result_label: String = "ALL PASS" if failures == 0 else "BUG STILL PRESENT"
	print("\n=== %s (%d failures) ===" % [result_label, failures])
	quit(1 if failures > 0 else 0)
