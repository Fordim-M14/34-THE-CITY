class_name PISSystem
extends Node
## PISSystem — yolcu bilgilendirme: anonslar (TR / TR+EN, kapı sistemiyle senkron, üst üste
## binmez) + tren içi LED ekranlar (mevcut/sonraki istasyon, güzergâh, kapı yönü, son istasyon)
## + istasyon PIS ekranları (yaklaşan trenin yönü, tahmini varış, sefer no, gecikme uyarısı).
## Tüm metinler gerçek simülasyon verisinden (MissionManager, TrafficManager, TrainController).

var train: TrainController
var route: RouteData
var mission: MissionManager
var traffic: TrafficManager
var world: TrackBuilder
var visual: TrainVisual
var bilingual: bool = true
var _timer := 0.0
var _phase := 0
var _approach_done: Dictionary = {}
var _mode := "idle"       # idle | next | approach | arrived | closing | terminus
var _station_timer := 0.0
var _closing_flag := false

func setup(p_train: TrainController, p_route: RouteData, p_mission: MissionManager, p_traffic: TrafficManager, p_world: TrackBuilder) -> void:
	train = p_train
	route = p_route
	mission = p_mission
	traffic = p_traffic
	world = p_world
	visual = train.visual
	AudioManager.bilingual = bilingual
	mission.departed_station.connect(_on_departed)
	mission.arrived_at_station.connect(_on_arrived)
	mission.doors_opened_at_station.connect(_on_doors_opened)
	mission.state_changed.connect(_on_state_changed)
	train.doors.doors_closing.connect(_on_doors_closing)
	train.doors.doors_closed.connect(_on_doors_closed)
	train.emergency_changed.connect(_on_emergency)
	traffic.lead_train_delayed.connect(_on_lead_delayed)
	visual.set_destination(route.terminus)
	_set_mode("idle")
	AudioManager.announce("welcome_" + route.direction)

func set_bilingual(on: bool) -> void:
	bilingual = on
	AudioManager.bilingual = on
	Scoring.log_event("Anons dili: %s" % ("TR + EN" if on else "yalnız TR"))

## Kabin düğmesi: sonraki istasyon anonsunu manuel çal
func manual_announce() -> void:
	var nxt := mission.target_station()
	if nxt.is_empty():
		return
	if mission.state == MissionManager.State.ARRIVED or mission.state == MissionManager.State.DWELL:
		var st := mission.current_station()
		if st.get("is_end", false):
			AudioManager.announce("terminus_" + str(st["id"]), true)
		else:
			AudioManager.announce("arrive_%s_%s" % [str(st["id"]), str(st.get("door_side", "right"))], true)
	else:
		AudioManager.announce("next_" + str(nxt["id"]), true)
	Scoring.log_event("Manuel anons: %s" % str(nxt["name"]))

func _set_mode(m: String) -> void:
	_mode = m
	_phase = 0
	_timer = 0.0
	_refresh_onboard()

# --- Olaylar ---------------------------------------------------------------

func _on_departed(_st: Dictionary) -> void:
	var nxt := mission.next_station()
	if not nxt.is_empty():
		AudioManager.announce("next_" + str(nxt["id"]))
	_set_mode("next")

func _on_arrived(st: Dictionary, _err: float) -> void:
	_set_mode("terminus" if st.get("is_end", false) else "arrived")

func _on_doors_opened(_st: Dictionary, _side: String, _correct: bool) -> void:
	_closing_flag = false
	_refresh_onboard()

func _on_doors_closing(_side: String) -> void:
	_closing_flag = true
	AudioManager.announce("closing", true)
	_refresh_onboard()

func _on_doors_closed(_side: String) -> void:
	_closing_flag = false
	_refresh_onboard()

func _on_state_changed(s: int) -> void:
	if s == MissionManager.State.READY and mission.departure_timer > 10.0:
		AudioManager.announce("hold")

func _on_emergency(active: bool, _reasons: Array) -> void:
	if active and train.speed_kmh() > 5.0:
		AudioManager.announce("emergency", true)

func _on_lead_delayed(_st: Dictionary, _s: float) -> void:
	if mission.state == MissionManager.State.READY or mission.state == MissionManager.State.DWELL:
		AudioManager.announce("delay")

# --- Yaklaşım (mesafe tabanlı: 320 m kala varış anonsu) ----------------------

func _process(delta: float) -> void:
	if GameState.paused or GameState.phase == GameState.Phase.BRIEFING:
		return
	_timer += delta
	if mission.state == MissionManager.State.RUNNING:
		var nxt := mission.target_station()
		if not nxt.is_empty():
			var sid := str(nxt["id"])
			var d: float = float(nxt["stop_pos"]) - train.offset
			if d < 320.0 and d > 0.0 and not _approach_done.get(sid, false) and train.speed_kmh() > 3.0:
				_approach_done[sid] = true
				if nxt.get("is_end", false):
					AudioManager.announce("terminus_" + sid)
				else:
					AudioManager.announce("arrive_%s_%s" % [sid, str(nxt.get("door_side", "right"))])
				_set_mode("approach")
	# Tren içi ekran: 3 sn'de bir TR/EN sayfa değişimi
	if _timer >= 3.0:
		_timer = 0.0
		_phase += 1
		_refresh_onboard()
	# İstasyon ekranları: saniyede bir
	_station_timer -= delta
	if _station_timer <= 0.0:
		_station_timer = 1.0
		_refresh_stations()

