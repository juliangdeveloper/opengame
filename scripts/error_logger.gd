## error_logger.gd — Autoload that registers FileLogger.
extends Node

var _logger: FileLogger = null


func _ready() -> void:
	_logger = FileLogger.new()
	_logger.start()
	OS.add_logger(_logger)
	print("[ErrorLogger] Registered. Writing to: %s" % _logger._log_path)


func _exit_tree() -> void:
	if _logger != null:
		_logger.stop()
