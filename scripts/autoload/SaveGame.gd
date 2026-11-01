extends Node
## SaveGame — otomatik kayıt / devam etme (v0.4).
## Kaydedilenler: görev tanımı (rota, yön, saat, seed, mod), tren konumu/hızı/yön kolu/kol,
## farlar/kabin ışığı, kapı durumları, görev durumu (istasyon dizini, sefer süresi, oyun saati),
## aktif arızalar, yolcu doluluğu, puanlama (kategori puanları, cezalar, istatistikler, olay günlüğü),
## trafik (öndeki sefer), ayarlar ayrıca Settings.cfg'de, kariyer ayrıca career.json'da.
## Tetik: her 20 sn (sürüşte), duraklatma menüsü, pencere kapatma, ana menüye dönüş.
## Bozuk/eski kayıt oyunun açılmasını engellemez: JSON parse veya alan doğrulaması başarısızsa kayıt yok sayılır.

const PATH := "user://autosave.json"
const VERSION := 2

var resume_data: Dictionary = {}      # Main._ready okur ve temizler
var _timer := 0.0

func has_save() -> bool:
	return not load_save().is_empty()

## Kayıt dosyasını okur ve doğrular; bozuksa {} döner (ve dosyayı siler)
func load_save() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK or not (json.data is Dictionary):
		push_warning("SaveGame: bozuk kayıt, yok sayıldı")
		clear()
		return {}
	var d: Dictionary = json.data
	if int(d.get("version", 0)) != VERSION:
		clear()
		return {}
	for key in ["mission", "train", "progress", "scoring"]:
		if not (d.get(key) is Dictionary):
			clear()
			return {}
	var tr: Dictionary = d["train"]
	if not tr.has("offset") or not (tr["offset"] is float or tr["offset"] is int):
		clear()
		return {}
	return d

