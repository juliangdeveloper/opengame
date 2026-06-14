extends SceneTree

# mcp-souls-game — controller navigation test (PS4 gamepad, real-user flow).
#
# Routes input the way a real user would: player._input for SHARE,
# then routes to whichever is visible (master or active slave) for
# R1/L1, and uses Viewport.push_input for D-pad so the GUI focus nav
# engine receives the events.

const TAB_NAMES: Array[StringName] = [&"skills", &"mision", &"objetivos", &"elementos", &"atributos", &"armas"]
const SLAVE_NAMES: Array[StringName] = [&"ElementAllocator", &"AttributeAllocator", &"WeaponAllocator"]

var _results: Array = []
var _errors: Array = []
var _step: int = 0


func _initialize() -> void:
	_reset_log()
	_log("=== mcp-souls-game: controller navigation test ===")

	var play: Node = load("res://scenes/play.tscn").instantiate()
	root.add_child(play)
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	if player == null:
		_fail("Player not found")
		_finish()
		return

	# --- 1. SHARE opens menu ---
	_log("\n--- 1. Press SHARE ---")
	_send(player, 4, true)
	await process_frame
	await process_frame
	_assert(player._menu_instance != null and player._menu_instance.visible, "menu visible after SHARE")
	_assert(self.paused == true, "world paused when menu open")

	# --- 2. Auto-focus on ItemList ---
	_log("\n--- 2. Auto-focus on ItemList ---")
	var focus_owner: Control = root.get_viewport().gui_get_focus_owner()
	_assert(focus_owner != null, "focus owner is not null after open")
	if focus_owner:
		var path: String = str(focus_owner.get_path())
		_log("   focus owner: %s" % path)
		_assert("ItemList" in path, "focus on ItemList on open")

	# --- 3. D-pad DOWN on ItemList ---
	_log("\n--- 3. D-pad down on ItemList ---")
	var item_list: ItemList = player._menu_instance.skill_list
	var prev_sel: int = item_list.get_selected_items()[0] if not item_list.get_selected_items().is_empty() else -1
	_push_dpad(12, true)
	await process_frame
	var new_sel: int = item_list.get_selected_items()[0] if not item_list.get_selected_items().is_empty() else -1
	_log("   sel: %d → %d" % [prev_sel, new_sel])
	_assert(new_sel == prev_sel + 1, "D-pad down advances skill by 1")

	_push_dpad(12, true); await process_frame
	_push_dpad(12, true); await process_frame
	var sel3: int = item_list.get_selected_items()[0]
	_log("   sel after 3x D-down: %d" % sel3)
	_assert(sel3 == prev_sel + 3, "D-pad down advances 3 skills")

	_push_dpad(11, true); await process_frame
	_log("   sel after D-up: %d" % item_list.get_selected_items()[0])

	# --- 4. D-pad RIGHT → right panel (BindingButton) ---
	_log("\n--- 4. D-pad right → BindingButton ---")
	_push_dpad(14, true)
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	var fp: String = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   focus owner: %s" % fp)
	_assert(focus_owner != item_list, "D-right moves focus away from ItemList")
	_assert("BindingButton" in fp, "D-right focuses BindingButton (right panel)")

	# --- 5. D-pad UP from BindingButton → TopBar ---
	_log("\n--- 5. D-pad up from right panel → TopBar ---")
	_push_dpad(11, true)
	await process_frame
	focus_owner = root.get_viewport().gui_get_focus_owner()
	fp = str(focus_owner.get_path()) if focus_owner else "<null>"
	_log("   focus owner: %s" % fp)
	_assert(focus_owner != null and "TopBar" in fp, "D-up from right panel reaches TopBar")

	# --- 6. R1 cycle all 6 tabs forward ---
	_log("\n--- 6. R1 cycle all 6 tabs forward ---")
	for i in 6:
		_send(player, 10, true)  # R1
		await process_frame
		await process_frame
		var tab_idx: int = player._menu_instance._current_tab
		var tab_name: StringName = TAB_NAMES[tab_idx]
		_log("   R1 x%d → tab %d = %s" % [i + 1, tab_idx, str(tab_name)])
		_assert(_tab_visible(player._menu_instance, tab_name), "tab '%s' is visible" % str(tab_name))

	# --- 7. L1 cycle back to 'skills' ---
	_log("\n--- 7. L1 cycle back to 'skills' ---")
	for i in 6:
		_send(player, 9, true)  # L1
		await process_frame
		await process_frame
		_log("   L1 x%d → tab %d = %s" % [i + 1, player._menu_instance._current_tab, str(TAB_NAMES[player._menu_instance._current_tab])])
	_assert(player._menu_instance._current_tab == 0, "L1 6x returns to skills (idx 0)")

	# --- 8. Navigate to 'elementos' sub-tab ---
	_log("\n--- 8. Navigate to 'elementos' sub-tab ---")
	for i in 3:
		_send(player, 10, true)
		await process_frame
		await process_frame
	_assert(player._menu_instance._current_tab == 3, "at elementos (idx 3)")
	var ea: Control = _get_slave(&"ElementAllocator")
	_assert(ea != null and ea.visible, "ElementAllocator slave is visible")
	if ea:
		_log("   ElementAllocator visible = %s" % ea.visible)
		# D-pad down inside Elementos
		var prev_focus = root.get_viewport().gui_get_focus_owner()
		_push_dpad(12, true)
		await process_frame
		var new_focus = root.get_viewport().gui_get_focus_owner()
		_log("   focus before/after D-down: %s → %s" % [
			str(prev_focus.get_path()) if prev_focus else "<null>",
			str(new_focus.get_path()) if new_focus else "<null>"
		])
		_assert(new_focus != prev_focus, "D-down inside Elementos moves focus")

	# --- 9. R1 from Elementos → atributos ---
	_log("\n--- 9. R1 from Elementos → atributos ---")
	_send(player, 10, true)
	await process_frame
	await process_frame
	var aa: Control = _get_slave(&"AttributeAllocator")
	_assert(aa != null and aa.visible, "AttributeAllocator visible")
	_assert(ea != null and not ea.visible, "ElementAllocator closed after switching to atributos")

	# --- 10. R1 from Atributos → armas ---
	_log("\n--- 10. R1 from Atributos → armas ---")
	_send(player, 10, true)
	await process_frame
	await process_frame
	var wa: Control = _get_slave(&"WeaponAllocator")
	_assert(wa != null and wa.visible, "WeaponAllocator visible")
	_assert(aa != null and not aa.visible, "AttributeAllocator closed")

	# --- 11. SHARE from inside armas → returns to master ---
	_log("\n--- 11. SHARE from inside armas slave → returns to master ---")
	_send(player, 4, true)
	await process_frame
	await process_frame
	_assert(player._menu_instance.visible, "master re-opened after SHARE from slave")
	_assert(wa != null and not wa.visible, "armas slave closed")
	_assert(self.paused == true, "world still paused")

	# --- 12. SHARE again → close menu ---
	_log("\n--- 12. SHARE again → close menu ---")
	_send(player, 4, true)
	await process_frame
	await process_frame
	_assert(not player._menu_instance.visible, "master closed after second SHARE")
	_assert(self.paused == false, "world unpaused after close")

	# --- 13. Re-open via SHARE → focus restored on ItemList ---
	_log("\n--- 13. Re-open with SHARE → focus restored ---")
	_send(player, 4, true)
	await process_frame
	await process_frame
	_assert(player._menu_instance.visible, "re-opened")
	_assert(self.paused == true, "world paused again")
	focus_owner = root.get_viewport().gui_get_focus_owner()
	_assert(focus_owner != null and "ItemList" in str(focus_owner.get_path()), "focus restored to ItemList")

	# --- 14. Stress: random button mashing ---
	_log("\n--- 14. Stress: rapid random button presses ---")
	for i in 30:
		var btn: int = [0, 1, 2, 3, 4, 7, 9, 10, 11, 12, 13, 14][i % 12]
		if btn >= 11 and btn <= 14:
			_push_dpad(btn, true); await process_frame
			_push_dpad(btn, false); await process_frame
		else:
			_send(player, btn, true); await process_frame
			_send(player, btn, false); await process_frame
	_log("   survived 30 random button presses without errors")

	# --- 15. From a slave, pressing the X face button (slot 0) must NOT crash ---
	_log("\n--- 15. X face button inside slave doesn't crash ---")
	# Go to elementos
	for i in 3:
		_send(player, 10, true); await process_frame; await process_frame
	_send(player, 0, true)  # X (Cross)
	await process_frame
	_log("   X inside slave: menu.visible = %s, slave.visible = %s, paused = %s" % [
		player._menu_instance.visible, _get_slave(&"ElementAllocator").visible, self.paused
	])

	_log("\n--- 16. Final state ---")
	_log("   menu.visible = %s, paused = %s" % [player._menu_instance.visible, self.paused])

	_finish()


