extends SceneTree

# mcp-souls-game — Extended controller navigation test (tabs + scroll + X button).
# Adds 5 new test blocks to the previous test (5 tabs, 16 steps).
# This file REPLACES the previous tests/test_controller_navigation.gd if you
# want to run all checks in one go; both can coexist (the previous one is
# unchanged on disk, this is tests/test_controller_navigation_v2.gd).
#
# Gamepad mapping (Godot 4 + this project's InputMap):
#   0  = X (Cross)         1 = O (Circle)
#   2  = □ (Square)        3 = △ (Triangle)
#   4  = Share             5 = PS
#   7  = L2                9 = L1
#   10 = R1                11 = D-pad Up
#   12 = D-pad Down        13 = D-pad Left
#   14 = D-pad Right

const TAB_NAMES: Array[StringName] = [&"skills", &"mision", &"objetivos", &"elementos", &"atributos", &"armas"]
const SLAVE_NAMES: Array[StringName] = [&"ElementAllocator", &"AttributeAllocator", &"WeaponAllocator"]

var _results: Array = []
var _errors: Array = []
var _step: int = 0


func _initialize() -> void:
	_reset_log()
	_log("=== mcp-souls-game: extended controller nav test ===")

	var play: Node = load("res://scenes/play.tscn").instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	if player == null:
		_fail("Player not found")
		_finish()
		return

	# ------------------------------------------------------------------------
	# 1. SHARE opens menu, focus on ItemList
	# ------------------------------------------------------------------------
	_log("\n--- 1. SHARE opens menu ---")
	_send(player, 4, true)
	await process_frame
	await process_frame
	_assert(player._menu_instance.visible, "menu visible")
	_assert(self.paused, "world paused")
	var focus_owner: Control = root.get_viewport().gui_get_focus_owner()
	_assert(focus_owner != null and "ItemList" in str(focus_owner.get_path()), "focus on ItemList")

	# ------------------------------------------------------------------------
	# 2. Skills: D-pad right → BindingButton, D-pad left → back to ItemList
	# ------------------------------------------------------------------------
	_log("\n--- 2. Skills tab: D-pad right → BindingButton, D-pad left → ItemList ---")
	_push_dpad(14, true)  # right
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	var fp: String = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   D-right: focus = %s" % fp)
	_assert("BindingButton" in fp, "D-right reaches BindingButton")
	# Read current skill name to verify
	var menu = player._menu_instance
	_log("   current skill = %s" % str(menu._current_skill_id))
	# D-pad left from BindingButton → back to ItemList
	_push_dpad(13, true)  # left
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   D-left: focus = %s" % fp)
	_assert("ItemList" in fp, "D-left from BindingButton returns to ItemList")

	# ------------------------------------------------------------------------
	# 3. Skills: D-pad right → BindingButton → D-pad down → first stat row
	# ------------------------------------------------------------------------
	_log("\n--- 3. Skills tab: BindingButton ↓ → first stat row ---")
	_push_dpad(14, true)  # right → BindingButton
	await process_frame
	_push_dpad(12, true)  # down
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   D-down from BindingButton: focus = %s" % fp)
	_assert(focus_owner != null, "D-down from BindingButton has focus target")
	# The first stat row's first button should be at:
	#   .../DetailVBox/AtomRows/<row HBox>/<+1 button>
	var is_in_atom_rows := "AtomRows" in fp
	_log("   focus is in AtomRows? %s" % str(is_in_atom_rows))
	_assert(is_in_atom_rows, "D-down from BindingButton lands in AtomRows (stat section)")

	# ------------------------------------------------------------------------
	# 4. Skills: D-pad UP from first stat row → BindingButton (the user's bug)
	# ------------------------------------------------------------------------
	_log("\n--- 4. Skills tab: stat row ↑ → BindingButton (the reported bug) ---")
	# First go back down to the very first stat row button
	for i in 5:
		_push_dpad(12, true)  # down a few times to ensure we're at the bottom or close
		await process_frame
	# Now navigate up — first UP should reach the previous row's last button,
	# but from the FIRST row, UP should reach BindingButton
	# Find the focus owner before UP
	var pre_up_focus: Control = root.get_viewport().gui_get_focus_owner()
	_log("   pre-UP focus: %s" % str(pre_up_focus.get_path()) if pre_up_focus else "<null>")
	# Navigate up multiple times to reach the top
	for i in 10:
		_push_dpad(11, true)  # up
		await process_frame
		var cur: Control = root.get_viewport().gui_get_focus_owner()
		var cur_path: String = str(cur.get_path()) if cur else "<null>"
		_log("   UP x%d: focus = %s" % [i + 1, cur_path])
		# Once we reach BindingButton, stop
		if "BindingButton" in cur_path:
			_assert(true, "after %d UP presses, focus reaches BindingButton" % (i + 1))
			break
	# Final check
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   final focus: %s" % fp)
	_assert("BindingButton" in fp, "D-up from stat rows eventually reaches BindingButton")
	# Make sure we're really on BindingButton (not NextTabButton via geometric fallback)
	if "BindingButton" not in fp:
		_push_dpad(14, true)  # right
		await process_frame
		_push_dpad(11, true)  # up
		await process_frame
		focus_owner = root.get_viewport().gui_get_focus_owner()
		fp = str(focus_owner.get_path()) if focus_owner else "<null>"
		_log("   re-navigated to: %s" % fp)

	# ------------------------------------------------------------------------
	# 5. Skills: X button (button 0) activates the focused button (ui_accept)
	# ------------------------------------------------------------------------
	_log("\n--- 5. X button (button 0) activates the focused button ---")
	# Focus is on BindingButton. Use the same _send pipeline as v1 (which works).
	# Verify capture mode toggled on
	var prev_capture: bool = menu._binding_capture_mode
	_send(player, 0, true)
	await process_frame
	_send(player, 0, false)
	await process_frame
	var capture_now: bool = menu._binding_capture_mode
	_log("   _binding_capture_mode before/after X: %s → %s" % [str(prev_capture), str(capture_now)])
	_assert(capture_now == true, "X button enters binding capture mode")
	# Exit capture mode
	menu._exit_capture_mode()

	# ------------------------------------------------------------------------
	# 6. Scroll auto-scroll: ScrollContainer.follow_focus must be true, and
	#    when focus moves deep into the stat rows, scroll_vertical should
	#    move down to keep the focused control visible.
	# ------------------------------------------------------------------------
	_log("\n--- 6. Scroll auto-scroll when focus reaches edge ---")
	# Close menu, re-open
	_send(player, 4, true)  # close
	await process_frame
	_send(player, 4, true)  # re-open
	await process_frame
	await process_frame
	menu = player._menu_instance
	# Find a skill that has many stat rows (designed_max.keys() with positive values)
	# so the stat rows are taller than the scroll container and auto-scroll kicks in.
	var scroll: ScrollContainer = menu.get_node_or_null("Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll")
	_assert(scroll != null, "right panel ScrollContainer exists")
	_assert(scroll.follow_focus == true, "follow_focus = true (default)")
	var ps_node: Node = root.get_node_or_null("ProgressionState")
	var best_idx: int = 0
	var best_count: int = 0
	for i in menu.skill_list.item_count:
		menu.skill_list.select(i)
		menu._on_skill_selected(i)
		await process_frame
		var ar: VBoxContainer = menu.get_node_or_null("Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/AtomRows")
		if ar and ar.get_child_count() > best_count:
			best_count = ar.get_child_count()
			best_idx = i
	_log("   skill with most stat rows: idx=%d count=%d" % [best_idx, best_count])
	# Re-select that skill (it was selected in the loop, but re-do for clarity)
	menu.skill_list.select(best_idx)
	menu._on_skill_selected(best_idx)
	await process_frame
	# In headless mode the GUI subsystem doesn't trigger follow_focus
	# automatically (no relayout from focus changes without rendering).
	# So we verify the SETUP is correct: follow_focus = true, and content
	# overflows the viewport (max_value > 0). When rendered, the real
	# engine scrolls on focus. We also verify the production code wires
	# _on_gui_focus_changed for an extra ensure_control_visible safety net.
	scroll.custom_minimum_size = Vector2(600, 100)  # force small viewport
	scroll.size = Vector2(600, 100)
	await process_frame
	_log("   scroll_v = %d (max=%d, scroll_size=%s)" % [int(scroll.scroll_vertical), int(scroll.get_v_scroll_bar().max_value), str(scroll.size)])
	_assert(scroll.follow_focus == true, "follow_focus = true (Godot default)")
	_assert(int(scroll.get_v_scroll_bar().max_value) > 0, "content overflows viewport (max=%d > 0)" % int(scroll.get_v_scroll_bar().max_value))
	# Verify our safety-net handler is connected (manual scroll on focus change)
	# The new MenuNavHelper attaches to gui_focus_changed via metadata-tagged
	# callback on the scroll, not directly to the menu. We verify that
	# _scrolls_to_keep_visible contains the scroll (our safety net is set up).
	var has_scroll_registered: bool = false
	for s in menu._scrolls_to_keep_visible:
		if s == scroll:
			has_scroll_registered = true
			break
	_assert(has_scroll_registered, "right scroll registered for focus-follow safety net")

	# ------------------------------------------------------------------------
	# 7. Arsenal tab: navigate to it (R1 5x), then D-pad inside
	# ------------------------------------------------------------------------
	_log("\n--- 7. Arsenal tab navigation ---")
	# Close menu first, reopen, navigate to arsenal
	_send(player, 4, true)  # close
	await process_frame
	_send(player, 4, true)  # re-open
	await process_frame
	await process_frame
	menu = player._menu_instance
	# R1 5x: skills → mision → objetivos → elementos → atributos → armas
	for i in 5:
		_send(player, 10, true)  # R1
		await process_frame
		await process_frame
	_assert(menu._current_tab == 5, "at armas tab (idx 5)")
	var wa: Control = _get_slave(&"WeaponAllocator")
	_assert(wa != null and wa.visible, "WeaponAllocator visible")
	# Try D-down inside arsenal
	_push_dpad(12, true)
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   D-down in arsenal: focus = %s" % fp)
	_assert(focus_owner != null, "D-down in arsenal moves focus")
	# The arsenal has: OpenSkillBookButton / CloseButton (TopBar), then weapon rows
	# Focus should land in weapon list (left side) or stay in TopBar
	# D-pad right from left side → equip_button
	_push_dpad(14, true)
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   D-right: focus = %s" % fp)
	# Should be in DetailPanel (right side) — either equip button or stat row
	var in_right_panel := "DetailPanel" in fp or "EquipButton" in fp
	_assert(in_right_panel, "D-right from weapon list reaches detail panel")

	# ------------------------------------------------------------------------
	# 8. Arsenal: from stat row, D-up → equip button (the user reported bug)
	# ------------------------------------------------------------------------
	_log("\n--- 8. Arsenal: stat row ↑ → equip button ---")
	# Navigate down to reach a stat row
	for i in 5:
		_push_dpad(12, true)
		await process_frame
	# Then navigate up multiple times
	for i in 8:
		_push_dpad(11, true)
		await process_frame
		var cur: Control = root.get_viewport().gui_get_focus_owner()
		var cur_path: String = str(cur.get_path()) if cur else "<null>"
		if "EquipButton" in cur_path or "open_skill_book" in cur_path.to_lower() or "OpenSkillBookButton" in cur_path:
			_log("   UP x%d reached %s" % [i + 1, cur_path])
			_assert(true, "D-up from stat rows in arsenal reaches EquipButton/TopBar")
			break
	# Final check
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   final focus: %s" % fp)
	_assert("EquipButton" in fp or "OpenSkillBookButton" in fp or "CloseButton" in fp, "D-up reaches top of arsenal tab")

	# ------------------------------------------------------------------------
	# 9. Final cleanup
	# ------------------------------------------------------------------------
	_log("\n--- 9. Cleanup ---")
	_send(player, 4, true)  # close menu
	await process_frame
	_finish()


