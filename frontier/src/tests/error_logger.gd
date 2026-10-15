class_name ErrorLogger
extends Logger
## Captures engine/script/shader errors for the bot oracles (a run with any script or shader error fails).

var mutex := Mutex.new()
var errors: Array = []        # [type, file:line, message]
var ignore := ["audio_driver", "init_output_device", "ALSA", "status < 0", "dummy driver"]

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, bt: Array) -> void:
	var msg := "%s %s" % [code, rationale]
	# thread-guard violations crash the engine a moment later: print which script made the call (the worker's stack)
	if msg.contains("caller thread can't call"):
		var lines := PackedStringArray()
		for b in bt:
			if b is ScriptBacktrace:
				lines.append((b as ScriptBacktrace).format())
		printerr("THREAD GUARD (thread %d): %s\n%s" % [OS.get_thread_caller_id(), msg, "\n".join(lines) if not lines.is_empty() else "  (no script frames: native caller)"])
	for ig in ignore:
		if msg.contains(ig) or file.contains(ig) or function.contains(ig):
			return
	if error_type == ERROR_TYPE_WARNING:
		return
	mutex.lock()
	if errors.size() < 200:
		errors.append([["error", "warning", "script", "shader"][error_type], "%s:%d" % [file, line], msg.strip_edges()])
	mutex.unlock()

func _log_message(_message: String, _error: bool) -> void:
	pass

func take() -> Array:
	mutex.lock()
	var e := errors.duplicate()
	mutex.unlock()
	return e
