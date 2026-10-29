extends Node
## The link to S-Bike Training Hub. Every Ride World mode talks to the hub through this:
## live numbers in (power, cadence, speed, distance, grade, gear, ERG target, FTP) about 10 times a second,
## and requests out (start the mode, set the hill, mark a moment, finish). The hub decides what reaches the bike.

signal updated(data: Dictionary)
signal connection_changed(connected: bool)

const POLL_S := 0.1
var base := ""
var data := {}
var connected := false
var _http: HTTPRequest
var _busy := false
var _misses := 0

func _ready() -> void:
	# Web games use the restricted page bridge; only local editor sessions use HTTP.
	base = "" if OS.has_feature("web") else "http://127.0.0.1:8729"
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_status)
	var timer := Timer.new()
	timer.wait_time = POLL_S
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_poll)

## Lean, -1 (left) .. 1 (right), from the hub's page: a tilted tablet, or a phone on a bike leaning on a rocker plate.
## lean_source() is "" when no sensor is sharing, so a mode can say leaning is available without requiring it.
var _lean := 0.0
var _lean_source := ""

func _process(_delta: float) -> void:
	if OS.has_feature("web") and Engine.get_process_frames() % 2 == 0:
		var r = JavaScriptBridge.eval("window.sbike ? [window.sbike.lean, window.sbike.leanSource] : null", true)
		if r is Array and r.size() == 2:
			_lean = clampf(float(r[0]), -1.0, 1.0)
			_lean_source = str(r[1])

func lean() -> float: return _lean
func lean_source() -> String: return _lean_source
func recenter_lean() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.sbike && window.sbike.recenter && window.sbike.recenter()", true)

func _poll() -> void:
	if OS.has_feature("web"):
		var snapshot = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.SBikeBridge ? window.SBikeBridge.snapshot() : {connected:false,data:{}})", true)))
		if snapshot is Dictionary and snapshot.get("connected", false):
			data = snapshot.get("data", {})
			_set_connected(true)
			updated.emit(data)
		else:
			_set_connected(false)
		return
	if _busy:
		return
	_busy = true
	if _http.request(base + "/status") != OK:
		_busy = false

func _on_status(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var parsed = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if parsed is Dictionary:
		data = parsed
		_misses = 0
		_set_connected(true)
		updated.emit(data)
	else:
		_misses += 1
		if _misses > 10:
			_set_connected(false)

func _set_connected(on: bool) -> void:
	if on != connected:
		connected = on
		connection_changed.emit(on)

## Numbers the modes use.
func power() -> float: return float(data.get("power", 0))
func cadence() -> float: return float(data.get("cadence", 0))
func speed_mps() -> float: return float(data.get("speed", 0.0)) / 3.6
func ftp() -> float: return max(1.0, float(data.get("ftp", 200)))
func effort() -> float: return power() / ftp()          # share of FTP: the basis for fair, relative speed

## Requests. The hub clamps the hill to a safe range and flattens it if the mode goes quiet.
func start_mode(id: String, title: String) -> void: _send("/mode/start/%s/%s" % [id.uri_encode(), title.uri_encode()])
func set_grade(percent: float) -> void: _send("/mode/grade/%s" % str(snappedf(percent, 0.5)))
func mark(text: String) -> void: _send("/mode/mark/" + text.uri_encode())
func end_mode(result := "") -> void: _send("/mode/end" + ("/" + result.uri_encode() if result != "" else ""))

func _send(path: String) -> void:
	if OS.has_feature("web"):
		var parts = path.split("/")
		var action = parts[2]
		var args := {}
		if action == "grade":
			args = {"value": parts[3].to_float()}
		elif action in ["mark", "end"]:
			args = {"text": parts[3].uri_decode() if parts.size() > 3 else ""}
		JavaScriptBridge.eval("window.SBikeBridge && window.SBikeBridge.request(%s,%s)" % [JSON.stringify(action), JSON.stringify(args)], true)
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	req.request(base + path, [], HTTPClient.METHOD_POST, "")
