extends SceneTree

# Verify the close flow: open skill book → switch to elementos → press X
# should go BACK to skill book (not leave game in paused-without-UI state).

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/skill_book.tscn")


func _initialize() -> void:
	print("=== CLOSE FLOW: Elementos X → back to Skill Book ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var sb := SKILL_BOOK_SCENE.instantiate()
	sb.name = "SkillBook"
	var layer: Node = root.find_child("SkillBookContainer", true, false)
	layer.add_child(sb)
	await process_frame
	sb.open()
	await process_frame
	# user_state should be: paused, sb.visible, no slaves
	var ok1: bool = sb.visible and paused
	print("[start] %s (sb.visible=%s, paused=%s)" % ["PASS" if ok1 else "FAIL", sb.visible, paused])

	# Navigate to elementos (R1)
	sb._on_next_tab()
	await process_frame
	await process_frame
	var ea: Node = layer.get_node_or_null("ElementAllocator")
	var ok2: bool = not sb.visible and ea.visible and paused
	print("[to-elementos] %s (sb=%s, ea=%s, paused=%s)" % ["PASS" if ok2 else "FAIL", sb.visible, ea.visible, paused])

	# Press X on Elementos → should go back to skill book
	var close_btn: Button = ea.get_node("Panel/Margin/VBox/TopBar/CloseButton")
	close_btn.pressed.emit()
	await process_frame
	await process_frame
	var ok3: bool = sb.visible and not ea.visible and paused
	print("[X-on-elementos] %s (sb=%s, ea=%s, paused=%s)" % ["PASS" if ok3 else "FAIL", sb.visible, ea.visible, paused])
	if not ok3:
		print("    EXPECTED: sb.visible=true, ea.visible=false, paused=true")
		print("    (X debe volver a la skill book, NO cerrar todo)")

	# Now press X on skill book → should fully close (paused=false)
	var sb_close_btn: Button = sb.get_node("Panel/Margin/VBox/TopBar/CloseButton")
	sb_close_btn.pressed.emit()
	await process_frame
	var ok4: bool = not sb.visible and not paused
	print("[X-on-skillbook] %s (sb=%s, paused=%s)" % ["PASS" if ok4 else "FAIL", sb.visible, paused])
	if not ok4:
		print("    EXPECTED: sb.visible=false, paused=false")

	var all_pass: bool = ok1 and ok2 and ok3 and ok4
	print("\n=== RESULT: %s ===" % ("ALL PASS" if all_pass else "SOME FAILED"))
	quit()