func _refresh_onboard() -> void:
	if visual == null:
		return
	var en := bilingual and (_phase % 2 == 1)
	var nxt := mission.target_station()
	var cur := mission.current_station()
	var txt := ""
	var col := Color(1.0, 0.62, 0.12)
	match _mode:
		"idle":
			txt = ("ARS Line 4 · to %s" % _en_name(route.terminus)) if en else ("ARS Hat 4 · %s" % route.direction_label)
		"next":
			if nxt.is_empty():
				txt = "ARS Hat 4"
			else:
				txt = ("Next station: %s" % _en_name(str(nxt["name"]))) if en else ("Sonraki istasyon: %s" % str(nxt["name"]))
		"approach":
			if not nxt.is_empty():
				var side_tr: String = "sağdan" if str(nxt.get("door_side", "right")) == "right" else "soldan"
				var side_en: String = "right" if str(nxt.get("door_side", "right")) == "right" else "left"
				txt = ("%s · doors open on the %s" % [_en_name(str(nxt["name"])), side_en]) if en else ("%s · kapılar %s açılır" % [str(nxt["name"]), side_tr])
		"arrived":
			if not cur.is_empty():
				txt = ("This is %s" % _en_name(str(cur["name"]))) if en else ("Bu istasyon: %s" % str(cur["name"]))
		"terminus":
			txt = "Last stop · please alight" if en else "Son istasyon · lütfen ininiz"
			col = Color(1.0, 0.35, 0.2)
	if _closing_flag:
		txt = "Doors closing · stand clear" if en else "Kapılar kapanıyor · uzak durun"
		col = Color(1.0, 0.25, 0.2)
	visual.set_pis_text(txt, col)

func _en_name(n: String) -> String:
	var m := {"Sabiha Gökçen Havalimanı": "Sabiha Gökçen Airport", "Fevzi Çakmak-Hastane": "Fevzi Çakmak-Hospital"}
	return str(m.get(n, n))

## İstasyon PIS: oyuncu treni + öndeki sefer için tahmini varış (gerçek konum/hız)
func _refresh_stations() -> void:
	if world == null:
		return
	var lead := traffic.lead_info() if traffic else {}
	for st in route.stations:
		var node := world.get_station_node(str(st["id"]))
		if node == null or not node.visible:
			continue
		var d: float = float(st["stop_pos"]) - train.offset
		var lines: Array[String] = []
		var sn := str(GameState.mission.get("service_number", ""))
		if d > 0.0 and d < 60000.0 and mission.state != MissionManager.State.FINISHED:
			var eta := _eta_seconds(d, train.offset, float(st["stop_pos"]))
			if d < 350.0 and train.speed_kmh() > 3.0:
				lines.append("%s · %s · TREN YAKLAŞIYOR" % [route.direction_label, sn])
			elif absf(d) < 1.0 or (d < 25.0 and train.is_stopped()):
				lines.append("%s · %s · PERONDA" % [route.direction_label, sn])
			else:
				lines.append("%s · %s · %s" % [route.direction_label, sn, _fmt_eta(eta)])
		elif absf(d) < 25.0:
			lines.append("%s · %s · PERONDA" % [route.direction_label, sn])
		if not lead.is_empty():
			var dl: float = float(st["stop_pos"]) - float(lead["offset"])
			if dl > 0.0:
				lines.append("%s · %s · %s" % [route.direction_label, str(lead["service"]), _fmt_eta(_eta_seconds(dl, float(lead["offset"]), float(st["stop_pos"])))])
		# Gecikme uyarısı (tarife farkı)
		var delay := _schedule_delay()
		if delay > 60.0:
			lines.append("GECİKME UYARISI · +%d dk" % int(delay / 60.0))
		if lines.is_empty():
			lines.append("%s · tren bilgisi yok" % route.direction_label)
		node.set_pis("  ·  ".join(lines))

func _eta_seconds(dist: float, from_off: float, to_off: float) -> float:
	# Ortalama 45 km/s + aradaki her istasyon için 35 sn
	var t := dist / (45.0 / 3.6)
	for s in route.stations:
		var p := float(s["stop_pos"])
		if p > from_off + 30.0 and p < to_off - 30.0:
			t += 35.0
	return t

func _fmt_eta(sec: float) -> String:
	if sec < 60.0:
		return "1 dk"
	return "%d dk" % int(ceil(sec / 60.0))

func _schedule_delay() -> float:
	if mission == null or mission.stop_index <= 0:
		return 0.0
	var st := mission.current_station()
	if st.is_empty():
		return 0.0
	var planned := route.schedule_for(int(st["index"]))
	return GameState.mission_time - planned
