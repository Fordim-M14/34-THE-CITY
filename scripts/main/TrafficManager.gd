class_name TrafficManager
extends Node
## TrafficManager — hat trafiği ve sinyalizasyon:
##   • Öndeki sefer (lead train) basit fizikle gerçekten simüle edilir (hızlanma, fren,
##     istasyon beklemesi, rastgele gecikme). 3B modeli yoktur; konumu sinyalleri belirler.
##   • Blok sinyalleri: bir blok öndeki trenin kapladığı aralıksa KIRMIZI, bir sonraki
##     blok doluysa SARI, aksi halde YEŞİL. Kalkış sinyalleri ayrıca görev iznine bağlıdır.
##   • Merkez (OCC) mesajları: gerçek olaylardan üretilir (öndeki tren gecikmesi, regülasyon
##     beklemesi, geçici hız kısıtlaması).
##   • Operasyonel olaylar: istasyonda regülasyon beklemesi, geçici hız kısıtlaması (TSR).

signal message(text: String, requires_ack: bool)
signal lead_train_delayed(station: Dictionary, seconds: float)

const HEADWAY_S := 240.0
const LEAD_TRACTION := 0.9
const LEAD_BRAKE := 0.8

var train: TrainController
var route: RouteData
var world: TrackBuilder
var mission: MissionManager
var rng := RandomNumberGenerator.new()
var enabled: bool = true

# Öndeki tren
var lead_active: bool = true
var lead_offset: float = 0.0
var lead_speed: float = 0.0
var lead_stop_index: int = 0
var lead_dwell: float = 0.0
var lead_service: String = "4105"
var lead_delay_total: float = 0.0
var lead_state: String = "dwell"   # dwell | run | done

# TSR (geçici hız kısıtlaması)
var tsr: Dictionary = {}   # {"from","to","limit","reason"}

# Mesajlar
var messages: Array = []   # [{time, text, ack}]
var pending_ack: String = ""
var _signal_timer := 0.0
var _sorted_signals: Array = []   # TrackSignal, pos sırasına göre
var _tsr_flag := false

# Görsel trenler (v0.4): öndeki sefer + karşı yön seferleri (ikinci hat, world.opp_x)
const OPP_HEADWAY_S := 200.0
const OPP_TRACTION := 0.9
const OPP_BRAKE := 0.85
const OPP_DWELL := 22.0
var lead_visual: OtherTrain
var opp_trains: Array = []     # [{offset(burun, azalan), speed, state, dwell, stop_index, visual, service}]
var _opp_spawn_timer := 0.0
var visual_trains_enabled: bool = true

func setup(p_train: TrainController, p_route: RouteData, p_world: TrackBuilder, p_mission: MissionManager, seed: int) -> void:
	train = p_train
	route = p_route
	world = p_world
	mission = p_mission
	rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())
	_sorted_signals = world.signals_by_id.values()
	_sorted_signals.sort_custom(func(a: TrackSignal, b: TrackSignal) -> bool: return a.track_pos < b.track_pos)
	mission.departure_requested.connect(_on_departure_requested)
	mission.departure_cleared.connect(_on_departure_cleared)
	mission.departed_station.connect(_on_departed)
	train.atp_intervention.connect(func() -> void: _say("Merkez: %s, ATP müdahalesi kaydedildi. Hız limitlerine uyun." % str(GameState.mission.get("service_number", "")), false, "radio_atp"))
	train.spad_permission_granted.connect(func() -> void: _say("Merkez: %s, hareket izniniz verilmiştir. Acil freni sıfırlayıp (Shift+R) dikkatli ilerleyin." % str(GameState.mission.get("service_number", "")), false, "radio_spad_permit"))
	train.spad.connect(_on_spad)
	_init_lead_train()
	_init_tsr()
	_update_signals()
	_init_visual_trains()

# ---------------------------------------------------------------------------
# Öndeki tren

