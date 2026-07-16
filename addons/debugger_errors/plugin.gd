@tool
extends EditorPlugin

## Adds "Copy All" + "Save to Log" buttons to the Debugger's Errors panel.
## Auto-saves errors to user://logs/debugger_errors.log after 5 seconds.

var _copy_button: Button = null
var _save_button: Button = null
var _error_tree: Tree = null
var _hbox: HBoxContainer = null
var _setup_timer: Timer = null
var _retry_count := 0
var _auto_save_done := false
var _frame_count := 0
const _MAX_RETRIES := 20


func _enter_tree() -> void:
	_setup_timer = Timer.new()
	_setup_timer.wait_time = 0.5
	_setup_timer.one_shot = true
	_setup_timer.timeout.connect(_try_setup)
	add_child(_setup_timer)
	_setup_timer.start()


func _exit_tree() -> void:
	if is_instance_valid(_copy_button):
		_copy_button.queue_free()
	if is_instance_valid(_save_button):
		_save_button.queue_free()
	_copy_button = null
	_save_button = null
	_error_tree = null
	_hbox = null
	_cleanup_timer()


func _process(_delta: float) -> void:
	if _auto_save_done:
		return
	if _error_tree == null:
		return
	# Check if Tree has items
	var root := _error_tree.get_root()
	if root and root.get_first_child():
		_auto_save_done = true
		_auto_save()


func _try_setup() -> void:
	var base := EditorInterface.get_base_control()
	if not base:
		_schedule_retry()
		return
	var result := _find_error_panel(base)
	if result.is_empty():
		_schedule_retry()
		return
	_error_tree = result["tree"]
	_hbox = result["hbox"]
	_inject_buttons()
	_cleanup_timer()


func _schedule_retry() -> void:
	_retry_count += 1
	if _retry_count < _MAX_RETRIES and is_instance_valid(_setup_timer):
		_setup_timer.start()
	else:
		push_warning("[DebuggerErrors] Error panel not found.")
		_cleanup_timer()


func _cleanup_timer() -> void:
	if is_instance_valid(_setup_timer):
		_setup_timer.queue_free()
		_setup_timer = null


func _find_error_panel(node: Node) -> Dictionary:
	if node is VBoxContainer:
		var tree: Tree = null
		var hbox: HBoxContainer = null
		var has_expand_btn := false
		for child in node.get_children():
			if child is HBoxContainer and not has_expand_btn:
				for btn in child.get_children():
					if btn is Button and btn.text in ["Expand All", "全部展开"]:
						has_expand_btn = true
						hbox = child
						break
			elif child is Tree and tree == null:
				tree = child
		if has_expand_btn and tree != null and hbox != null:
			return {"tree": tree, "hbox": hbox}
	for child in node.get_children():
		var result := _find_error_panel(child)
		if not result.is_empty():
			return result
	return {}


func _inject_buttons() -> void:
	var theme := EditorInterface.get_editor_theme()

	_copy_button = Button.new()
	_copy_button.text = "Copy All"
	_copy_button.tooltip_text = "Copy all errors to clipboard"
	_copy_button.pressed.connect(_on_copy_all_pressed)
	if theme:
		for icon_name in ["ActionCopy", "CopyNodePath", "Duplicate"]:
			if theme.has_icon(icon_name, "EditorIcons"):
				_copy_button.icon = theme.get_icon(icon_name, "EditorIcons")
				break

	_save_button = Button.new()
	_save_button.text = "Save to Log"
	_save_button.tooltip_text = "Save all errors to user://logs/debugger_errors.log"
	_save_button.pressed.connect(_on_save_pressed)
	if theme:
		for icon_name in ["Save", "FileAccess"]:
			if theme.has_icon(icon_name, "EditorIcons"):
				_save_button.icon = theme.get_icon(icon_name, "EditorIcons")
				break

	var insert_idx := _hbox.get_child_count()
	for i in _hbox.get_child_count():
		var child := _hbox.get_child(i)
		if child is Button and child.text in ["Collapse All", "全部折叠"]:
			insert_idx = i + 1
			break

	_hbox.add_child(_copy_button)
	_hbox.add_child(_save_button)
	if insert_idx < _hbox.get_child_count():
		_hbox.move_child(_copy_button, insert_idx)
		_hbox.move_child(_save_button, insert_idx + 1)

	print("[DebuggerErrors] Plugin ready.")


func _collect_errors() -> String:
	if not is_instance_valid(_error_tree):
		return ""
	var root := _error_tree.get_root()
	if not root or not root.get_first_child():
		return ""
	var entries: PackedStringArray = []
	var item := root.get_first_child()
	while item:
		entries.append(_format_error_item(item))
		item = item.get_next()
	return "\n\n".join(entries).strip_edges()


func _on_copy_all_pressed() -> void:
	var output := _collect_errors()
	if output.is_empty():
		_flash_button(_copy_button, "No content")
		return
	DisplayServer.clipboard_set(output)
	var count := output.count("\n") + 1
	_flash_button(_copy_button, "Copied %d!" % count)


func _on_save_pressed() -> void:
	_save_to_file()


func _auto_save() -> void:
	_save_to_file()


func _save_to_file() -> void:
	var output := _collect_errors()
	if output.is_empty():
		print("[DebuggerErrors] No errors to save.")
		return
	var log_path := ProjectSettings.globalize_path("user://logs/debugger_errors.log")
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var file := FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		print("[DebuggerErrors] ERROR: Cannot write to: %s" % log_path)
		return
	file.store_line("[DebuggerErrors] Saved at %s" % Time.get_datetime_string_from_system())
	file.store_line("")
	file.store_string(output)
	file.close()
	print("[DebuggerErrors] Saved %d errors to: %s" % [output.count("\n") + 1, log_path])


func _flash_button(btn: Button, msg: String) -> void:
	if not is_instance_valid(btn):
		return
	var original_text := btn.text
	btn.text = msg
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(btn):
			btn.text = original_text
	)


func _format_error_item(item: TreeItem) -> String:
	var parts: PackedStringArray = []
	var type_char := _get_type_char(item)
	var time_str: String = item.get_text(0).strip_edges()
	var msg_str: String = item.get_text(1).strip_edges()
	parts.append("%s %s   %s" % [type_char, time_str, msg_str])
	var child := item.get_first_child()
	while child:
		var c0: String = child.get_text(0).strip_edges()
		var c1: String = child.get_text(1).strip_edges()
		if c0 or c1:
			var line := "  "
			if c0 and c1:
				line += c0 + " " + c1
			elif c0:
				line += c0
			else:
				line += c1
			parts.append(line)
		child = child.get_next()
	return "\n".join(parts)


func _get_type_char(item: TreeItem) -> String:
	var meta = item.get_metadata(0)
	if meta is String:
		if meta == "warning":
			return "W"
		if meta in ["error", "cycled_error"]:
			return "E"
	var child := item.get_first_child()
	while child:
		var combined := (child.get_text(0) + " " + child.get_text(1)).to_upper()
		if "WARNING" in combined or "WARN" in combined:
			return "W"
		child = child.get_next()
	return "W"
