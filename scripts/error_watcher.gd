## error_watcher.gd — Watches for errors via stderr capture and writes to file.
extends Node

var _log_path: String = ""
var _file: FileAccess = null


func _ready() -> void:
	_log_path = ProjectSettings.globalize_path("user://logs/debug_errors.log")
	DirAccess.make_dir_recursive_absolute(_log_path.get_base_dir())
	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file != null:
		_file.store_line("[Watcher] Started at %s" % Time.get_datetime_string_from_system())
		_file.flush()
	# Override print to also write to our file
	_hook_prints()


func _hook_prints() -> void:
	# We can't override print directly, but we can poll for changes
	# Use a timer to periodically check for new errors
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	timer.timeout.connect(_poll_errors)
	add_child(timer)


func _poll_errors() -> void:
	# Read the engine's log file and compare
	var engine_log_path = ProjectSettings.globalize_path("user://logs/godot.log")
	if not FileAccess.file_exists(engine_log_path):
		return
	var engine_log = FileAccess.open(engine_log_path, FileAccess.READ)
	if engine_log == null:
		return
	var content = engine_log.get_as_text()
	engine_log.close()
	# Check for ERROR lines
	var lines = content.split("\n")
	for line in lines:
		if line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR:") or "error" in line.to_lower():
			if _file != null:
				_file.store_line("[ENGINE] %s" % line)
				_file.flush()