func _init_lead_train() -> void:
	lead_active = enabled and route.stations.size() > 1
	lead_offset = float(route.stations[0]["stop_pos"])
	lead_speed = 0.0
	lead_stop_index = 0
	lead_dwell = 0.0
	lead_state = "run"
	# Sefer numarası: oyuncununkinden 2 küçük
	var sn := int(GameState.mission.get("service_number", "4107"))
	lead_service = str(sn - 2)
	# HEADWAY kadar önceden yola çıkmış olsun: ön simülasyon
	var t := 0.0
	while t < HEADWAY_S and lead_state != "done":
		_step_lead(0.1, false)
		t += 0.1

func _step_lead(delta: float, allow_random: bool) -> void:
	if not lead_active or lead_state == "done":
		return
	if lead_state == "dwell":
		lead_dwell -= delta
		if lead_dwell <= 0.0:
			lead_state = "run"
		return
	# Hedef: sonraki istasyon
	if lead_stop_index + 1 >= route.stations.size():
		lead_state = "done"
		lead_active = false
		return
	var nxt: Dictionary = route.stations[lead_stop_index + 1]
	var stop_pos: float = float(nxt["stop_pos"])
	var d := stop_pos - lead_offset
	var limit := (route.get_speed_limit_kmh(lead_offset) - 4.0) / 3.6
	var up := route.get_upcoming_limit(lead_offset, 400.0)
	if not up.is_empty():
		var lim2 := (float(up["limit_kmh"]) - 4.0) / 3.6
		limit = minf(limit, sqrt(maxf(lim2 * lim2 + 2.0 * LEAD_BRAKE * float(up["distance"]), 0.0)))
	var target := limit
	if d > 0.0:
		target = minf(target, sqrt(2.0 * LEAD_BRAKE * d))
	if d <= 0.3:
		# Vardı
		lead_offset = stop_pos
		lead_speed = 0.0
		lead_stop_index += 1
		lead_dwell = route.dwell_seconds + rng.randf_range(0.0, 8.0)
		lead_state = "dwell"
		if allow_random and rng.randf() < 0.30 and not nxt.get("is_end", false):
			var extra := rng.randf_range(35.0, 90.0)
			lead_dwell += extra
			lead_delay_total += extra
			var reasons := ["yolcu yoğunluğu", "kapı kontrolü", "yolcu rahatsızlığı", "merkez regülasyonu"]
			var why: String = reasons[rng.randi_range(0, reasons.size() - 1)]
			_say("Öndeki sefer %s, %s istasyonunda %s nedeniyle yaklaşık %d sn bekleyecek. Sinyallere uyun." % [lead_service, str(nxt["name"]), why, int(extra)], false, "radio_lead_delay")
			lead_train_delayed.emit(nxt, extra)
		return
	if lead_speed < target:
		lead_speed = minf(lead_speed + LEAD_TRACTION * delta, target)
	else:
		lead_speed = maxf(lead_speed - LEAD_BRAKE * delta, target)
	lead_offset += lead_speed * delta

func lead_tail() -> float:
	return lead_offset - train.train_length()

func lead_info() -> Dictionary:
	if not lead_active:
		return {}
	var st_name := ""
	if lead_state == "dwell" and lead_stop_index < route.stations.size():
		st_name = str(route.stations[lead_stop_index]["name"])
	return {"service": lead_service, "offset": lead_offset, "speed_kmh": lead_speed * 3.6,
		"state": lead_state, "station": st_name, "distance": lead_tail() - train.offset}

# ---------------------------------------------------------------------------
# Sinyaller

func _process(delta: float) -> void:
	if GameState.paused or GameState.phase == GameState.Phase.BRIEFING:
		return
	_step_lead(delta, true)
	_step_opposing(delta)
	_update_visual_trains()
	_signal_timer -= delta
	if _signal_timer <= 0.0:
		_signal_timer = 0.2
		_update_signals()
	_update_tsr()

func _block_occupied(from_pos: float, to_pos: float) -> bool:
	if not lead_active:
		return false
	return lead_tail() < to_pos and lead_offset >= from_pos

