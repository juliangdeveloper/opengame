extends Node
class_name MenuFocusable
## D-pad auto-repeat component for any menu.
##
## Attach as a child of the menu (or any Control that should respond
## to D-pad hold). Then connect signals:
##   - on_step_up: Callable — fired once per D-up step
##   - on_step_down: Callable — fired once per D-down step
##   - on_step_left: Callable (optional) — fired once per D-left
##   - on_step_right: Callable (optional) — fired once per D-right
##
## Behavior:
##   - First press → 1 step immediately
##   - Hold ≥ 0.2s → starts fast repeat (every 50ms)
##   - Release → stops
##
## The first step is delivered to your handler via the standard input
## flow (D-pad up/down/left/right already trigger Godot's built-in
## ui_focus_prev/next/left/right). This node only delivers REPEAT
## steps when the user holds.

signal repeat_step(direction: String)  # "up" | "down" | "left" | "right"

const INITIAL_DELAY := 0.2  # seconds before fast repeat starts
const INTERVAL := 0.05      # seconds between repeat steps

var _press_times: Dictionary = {}  # direction (String) -> start time (float, -1 = not pressed)
var _active_direction: String = ""
var _last_step_time: float = -1.0
var _enabled: bool = true


func _ready() -> void:
	_press_times = {"up": -1.0, "down": -1.0, "left": -1.0, "right": -1.0}
	set_process(true)


## Process a raw input event to track press/release.
## Call this from the menu's _input or _unhandled_input.
func feed_event(event: InputEvent) -> void:
	if not _enabled:
		return
	if not (event is InputEventJoypadButton or event is InputEventAction):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if event is InputEventJoypadButton:
		match event.button_index:
			11:  # D-up
				_press_times["up"] = now if event.pressed else -1.0
			12:  # D-down
				_press_times["down"] = now if event.pressed else -1.0
			13:  # D-left
				_press_times["left"] = now if event.pressed else -1.0
			14:  # D-right
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
	# Find the direction with the earliest press that has crossed the threshold
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
	# Throttle: one step per INTERVAL
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