func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func describe(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var m: Dictionary = d["mission"]
	var p: Dictionary = d["progress"]
	return "Sefer %s · %s · %s · istasyon %d/%d · %s" % [str(m.get("service_number", "")), "Serbest" if str(m.get("mode", "")) == "free" else "Kariyer",
		"dönüş" if str(m.get("direction", "forward")) == "reverse" else "gidiş", int(p.get("stop_index", 0)) + 1, int(p.get("station_count", 6)), str(d.get("saved_at", ""))]

## Main çağırır (düzenli aralıkla ve olaylarda)
func save_from_main(main: Node) -> bool:
	if main == null or not main.has_node("Train") or not main.has_node("Mission"):
		return false
	var train = main.get_node("Train")
	var mission = main.get_node("Mission")
	if mission.state == MissionManager.State.FINISHED or mission.state == MissionManager.State.BRIEFING:
		return false
	var doors = train.doors
	var faults_ids: Array = []
	if main.has_node("Faults"):
		for f in main.get_node("Faults").active:
			faults_ids.append(str(f["id"]))
	var traffic = main.get_node("Traffic") if main.has_node("Traffic") else null
	var d := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"mission": GameState.mission.duplicate(true),
		"train": {
			"offset": train.offset, "speed": train.speed, "lever": train.lever, "reverser": train.reverser,
			"move_dir": train.move_dir, "headlights": train.headlights_on, "cabin_light": train.cabin_light_on,
			"doors_left": doors.is_open("left"), "doors_right": doors.is_open("right"),
			"distance": train.distance_travelled, "emergency": train.active_reason_names(),
		},
		"progress": {
			"stop_index": mission.stop_index, "state": mission.state, "station_count": GameState.route.stations.size(),
			"mission_time": GameState.mission_time, "clock_s": GameState.clock_s, "departure_cleared": GameState.departure_cleared,
			"dwell_timer": mission.dwell_timer, "departure_timer": mission.departure_timer,
			"onboard": main.get_node("Passengers").onboard if main.has_node("Passengers") else 0,
			"faults": faults_ids,
		},
		"scoring": {
			"category_scores": _cat_to_str(Scoring.category_scores), "penalties": Scoring.penalties.duplicate(true),
			"event_log": Scoring.event_log.duplicate(true), "stats": Scoring.stats.duplicate(true),
		},
		"traffic": {} if traffic == null else {"lead_offset": traffic.lead_offset, "lead_speed": traffic.lead_speed,
			"lead_stop_index": traffic.lead_stop_index, "lead_state": traffic.lead_state, "lead_dwell": traffic.lead_dwell,
			"lead_active": traffic.lead_active, "tsr": traffic.tsr.duplicate(true)},
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true

func _cat_to_str(cs: Dictionary) -> Dictionary:
	var out := {}
	for k in cs:
		out[str(int(k))] = cs[k]
	return out

## Main._ready sonunda çağrılır: kaydı sahneye uygular
func apply_to_main(main: Node, d: Dictionary) -> void:
	var train = main.get_node("Train")
	var mission = main.get_node("Mission")
	var tr: Dictionary = d["train"]
	var p: Dictionary = d["progress"]
	var sc: Dictionary = d["scoring"]
	# Puanlama
	if sc.get("category_scores") is Dictionary:
		for k in sc["category_scores"]:
			Scoring.category_scores[int(k)] = int(sc["category_scores"][k])
	if sc.get("penalties") is Array:
		Scoring.penalties = sc["penalties"]
	if sc.get("event_log") is Array:
		Scoring.event_log = sc["event_log"]
	if sc.get("stats") is Dictionary:
		for k in sc["stats"]:
			Scoring.stats[k] = sc["stats"][k]
	# Görev / saat
	GameState.mission_time = float(p.get("mission_time", 0.0))
	GameState.clock_s = float(p.get("clock_s", GameState.clock_s))
	GameState.departure_cleared = bool(p.get("departure_cleared", false))
	# Tren
	train.offset = float(tr["offset"])
	train.speed = float(tr.get("speed", 0.0))
	train.lever = float(tr.get("lever", 0.0))
	train.reverser = int(tr.get("reverser", 1))
	train.move_dir = int(tr.get("move_dir", 1))
	train.distance_travelled = float(tr.get("distance", 0.0))
	train.headlights_on = bool(tr.get("headlights", true))
	train.cabin_light_on = bool(tr.get("cabin_light", true))
	train.visual.set_headlights(train.headlights_on)
	train.visual.set_cabin_light(train.cabin_light_on)
	train._update_car_transforms()
	train._prev_offset = train.offset
	# Görev durumu: brifing atlanır
	mission.stop_index = int(p.get("stop_index", 0))
	var st_state := int(p.get("state", MissionManager.State.RUNNING))
	train.controls_enabled = true
	mission._set_state(st_state)
	mission.dwell_timer = float(p.get("dwell_timer", -1.0))
	mission.departure_timer = float(p.get("departure_timer", -1.0))
	if bool(tr.get("doors_left", false)):
		train.doors.force_open("left")
	if bool(tr.get("doors_right", false)):
		train.doors.force_open("right")
	for r in tr.get("emergency", []):
		for key in TrainController.REASON_NAMES:
			if TrainController.REASON_NAMES[key] == str(r) and key != TrainController.EmergencyReason.FAULT:
				train.trigger_emergency(key)
	# Yolcu
	if main.has_node("Passengers"):
		main.get_node("Passengers").onboard = int(p.get("onboard", 0))
		main.get_node("Passengers")._update_load()
	# Arızalar
	if main.has_node("Faults"):
		var fm = main.get_node("Faults")
		for fid in p.get("faults", []):
			if fm.DEFS.has(str(fid)) and str(fid) != "signal_fault":
				fm._start(str(fid))
	# Trafik
	if d.get("traffic") is Dictionary and main.has_node("Traffic"):
		var t = main.get_node("Traffic")
		var td: Dictionary = d["traffic"]
		if td.has("lead_offset"):
			t.lead_offset = float(td["lead_offset"])
			t.lead_speed = float(td.get("lead_speed", 0.0))
			t.lead_stop_index = int(td.get("lead_stop_index", 0))
			t.lead_state = str(td.get("lead_state", "run"))
			t.lead_dwell = float(td.get("lead_dwell", 0.0))
			t.lead_active = bool(td.get("lead_active", true))
			if td.get("tsr") is Dictionary:
				t.tsr = td["tsr"]
	Scoring.log_event("Kayıttan devam edildi (%s)" % str(d.get("saved_at", "")))

func _process(delta: float) -> void:
	if GameState.phase == GameState.Phase.DRIVING or GameState.phase == GameState.Phase.ARRIVED or GameState.phase == GameState.Phase.PREPARING:
		_timer += delta
		if _timer >= 20.0 and not GameState.auto_test_mode:
			_timer = 0.0
			var m := get_tree().current_scene
			if m and m.has_node("Train"):
				save_from_main(m)
	else:
		_timer = 0.0
