class_name BookTabBase
extends Control

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")

@export var tab_id: StringName = &""

@export var is_master_tab: bool = false

@export var scroll: ScrollContainer = null

@export var scroll_step: int = 48

var _was_paused: bool = false
var _was_paused_initialized: bool = false
var _initialized: bool = false
var _scroll_accum: float = 0.0
var _scroll_threshold: float = 0.4


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _initialized:
		ready.connect(_initialize, CONNECT_ONE_SHOT)


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if scroll == null:
		scroll = _find_first_scroll(self)
	_do_initialize()


func _do_initialize() -> void:
	pass


func open() -> void:
	visible = true
	if not _was_paused_initialized:
		_was_paused = get_tree().paused
		_was_paused_initialized = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_scroll_accum = 0.0


func close() -> void:
	_close()


func _close() -> void:
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_was_paused_initialized = false


func _navigate_to_master_tab(delta: int) -> void:
	if is_master_tab:
		if delta > 0:
			call("_on_next_tab")
		else:
			call("_on_prev_tab")
		return
	var book: Control = get_tree().root.find_child("Menu", true, false)
	if book == null:
		book = get_tree().root.find_child("SkillBook", true, false)
	_close()
	if book == null:
		return
	if delta > 0:
		if book.has_method("_on_next_tab"):
			book._on_next_tab()
	else:
		if book.has_method("_on_prev_tab"):
			book._on_prev_tab()
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not is_master_tab and event is InputEventJoypadButton and event.pressed:
		var btn: int = event.button_index
		if btn == 9:
			_navigate_to_master_tab(-1)
			get_viewport().set_input_as_handled()
			return
		elif btn == 10:
			_navigate_to_master_tab(+1)
			get_viewport().set_input_as_handled()
			return


func _find_first_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer and (n.name == "Scroll" or n.name == "DetailScroll"):
		return n
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_first_scroll(c)
		if r != null:
			return r
	return null