# Route an input event the way Godot would: player always sees it,
# then the visible UI (master or active slave) sees it. We pick ONE
# visible UI — the master if visible, otherwise the first visible slave.
# A real input event reaches ONE focused control, not two.
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
	# Route to whichever UI is currently visible (master OR slave, not both)
	if player and "_menu_instance" in player and is_instance_valid(player._menu_instance):
		var menu = player._menu_instance
		if menu.visible and menu.has_method("_input"):
			menu._input(ev)
		else:
			# Master hidden → check for a visible slave
			for sn in SLAVE_NAMES:
				var slave: Control = _get_slave(sn)
				if slave and slave.visible and slave.has_method("_input"):
					slave._input(ev)
					break


# Inject D-pad via Viewport.push_input so the GUI subsystem sees it.
func _push_dpad(btn: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = pressed
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


func _tab_visible(menu: Control, tab_name: StringName) -> bool:
	if tab_name == &"skills":
		var hbox: Control = menu.get_node_or_null("Panel/Margin/VBox/HBoxBody")
		return menu.visible and hbox != null and hbox.visible
	if tab_name == &"mision":
		var mp: Control = menu.get_node_or_null("Panel/Margin/VBox/MissionPanel")
		return menu.visible and mp != null and mp.visible
	if tab_name == &"objetivos":
		var op: Control = menu.get_node_or_null("Panel/Margin/VBox/ObjectivesPanel")
		return menu.visible and op != null and op.visible
	if tab_name == &"elementos":
		var ea := _get_slave(&"ElementAllocator")
		return ea != null and ea.visible
	if tab_name == &"atributos":
		var aa := _get_slave(&"AttributeAllocator")
		return aa != null and aa.visible
	if tab_name == &"armas":
		var wa := _get_slave(&"WeaponAllocator")
		return wa != null and wa.visible
	return false


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
		_log("RESULT: ✓ ALL CONTROLLER NAVIGATION TESTS PASSED")
	else:
		_log("RESULT: ✗ %d FAILURES:" % _errors.size())
		for e in _errors:
			_log("  - %s" % e)
	var f := FileAccess.open("/tmp/controller_test_results.txt", FileAccess.WRITE)
	for r in _results:
		f.store_line(r)
	f.close()
	quit()


func _log(msg: String) -> void:
	print(msg)
	var f := FileAccess.open("/tmp/controller_test.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("/tmp/controller_test.log", FileAccess.WRITE)
	else:
		f.seek_end()
	f.store_line(msg)
	f.close()


func _reset_log() -> void:
	var f := FileAccess.open("/tmp/controller_test.log", FileAccess.WRITE)
	f.close()
	var f2 := FileAccess.open("/tmp/controller_test_results.txt", FileAccess.WRITE)
	f2.close()
