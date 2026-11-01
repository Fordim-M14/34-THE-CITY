class_name RouteData
extends RefCounted
## RouteData — JSON rota verisini yükler; istasyon, hız limiti, segment ve sinyal sorguları.
## Sinyaller istasyon verisinden otomatik üretilir (kalkış / blok / yaklaşım) ve her iki
## yön için tutarlıdır. reversed() ile dönüş yönü için aynalanmış kopya üretilir.

var raw: Dictionary = {}
var route_id: String = ""
var direction: String = "forward"
var stations: Array = []
var speed_limits: Array = []
var signals: Array = []
var segments: Array = []
var track_points: Array = []
var curve: Curve3D
var track_length: float = 0.0
var buffer_end: float = 2500.0
var schedule_tolerance: float = 20.0
var dwell_seconds: float = 22.0
var max_speed_kmh: float = 80.0
var line_name: String = ""
var line_color: Color = Color(0.83, 0.2, 0.48)
var operator_name: String = ""
var train_model: String = ""
var direction_label: String = ""
var terminus: String = ""
var signal_rules: Dictionary = {"departure_offset": 12.0, "approach_offset": 260.0, "block_spacing": 650.0}

static func load_route(path: String) -> RouteData:
	var r := RouteData.new()
	if r.load_from_file(path):
		return r
	return null

func load_from_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("RouteData: dosya açılamadı: %s" % path)
		return false
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	if err != OK:
		push_error("RouteData: JSON hatası satır %d: %s" % [json.get_error_line(), json.get_error_message()])
		return false
	raw = json.data
	route_id = str(raw.get("route_id", ""))
	stations = (raw.get("stations", []) as Array).duplicate(true)
	speed_limits = (raw.get("speed_limits", []) as Array).duplicate(true)
	segments = (raw.get("segments", []) as Array).duplicate(true)
	track_points = raw.get("track", {}).get("points", [])
	buffer_end = float(raw.get("track", {}).get("buffer_end", 2500.0))
	schedule_tolerance = float(raw.get("schedule_tolerance_seconds", 20.0))
	dwell_seconds = float(raw.get("dwell_seconds", 22.0))
	max_speed_kmh = float(raw.get("max_speed_kmh", 80.0))
	line_name = str(raw.get("line_name", ""))
	line_color = Color.html(str(raw.get("line_color", "#d4327a")))
	operator_name = str(raw.get("operator", ""))
	train_model = str(raw.get("train_model", ""))
	direction_label = str(raw.get("direction_label_forward", raw.get("direction_label", "")))
	terminus = str(raw.get("terminus_forward", ""))
	if raw.has("signal_rules"):
		for k in raw["signal_rules"]:
			signal_rules[k] = float(raw["signal_rules"][k])
	_build_curve()
	buffer_end = minf(buffer_end, track_length - 3.0)
	for i in stations.size():
		stations[i]["index"] = i
		stations[i]["is_start"] = (i == 0)
		stations[i]["is_end"] = (i == stations.size() - 1)
	_generate_signals()
	return true

func _build_curve() -> void:
	curve = Curve3D.new()
	curve.bake_interval = 1.0
	for pt in track_points:
		var pos: Array = pt["pos"]
		var p := Vector3(pos[0], pos[1], pos[2])
		var pin := Vector3.ZERO
		var pout := Vector3.ZERO
		if pt.has("in"):
			pin = Vector3(pt["in"][0], pt["in"][1], pt["in"][2])
		if pt.has("out"):
			pout = Vector3(pt["out"][0], pt["out"][1], pt["out"][2])
		curve.add_point(p, pin, pout)
	track_length = curve.get_baked_length()

## Dönüş yönü için aynalanmış kopya: konumlar (track_length - x), istasyon sırası ters,
## kapı tarafları ters, eğri ters.
func reversed() -> RouteData:
	var r := RouteData.new()
	r.raw = raw
	r.route_id = route_id
	r.direction = "reverse"
	r.schedule_tolerance = schedule_tolerance
	r.dwell_seconds = dwell_seconds
	r.max_speed_kmh = max_speed_kmh
	r.line_name = line_name
	r.line_color = line_color
	r.operator_name = operator_name
	r.train_model = train_model
	r.direction_label = str(raw.get("direction_label_reverse", "Dönüş"))
	r.terminus = str(raw.get("terminus_reverse", ""))
	r.signal_rules = signal_rules.duplicate()
	var L := track_length
	# Eğri: noktalar ters sırada, in/out yer değiştirir
	var pts: Array = []
	for i in range(track_points.size() - 1, -1, -1):
		var pt: Dictionary = track_points[i]
		var np := {"pos": pt["pos"]}
		if pt.has("out"):
			np["in"] = pt["out"]
		if pt.has("in"):
			np["out"] = pt["in"]
		pts.append(np)
	r.track_points = pts
	r._build_curve()
	# Ters eğrinin uzunluğu ileri ile aynıdır; aynalama ileri uzunluğa göre yapılır
	r.track_length = L
	r.buffer_end = L - 3.0
	# İstasyonlar
	var st: Array = []
	for i in range(stations.size() - 1, -1, -1):
		var s: Dictionary = stations[i].duplicate(true)
		var ps: float = float(s["platform_start"])
		var pe: float = float(s["platform_end"])
		s["platform_start"] = L - pe
		s["platform_end"] = L - ps
		# Duruş noktası: ileri yönde peron sonuna olan uzaklık dönüşte de korunur
		var stop_from_end: float = pe - float(stations[i]["stop_pos"])
		s["stop_pos"] = float(s["platform_end"]) - stop_from_end
		s["door_side"] = "left" if str(s.get("door_side", "right")) == "right" else "right"
		st.append(s)
	for i in st.size():
		st[i]["index"] = i
		st[i]["is_start"] = (i == 0)
		st[i]["is_end"] = (i == st.size() - 1)
	r.stations = st
	# Hız limitleri
	var sl: Array = []
	for lim in speed_limits:
		sl.append({"from": L - float(lim["to"]), "to": L - float(lim["from"]), "limit_kmh": lim["limit_kmh"]})
	r.speed_limits = sl
	var sg: Array = []
	for seg in segments:
		var ns: Dictionary = seg.duplicate()
		ns["from"] = L - float(seg["to"])
		ns["to"] = L - float(seg["from"])
		sg.append(ns)
	r.segments = sg
	r._generate_signals()
	return r

