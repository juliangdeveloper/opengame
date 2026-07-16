## file_logger.gd — Custom Logger that captures ALL output to a file.
extends Logger
class_name FileLogger

var _file: FileAccess = null
var _mutex: Mutex = Mutex.new()
var _log_path: String = ""


func start() -> void:
	_log_path = ProjectSettings.globalize_path("user://logs/debug_errors.log")
	DirAccess.make_dir_recursive_absolute(_log_path.get_base_dir())
	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file != null:
		_file.store_line("[FileLogger] Started at %s" % Time.get_datetime_string_from_system())
		_file.flush()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
	_mutex.lock()
	if _file != null:
		var type_str: String = "ERROR"
		match error_type:
			0: type_str = "ERROR"
			1: type_str = "WARNING"
			2: type_str = "SCRIPT"
			3: type_str = "SHADER"
		_file.store_line("")
		_file.store_line("=== %s ===" % type_str)
		_file.store_line("  Function: %s" % function)
		_file.store_line("  Location: %s:%d" % [file, line])
		if code != "":
			_file.store_line("  Code: %s" % code)
		if rationale != "":
			_file.store_line("  Reason: %s" % rationale)
		for bt in script_backtraces:
			_file.store_line("  Trace: %s" % str(bt))
		_file.flush()
	_mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	_mutex.lock()
	if _file != null:
		var prefix: String = "[ERR] " if error else "[MSG] "
		_file.store_line("%s%s" % [prefix, message])
		_file.flush()
	_mutex.unlock()


func stop() -> void:
	if _file != null:
		_file.store_line("[FileLogger] Stopped")
		_file.close()
		_file = null
