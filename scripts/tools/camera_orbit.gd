extends Node3D

# Simple camera orbit: left-drag rotates around target, wheel zooms.
# Attach this script to a Camera3D; set `target_path` to a Node3D to orbit around.

@export var target_path: NodePath
@export var distance: float = 5.0
@export var min_distance: float = 1.5
@export var max_distance: float = 20.0
@export var rotation_speed: float = 0.005
@export var zoom_speed: float = 0.5

var _yaw: float = 0.0
var _pitch: float = -0.3
var _target: Node3D

func _ready() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		# Fallback: use parent if it's a Node3D
		var p := get_parent()
		if p is Node3D:
			_target = p
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_dragging = true
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clamp(distance - zoom_speed, min_distance, max_distance)
			_apply_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clamp(distance + zoom_speed, min_distance, max_distance)
			_apply_transform()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * rotation_speed
		_pitch -= event.relative.y * rotation_speed
		_pitch = clamp(_pitch, -1.5, 1.5)
		_apply_transform()

var _dragging: bool = false


func _apply_transform() -> void:
	if _target == null:
		return
	var pivot := _target.global_position
	var x := distance * cos(_pitch) * sin(_yaw)
	var y := distance * sin(-_pitch)
	var z := distance * cos(_pitch) * cos(_yaw)
	global_position = pivot + Vector3(x, y + 1.5, z)
	look_at(pivot + Vector3(0, 1.0, 0), Vector3.UP)