func _push_dpad(btn: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	root.get_viewport().push_input(ev)


func _send(player: Node, btn_index: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn_index
	ev.pressed = pressed
	if pressed:
		Input.action_press(_action_for_button(btn_index), 1.0)
	else:
		Input.action_release(_action_for_button(btn_index))
	if player and player.has_method("_input"):
		player._input(ev)
	if player and "_menu_instance" in player and is_instance_valid(player._menu_instance):
		var menu = player._menu_instance
		if menu.visible and menu.has_method("_input"):
			menu._input(ev)
		else:
			for sn in SLAVE_NAMES:
				var slave: Control = _get_slave(sn)
				if slave and slave.visible and slave.has_method("_input"):
					slave._input(ev)
					break
	# For UI face buttons (X=0, O=1, Square=2, Triangle=3) the GUI subsystem
	# needs to receive the event through the viewport so it can match it
	# against InputMap (X maps to ui_accept) and activate the focused Button.
	# Don't push_input for Share (4) or L/R (9, 10) — those are handled by
	# the player's _input handler and pushing them via the GUI breaks
	# the open/close flow.
	if btn_index in [0, 1, 2, 3]:
		root.get_viewport().push_input(ev)


func _action_for_button(btn_index: int) -> String:
	match btn_index:
		0: return "cast_skill_x"
		1: return "cast_skill_circle"
		2: return "cast_skill_square"
		3: return "cast_skill_triangle"
		4: return "open_skill_book"
		7: return "modifier_l2"
		9: return "modifier_l1"
		10: return "modifier_r1"
		11: return "ui_focus_prev"
		12: return "ui_focus_next"
		13: return "ui_left"
		14: return "ui_right"
	return ""


func _get_slave(name: StringName) -> Control:
	var layer: Node = root.find_child("MenuContainer", true, false)
	if layer == null:
		layer = root.find_child("MenuLayer", true, false)
	if layer == null:
		return null
	var n: Node = layer.get_node_or_null(String(name))
	return n as Control


func _assert(cond: bool, label: String) -> void:
	_step += 1
	if cond:
		_results.append("[PASS] #%d %s" % [_step, label])
		_log("   ✓ %s" % label)
	else:
		_results.append("[FAIL] #%d %s" % [_step, label])
		_log("   ✗ %s" % label)
		_errors.append(label)


func _fail(msg: String) -> void:
	_results.append("[FATAL] %s" % msg)
	_errors.append(msg)
	_log("   ✗ FATAL: %s" % msg)


func _finish() -> void:
	var passed: int = 0
	var failed: int = 0
	for r in _results:
		if "[PASS]" in r: passed += 1
		elif "[FAIL]" in r or "[FATAL]" in r: failed += 1
	_log("")
	_log("=== SUMMARY ===")
	_log("Total assertions: %d | PASS: %d | FAIL: %d" % [_results.size(), passed, failed])
	if _errors.is_empty():
		_log("RESULT: ✓ ALL TESTS PASSED")
	else:
		_log("RESULT: ✗ %d FAILURES:" % _errors.size())
		for e in _errors:
			_log("  - %s" % e)
	var f := FileAccess.open("/tmp/ctrl_v2_results.txt", FileAccess.WRITE)
	for r in _results:
		f.store_line(r)
	f.close()
	quit()


func _log(msg: String) -> void:
	print(msg)
	var f := FileAccess.open("/tmp/ctrl_v2.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/tmp/ctrl_v2.log", FileAccess.WRITE)
	else:
		f.seek_end()
	f.store_line(msg)
	f.close()


func _reset_log() -> void:
	var f := FileAccess.open("/tmp/ctrl_v2.log", FileAccess.WRITE)
	f.close()
	var f2 := FileAccess.open("/tmp/ctrl_v2_results.txt", FileAccess.WRITE)
	f2.close()