func _update_signals() -> void:
	var n := _sorted_signals.size()
	for i in n:
		var sig: TrackSignal = _sorted_signals[i]
		var b_start := sig.track_pos
		var b_end: float = _sorted_signals[i + 1].track_pos if i + 1 < n else route.buffer_end
		var b2_end: float = _sorted_signals[i + 2].track_pos if i + 2 < n else route.buffer_end
		var aspect := "green"
		if _block_occupied(b_start, b_end):
			aspect = "red"
		elif i + 1 < n and _block_occupied(b_end, b2_end):
			aspect = "yellow"
		if sig.signal_type == "departure":
			# Kalkış izni: görev durumu READY ve izin verilmiş olmalı; tren bu istasyondaysa
			var st_id := sig.station_id
			var cur := mission.current_station()
			var at_this := str(cur["id"]) == st_id and train.offset < sig.track_pos
			var waiting := mission.state == MissionManager.State.BOARDING or mission.state == MissionManager.State.READY or mission.state == MissionManager.State.ARRIVED or mission.state == MissionManager.State.DWELL
			if at_this and waiting and not GameState.departure_cleared:
				aspect = "red"
		if sig.forced_red:
			aspect = "red"
		elif sig.forced_yellow:
			aspect = "yellow"
		if sig.aspect != aspect:
			sig.set_aspect(aspect)

## HUD/MMI: önümüzdeki sinyalin nedeni
func signal_reason(sig: TrackSignal) -> String:
	if sig.forced_red:
		return "SİNYAL ARIZASI — merkezi arayın"
	if sig.forced_yellow:
		return "arıza izni: 25 km/s"
	if sig.aspect == "red":
		if sig.signal_type == "departure" and not GameState.departure_cleared:
			return "kalkış izni yok"
		if lead_active:
			return "blok dolu — sefer %s önde" % lead_service
		return "blok dolu"
	if sig.aspect == "yellow":
		return "sonraki sinyal kırmızı"
	return "serbest"

# ---------------------------------------------------------------------------
# Olaylar

func _on_departure_requested(st: Dictionary) -> void:
	# %25: merkez regülasyonu (ilk istasyon hariç)
	if enabled and not st.get("is_start", false) and rng.randf() < 0.25:
		var hold := rng.randf_range(20.0, 45.0)
		mission.departure_hold = hold
		mission.departure_timer = hold
		_say("Merkez: %s istasyonunda regülasyon — %d sn bekleyin, kalkış sinyali yeşile dönünce hareket edin." % [str(st["name"]), int(hold)], false, "radio_regulation")

func _on_departed(_st: Dictionary) -> void:
	# Bir sonraki istasyon yaklaşımında TSR varsa hatırlat
	if not tsr.is_empty():
		var nxt := mission.next_station()
		if not nxt.is_empty() and float(tsr["from"]) > train.offset and float(tsr["from"]) < float(nxt["stop_pos"]):
			_say("Merkez: %s, %s yaklaşımında hızınızı %d km/s'ye düşürün (%s)." % [str(GameState.mission.get("service_number", "")), str(nxt["name"]), int(tsr["limit"]), str(tsr["reason"])], false, "radio_tsr")

func _on_departure_cleared(st: Dictionary) -> void:
	if enabled and not st.get("is_start", false) and rng.randf() < 0.6:
		_say("Merkez: %s, kalkış izniniz verilmiştir." % str(GameState.mission.get("service_number", "")), false, "radio_departure_ok")
	elif st.get("is_start", false):
		_say("Merkez: %s numaralı sefer, %s'den kalkış izniniz verilmiştir. İyi seferler." % [str(GameState.mission.get("service_number", "")), str(st["name"])], false, "radio_departure_ok")

func _on_spad(sig: TrackSignal) -> void:
	_say("Merkez: %s sinyali kırmızıda geçildi! Trenin durdurulduğunu onaylayın (F). İzin verilene kadar bekleyin." % sig.signal_id, true, "radio_spad")