## Sinyal üretimi: her istasyon için kalkış sinyali (peron sonu + offset), bir sonraki
## istasyon için yaklaşım sinyali (peron başı - offset), arada blok sinyalleri.
func _generate_signals() -> void:
	signals.clear()
	var dep_off: float = signal_rules["departure_offset"]
	var app_off: float = signal_rules["approach_offset"]
	var spacing: float = signal_rules["block_spacing"]
	for i in stations.size():
		var s: Dictionary = stations[i]
		if i < stations.size() - 1:
			var dep_pos: float = float(s["platform_end"]) + dep_off
			signals.append({"id": "D-%s" % s["id"], "pos": dep_pos, "type": "departure", "station": s["id"], "aspect": "red"})
			var nxt: Dictionary = stations[i + 1]
			var app_pos: float = float(nxt["platform_start"]) - app_off
			var p := dep_pos + spacing
			var n := 1
			while p < app_pos - spacing * 0.5:
				signals.append({"id": "B-%s-%d" % [s["id"], n], "pos": p, "type": "block", "aspect": "green"})
				p += spacing
				n += 1
			signals.append({"id": "A-%s" % nxt["id"], "pos": app_pos, "type": "approach", "station": nxt["id"], "aspect": "yellow"})
	# JSON'daki ek sinyaller (opsiyonel)
	for extra in raw.get("signals", []):
		if direction == "forward":
			signals.append(extra.duplicate())

# ---------------------------------------------------------------------------
# Sorgular

func get_start_station() -> Dictionary:
	return stations[0] if stations.size() > 0 else {}

func get_end_station() -> Dictionary:
	return stations[-1] if stations.size() > 0 else {}

func get_station_by_id(id: String) -> Dictionary:
	for s in stations:
		if str(s["id"]) == id:
			return s
	return {}

## Verilen konumdan sonraki (henüz geçilmemiş) istasyon; başlangıç istasyonu atlanır.
func get_next_station(pos: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for s in stations:
		var d: float = float(s["stop_pos"]) - pos
		if s.get("is_start", false) and d < 1.0:
			continue
		if d > -5.0 and d < best_d:
			best_d = d
			best = s
	return best

func get_station_at(pos: float) -> Dictionary:
	for s in stations:
		if pos >= float(s["platform_start"]) and pos <= float(s["platform_end"]):
			return s
	return {}

func get_speed_limit_kmh(pos: float) -> float:
	for sl in speed_limits:
		if pos >= float(sl["from"]) and pos < float(sl["to"]):
			return float(sl["limit_kmh"])
	return max_speed_kmh

func get_upcoming_limit(pos: float, lookahead: float) -> Dictionary:
	var current := get_speed_limit_kmh(pos)
	var best: Dictionary = {}
	for sl in speed_limits:
		var from_pos: float = float(sl["from"])
		if from_pos > pos and from_pos <= pos + lookahead and float(sl["limit_kmh"]) < current:
			if best.is_empty() or from_pos < float(best["distance"]) + pos:
				best = {"limit_kmh": float(sl["limit_kmh"]), "distance": from_pos - pos}
	return best

func get_next_signal(pos: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for sg in signals:
		var d: float = float(sg["pos"]) - pos
		if d >= 0.0 and d < best_d:
			best_d = d
			best = sg
	return best

func get_segment_type(pos: float) -> String:
	for seg in segments:
		if pos >= float(seg["from"]) and pos < float(seg["to"]):
			return str(seg.get("type", "tunnel"))
	return "tunnel"

## Eğim (yükseliş pozitif): dy/ds
func get_grade(pos: float) -> float:
	if curve == null:
		return 0.0
	var o := clampf(pos, 0.0, track_length - 6.0)
	var a := curve.sample_baked(o, true)
	var b := curve.sample_baked(o + 5.0, true)
	return (b.y - a.y) / 5.0

func station_count() -> int:
	return stations.size()

## İstasyonlar arası tarife: dizin i istasyonuna planlı varış (sn, ilk kalkıştan itibaren)
func schedule_for(i: int) -> float:
	if i < 0 or i >= stations.size():
		return 0.0
	if direction == "forward":
		return float(stations[i].get("schedule_s", 0.0))
	# Dönüşte: ileri tarifenin aynası (toplam - kendi)
	var total: float = float(raw["stations"][-1].get("schedule_s", 0.0))
	return total - float(stations[i].get("schedule_s", 0.0))
