class_name ErrorCount
extends Logger
## Counts GDScript runtime errors (they abort the function they happen in and are otherwise only printed): the
## test runner, the scenarios and the smoke run fail on them.

static var shared: ErrorCount

var n := 0
var first := ""
var _mutex := Mutex.new()


static func install() -> ErrorCount:
	if shared == null:
		shared = ErrorCount.new()
		OS.add_logger(shared)
	return shared


## Errors since `since` (a previous value of n), with the first one's message.
func since(count: int) -> String:
	if n <= count:
		return ""
	return "%d script error(s), first: %s" % [n - count, first]


func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	if first == "":
		first = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]
	n += 1
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
