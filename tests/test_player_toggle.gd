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

# Test: toggle from player (Share button) — the full Share-button lifecycle.

var SKILL_BOOK_SCENE: PackedScene = preload("res://scenes/ui/menu.tscn")


func _initialize() -> void:
	print("=== PLAYER TOGGLE: Share button lifecycle ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	if player == null:
		print("FAIL: Player not found")
		quit()
		return
	print("[setup] Player found: %s" % player.name)

	# 1st toggle: open
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var sb: Node = _find_master_menu()
	var ok1: bool = sb != null and sb.visible and paused
	print("[1st toggle - open] %s (sb.visible=%s, paused=%s)" % ["PASS" if ok1 else "FAIL", sb.visible, paused])

	# 2nd toggle: close
	player._toggle_skill_book()
	await process_frame
	var ok2: bool = sb != null and not sb.visible and not paused
	print("[2nd toggle - close] %s (sb.visible=%s, paused=%s)" % ["PASS" if ok2 else "FAIL", sb.visible, paused])

	# 3rd toggle: open again (re-uses same instance)
	player._toggle_skill_book()
	await process_frame
	await process_frame
	var ok3: bool = sb != null and sb.visible and paused
	print("[3rd toggle - reopen] %s (sb.visible=%s, paused=%s)" % ["PASS" if ok3 else "FAIL", sb.visible, paused])

	# Now navigate to atributos and toggle from there (should close everything)
	# Tab order: skills(0) → mision(1) → objetivos(2) → atributos(3)
	sb._on_next_tab()
	await process_frame
	await process_frame
	sb._on_next_tab()
	await process_frame
	await process_frame
	sb._on_next_tab()
	await process_frame
	await process_frame
	var aa: Node = _find_menu_container().get_node_or_null("AttributeAllocator")
	var ok4: bool = not sb.visible and aa != null and aa.visible and paused
	print("[to-atributos] %s (sb=%s, aa=%s, paused=%s)" % ["PASS" if ok4 else "FAIL", sb.visible, aa.visible if aa else false, paused])

	# Toggle from here should close AA and REOPEN the master (UX: Share = "salir del sub-tab")
	player._toggle_skill_book()
	await process_frame
	var ok5: bool = sb.visible and not aa.visible and paused
	print("[toggle-from-atributos] %s (sb=%s, aa=%s, paused=%s)" % ["PASS" if ok5 else "FAIL", sb.visible, aa.visible, paused])
	if not ok5:
		print("    EXPECTED: sb.visible=true, aa.visible=false, paused=true (master reabierto)")

	# Now toggle again to fully close
	player._toggle_skill_book()
	await process_frame
	var ok6: bool = not sb.visible and not aa.visible and not paused
	print("[toggle-from-master] %s (sb=%s, aa=%s, paused=%s)" % ["PASS" if ok6 else "FAIL", sb.visible, aa.visible, paused])

	var all_pass: bool = ok1 and ok2 and ok3 and ok4 and ok5 and ok6
	print("\n=== RESULT: %s ===" % ("ALL PASS" if all_pass else "SOME FAILED"))
	quit()