func _init_tsr() -> void:
	tsr = {}
	if not enabled or rng.randf() > 0.5:
		return
	# İstasyon dışı bir bölgede 300 m'lik 40 km/s kısıtlaması
	for attempt in 10:
		var i := rng.randi_range(0, route.stations.size() - 2)
		var a: float = float(route.stations[i]["platform_end"]) + 300.0
		var b: float = float(route.stations[i + 1]["platform_start"]) - 400.0
		if b - a > 400.0:
			var from_pos := rng.randf_range(a, b - 300.0)
			tsr = {"from": from_pos, "to": from_pos + 300.0, "limit": 40.0, "reason": "ray bakımı"}
			break
	if tsr.is_empty():
		return
	# Hat kenarına geçici levha
	var xf := world.get_track_transform(float(tsr["from"]) - 60.0)
	var board := Label3D.new()
	board.text = "GEÇİCİ\n40"
	board.font_size = 64
	board.pixel_size = 0.004
	board.modulate = Color(1.0, 0.85, 0.1)
	board.outline_modulate = Color(0.1, 0.1, 0.1)
	board.outline_size = 10
	board.transform = xf.translated_local(Vector3(2.3, 2.6, 0.0))
	world.add_child(board)
	var xf2 := world.get_track_transform(float(tsr["to"]))
	var board2 := Label3D.new()
	board2.text = "KISIT\nSONU"
	board2.font_size = 48
	board2.pixel_size = 0.004
	board2.modulate = Color(0.6, 1.0, 0.6)
	board2.transform = xf2.translated_local(Vector3(2.3, 2.6, 0.0))
	world.add_child(board2)

func tsr_text() -> String:
	if tsr.is_empty():
		return ""
	return "Geçici hız kısıtlaması: km %s – %s arası %d km/s (%s)" % [_km(float(tsr["from"])), _km(float(tsr["to"])), int(tsr["limit"]), str(tsr["reason"])]

func _km(p: float) -> String:
	return "%d+%03d" % [int(p / 1000.0), int(fmod(p, 1000.0))]

func _update_tsr() -> void:
	if tsr.is_empty():
		return
	var inside: bool = train.offset >= float(tsr["from"]) - train.train_length() and train.offset < float(tsr["to"])
	train.temp_speed_restriction_kmh = float(tsr["limit"]) if inside else 0.0
	if inside and not _tsr_flag:
		_tsr_flag = true
	elif not inside:
		_tsr_flag = false

func announce_tsr() -> void:
	if not tsr.is_empty():
		_say("Merkez: " + tsr_text(), false)

func _say(text: String, requires_ack: bool, voice: String = "") -> void:
	messages.append({"time": GameState.clock_text(), "text": text, "ack": requires_ack})
	if requires_ack:
		pending_ack = text
	Scoring.log_event("MERKEZ: " + text)
	message.emit(text, requires_ack)
	if voice != "":
		AudioManager.play_radio(voice)
	if train and train.visual:
		train.visual.set_radio_text("MERKEZ ▸ " + text.left(22))

func acknowledge() -> void:
	pending_ack = ""


## Makinist telsizle merkezi arar (PTT): durum bilgisi / izin isteği
func driver_call() -> void:
	var txt := ""
	if train.has_reason(TrainController.EmergencyReason.SPAD) and not train.spad_permission:
		if not train.spad_acknowledged:
			train.acknowledge()
		txt = "Merkez: %s, sinyal ihlali kaydedildi. Treni durdurun, izin bekleyin." % str(GameState.mission.get("service_number", ""))
		_say(txt, false, "radio_spad")
		return
	elif mission and mission.state == MissionManager.State.READY and mission.departure_timer > 0.0:
		txt = "Merkez: %s, kalkış için %d sn bekleyin." % [str(GameState.mission.get("service_number", "")), int(ceil(mission.departure_timer))]
		_say(txt, false, "radio_regulation")
		return
	else:
		var nxt := mission.target_station() if mission else {}
		txt = "Merkez: %s, anlaşıldı. Sonraki durak %s, hat normal." % [str(GameState.mission.get("service_number", "")), str(nxt.get("name", "—"))]
	_say(txt, false, "radio_ack")


# ---------------------------------------------------------------------------
# Görsel trenler: öndeki sefer (aynı hat) + karşı yön seferleri (ikinci hat)

