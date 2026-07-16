## push_error_test.gd — Tests if push_error() goes through Logger._log_message
extends SceneTree

func _init():
	print("[TEST] Testing push_error capture...")
	push_error("TEST ERROR: This should appear in Logger._log_message")
	push_warning("TEST WARNING: This should also appear")
	print("[TEST] Done. Check debug_errors.log")
	quit(0)
