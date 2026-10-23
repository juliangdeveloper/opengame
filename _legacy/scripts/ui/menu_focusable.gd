extends Node
class_name MenuFocusable

signal repeat_step(direction: String)

const INITIAL_DELAY := 0.2
const INTERVAL := 0.05

var _press_times: Dictionary = {}
var _active_direction: String = ""
var _last_step_time: float = -1.0
var _enabled: bool = true


func _ready() -> void:
	_press_times = {"up": -1.0, "down": -1.0, "left": -1.0, "right": -1.0}
	set_process(true)


func feed_event(event: InputEvent) -> void:
	if not _enabled:
		return
	if not (event is InputEventJoypadButton or event is InputEventAction):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if event is InputEventJoypadButton:
		match event.button_index:
			11:
				_press_times["up"] = now if event.pressed else -1.0
			12:
				_press_times["down"] = now if event.pressed else -1.0
			13:
				_press_times["left"] = now if event.pressed else -1.0
			14:
				_press_times["right"] = now if event.pressed else -1.0
		if not event.pressed:
			_active_direction = ""
	elif event is InputEventAction:
		var action_dir: String = ""
		match event.action:
			"ui_focus_prev": action_dir = "up"
			"ui_focus_next": action_dir = "down"
			"ui_left": action_dir = "left"
			"ui_right": action_dir = "right"
		if action_dir != "":
			_press_times[action_dir] = now if event.pressed else -1.0
			if not event.pressed:
				_active_direction = ""


func _process(_delta: float) -> void:
	if not _enabled:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var chosen: String = ""
	var chosen_start: float = -1.0
	for dir in _press_times.keys():
		var t: float = _press_times[dir]
		if t < 0.0:
			continue
		var held: float = now - t
		if held < INITIAL_DELAY:
			continue
		if chosen_start < 0.0 or t < chosen_start:
			chosen = dir
			chosen_start = t
	if chosen == "":
		_last_step_time = -1.0
		return
	if _last_step_time >= 0.0 and (now - _last_step_time) < INTERVAL:
		return
	_last_step_time = now
	_active_direction = chosen
	repeat_step.emit(chosen)


func is_repeating() -> bool:
	return _active_direction != ""


func set_enabled(v: bool) -> void:
	_enabled = v
	if not v:
		for k in _press_times.keys():
			_press_times[k] = -1.0
		_active_direction = ""
		_last_step_time = -1.0