func _init_visual_trains() -> void:
	if not visual_trains_enabled or not enabled:
		return
	var dest_fwd := route.terminus
	lead_visual = OtherTrain.new()
	lead_visual.name = "LeadTrain"
	world.add_child(lead_visual)
	lead_visual.build(world, train.car_count, 0.0, 1, dest_fwd)
	# Karşı yön: hat sonundan başlayıp azalan ofsetle gelen 3 sefer, HEADWAY aralıkla
	var opp_dest := str(route.raw.get("terminus_reverse", "")) if dest_fwd == str(route.raw.get("terminus_forward", "")) else str(route.raw.get("terminus_forward", ""))
	if opp_dest == "":
		opp_dest = str(route.stations[0].get("name", ""))
	var sn := int(GameState.mission.get("service_number", "4107"))
	for k in 3:
		var t := OtherTrain.new()
		t.name = "OppTrain%d" % k
		world.add_child(t)
		t.build(world, train.car_count, world.opp_x, -1, opp_dest)
		var o := {"offset": route.track_length - 30.0, "speed": 0.0, "state": "run", "dwell": 0.0,
			"stop_index": route.stations.size() - 1, "visual": t, "service": str(sn + 1 + k * 2)}
		opp_trains.append(o)
		# Ön simülasyon: k·HEADWAY kadar ilerlemiş olsun
		var tt := 0.0
		while tt < OPP_HEADWAY_S * (k + 0.5):
			_step_one_opp(o, 0.2)
			tt += 0.2
	_opp_spawn_timer = OPP_HEADWAY_S

## Karşı yön treni: azalan ofsette ilerler, istasyonlarda (karşı peron) durur, hat başında yeniden doğar
func _step_one_opp(o: Dictionary, delta: float) -> void:
	if o["state"] == "dwell":
		o["dwell"] = float(o["dwell"]) - delta
		if float(o["dwell"]) <= 0.0:
			o["state"] = "run"
		return
	var idx: int = int(o["stop_index"]) - 1
	var off: float = float(o["offset"])
	var speed: float = float(o["speed"])
	if idx < 0:
		# Hat başına kadar git, sonra yeniden doğ (hat sonundan)
		var limit0 := (route.get_speed_limit_kmh(maxf(off, 0.0)) - 4.0) / 3.6
		speed = minf(speed + OPP_TRACTION * delta, limit0)
		off -= speed * delta
		if off < -train.train_length() - 40.0:
			off = route.track_length - 30.0
			speed = 0.0
			o["stop_index"] = route.stations.size() - 1
			o["state"] = "dwell"
			o["dwell"] = rng.randf_range(5.0, 40.0)
		o["offset"] = off
		o["speed"] = speed
		return
	var st: Dictionary = route.stations[idx]
	# Karşı peronda duruş: burun, peron başlangıcı + tren boyu (burun peronun ilerisinde)
	var stop_pos: float = float(st["platform_start"]) + train.train_length() + 1.0
	var d := off - stop_pos
	var limit := (route.get_speed_limit_kmh(off) - 4.0) / 3.6
	var target := limit
	if d > 0.0:
		target = minf(target, sqrt(2.0 * OPP_BRAKE * d))
	if d <= 0.3:
		o["offset"] = stop_pos
		o["speed"] = 0.0
		o["stop_index"] = idx
		o["state"] = "dwell"
		o["dwell"] = OPP_DWELL + rng.randf_range(0.0, 10.0)
		return
	if speed < target:
		speed = minf(speed + OPP_TRACTION * delta, target)
	else:
		speed = maxf(speed - OPP_BRAKE * delta, target)
	off -= speed * delta
	o["offset"] = off
	o["speed"] = speed

func _step_opposing(delta: float) -> void:
	for o in opp_trains:
		_step_one_opp(o, delta)

func _update_visual_trains() -> void:
	if lead_visual:
		if lead_active and lead_state != "done":
			lead_visual.visible = true
			lead_visual.place(lead_offset, train.offset)
		else:
			lead_visual.visible = false
	for o in opp_trains:
		var t: OtherTrain = o["visual"]
		t.place(float(o["offset"]), train.offset)

## En yakın karşı yön treni (HUD/MMI bilgisi için): {"distance", "speed_kmh", "service"}
func nearest_opposing() -> Dictionary:
	var best := {}
	var bd := INF
	for o in opp_trains:
		var d := absf(float(o["offset"]) - train.train_length() * 0.5 - train.offset)
		if d < bd:
			bd = d
			best = {"distance": d, "speed_kmh": float(o["speed"]) * 3.6, "service": str(o["service"]), "state": str(o["state"])}
	return best
