class_name FaultManager
extends Node
## FaultManager — rastgele fakat mantıklı arızalar ve çözüm prosedürleri.
## Her arıza: tetikleme koşulu, etkisi (tren parametreleri/sinyal/MMI), prosedür ve
## çözüm koşulu. Arızalar MMI "ARIZA" sayfasında görünür, HUD'da uyarı verir ve
## sefer zamanlamasını doğal olarak etkiler. Prosedür uygulanmazsa ceza uygulanır.

signal fault_started(fault: Dictionary)
signal fault_resolved(fault: Dictionary)
signal fault_message(text: String)

var train: TrainController
var route: RouteData
var mission: MissionManager
var rng := RandomNumberGenerator.new()
var enabled: bool = true
var active: Array = []          # aktif arızalar (Dictionary)
var scheduled: Array = []       # planlanan: {"id", "trigger": "time"/"station_close"/"station_dwell"/"running", "at"}
var resolved_count: int = 0
var _time := 0.0
var _ack_requested := false
var _mmi: MMIScreen

const DEFS := {
	"door_fault": {
		"title": "KAPI ARIZASI",
		"description": "Bir kapı çifti kapanmıyor (kapı yolu engeli / kilit sensörü).",
		"procedure": "Kapıları yeniden kapatın (KAPAT). İki denemede kapanmazsa F ile kapıyı izole edin.",
	},
	"brake_warning": {
		"title": "FREN SİSTEMİ UYARISI",
		"description": "Bir araçta fren basıncı düşük. Servis freni verimi %70.",
		"procedure": "Hızı 50 km/s altında tutun. Sonraki istasyonda duruşta kolu TAM FREN'de 3 sn tutarak fren testi yapın.",
	},
	"power_loss": {
		"title": "KATENER GERİLİMİ KESİK",
		"description": "Hat gerilimi kesildi; çekiş yok. Fren ve aydınlatma batarya ile çalışıyor.",
		"procedure": "Kolu NÖTR'e alın ve bekleyin. Gerilim gelince MMI bilgi verir; kol nötr değilse çekiş devreye girmez.",
	},
	"signal_fault": {
		"title": "SİNYAL ARIZASI",
		"description": "İleride bir sinyal arızalı olarak KIRMIZIDA kalıyor.",
		"procedure": "Sinyal önünde durun, F ile merkezi arayın. İzin gelince sinyal SARI'ya alınır; 25 km/s ile geçin.",
	},
	"traction_fault": {
		"title": "ÇEKİŞ MOTORU ARIZASI",
		"description": "Bir bojide çekiş inverteri devre dışı; çekiş gücü %60.",
		"procedure": "Sonraki istasyonda duruşta F ile çekiş sistemini yeniden başlatın (10 sn).",
	},
	"mmi_fault": {
		"title": "MMI EKRAN ARIZASI",
		"description": "Makinist bilgi ekranı yanıt vermiyor; yeniden başlatılıyor.",
		"procedure": "Analog hız saatini ve HUD'ı kullanın. Ekran ~20 sn içinde geri gelir.",
	},
	"passenger_delay": {
		"title": "YOLCU KAYNAKLI GECİKME",
		"description": "Bir kapıda yolcu sıkışması / rahatsızlanan yolcu. Kalkış ertelendi.",
		"procedure": "Kapıları AÇIK tutun, F ile merkeze bildirin. Merkez onayı sonrası kapatıp kalkın.",
	},
	"emergency_alarm": {
		"title": "YOLCU İMDAT ALARMI",
		"description": "Bir araçta yolcu imdat kolu çekildi.",
		"procedure": "TÜNELDE DURMAYIN. Sonraki istasyona ilerleyin, kapıları açın ve F ile alarmı sıfırlayın.",
	},
}

func setup(p_train: TrainController, p_route: RouteData, p_mission: MissionManager, seed: int) -> void:
	train = p_train
	route = p_route
	mission = p_mission
	rng.seed = seed
	mission.departure_requested.connect(_on_departure_requested)
	mission.doors_opened_at_station.connect(_on_doors_opened)
	mission.arrived_at_station.connect(_on_arrived)
	mission.departed_station.connect(_on_departed)
	train.doors.doors_closing.connect(_on_doors_closing)
	train.doors.doors_closed.connect(_on_doors_closed)
	_plan()

func set_mmi(m: MMIScreen) -> void:
	_mmi = m

func _plan() -> void:
	scheduled.clear()
	if not enabled:
		return
	var n_st := route.stations.size()
	var count := 0
	var r := rng.randf()
	if r < 0.25:
		count = 0
	elif r < 0.75:
		count = 1
	else:
		count = 2
	var pool := DEFS.keys()
	# rng ile deterministik karıştırma
	for i in pool.size():
		var j := rng.randi_range(0, pool.size() - 1)
		var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	for i in count:
		var id: String = pool[i]
		var entry := {"id": id}
		match id:
			"door_fault":
				entry["trigger"] = "station_close"
				entry["station"] = rng.randi_range(0, n_st - 2)
			"passenger_delay":
				entry["trigger"] = "station_dwell"
				entry["station"] = rng.randi_range(1, n_st - 2) if n_st > 2 else 0
			"brake_warning", "power_loss", "traction_fault", "mmi_fault", "emergency_alarm", "signal_fault":
				entry["trigger"] = "running"
				entry["leg"] = rng.randi_range(0, n_st - 2)
				entry["frac"] = rng.randf_range(0.15, 0.6)
		scheduled.append(entry)

func active_faults() -> Array:
	return active

func has_fault(id: String) -> bool:
	for f in active:
		if f["id"] == id:
			return true
	return false

func find_fault(id: String) -> Dictionary:
	for f in active:
		if f["id"] == id:
			return f
	return {}

func _start(id: String, extra: Dictionary = {}) -> void:
	if has_fault(id):
		return
	var f := {"id": id, "title": DEFS[id]["title"], "description": DEFS[id]["description"],
		"procedure": DEFS[id]["procedure"], "progress": "", "t": 0.0, "acked": false, "attempts": 0}
	for k in extra:
		f[k] = extra[k]
	active.append(f)
	Scoring.stats["faults"] = int(Scoring.stats["faults"]) + 1
	Scoring.log_event("ARIZA: %s" % f["title"])
	match id:
		"door_fault":
			var side := str(mission.current_station().get("door_side", "right"))
			var idx := rng.randi_range(0, train.doors.pair_count(side) - 1)
			train.doors.set_stuck(side, idx)
			f["side"] = side
			f["door"] = idx
			f["description"] = "Araç %d %s kapı çifti kapanmıyor (kilit sensörü)." % [int(idx / 3) + 1, "sağ" if side == "right" else "sol"]
		"brake_warning":
			train.brake_factor = 0.7
		"power_loss":
			train.traction_cut = true
			f["duration"] = rng.randf_range(15.0, 30.0)
		"traction_fault":
			train.traction_factor = 0.6
		"mmi_fault":
			if _mmi:
				_mmi.blackout = true
			f["duration"] = 20.0
		"passenger_delay":
			mission.dwell_timer = maxf(mission.dwell_timer, 1.0) + rng.randf_range(25.0, 45.0)
			mission.extra_dwell_from_passengers = 0.0
		"emergency_alarm":
			train.visual.set_lamp("fault", true)
		"signal_fault":
			var sg := _pick_signal_ahead()
			if sg == null:
				active.erase(f)
				return
			f["signal"] = sg
			sg.forced_red = true
			sg.set_aspect("red")
			f["description"] = "%s sinyali arızalı — kırmızıda kalıyor (blok boş)." % sg.signal_id
	train.visual.set_lamp("fault", true)
	fault_started.emit(f)
	fault_message.emit("ARIZA: %s — %s" % [f["title"], f["procedure"]])

func _pick_signal_ahead() -> TrackSignal:
	var best: TrackSignal = null
	var best_d := INF
	for id in train.world.signals_by_id:
		var sg: TrackSignal = train.world.signals_by_id[id]
		var d := sg.track_pos - train.offset
		if sg.signal_type == "block" and d > 400.0 and d < best_d:
			best_d = d
			best = sg
	return best

func _resolve(f: Dictionary, ok_text: String) -> void:
	active.erase(f)
	resolved_count += 1
	Scoring.stats["faults_resolved"] = int(Scoring.stats["faults_resolved"]) + 1
	Scoring.log_event("Arıza giderildi: %s — %s" % [f["title"], ok_text])
	match f["id"]:
		"door_fault": train.doors.clear_stuck()
		"brake_warning": train.brake_factor = 1.0
		"power_loss": train.traction_cut = false
		"traction_fault": train.traction_factor = 1.0
		"mmi_fault":
			if _mmi:
				_mmi.blackout = false
				_mmi.flicker = false
		"signal_fault":
			var sg: TrackSignal = f.get("signal")
			if sg:
				sg.forced_red = false
	if active.is_empty():
		train.visual.set_lamp("fault", false)
	fault_resolved.emit(f)
	fault_message.emit("Arıza giderildi: %s" % f["title"])

func acknowledge() -> void:
	for f in active:
		if not f["acked"]:
			f["acked"] = true
			f["ack_t"] = f["t"]
			match f["id"]:
				"door_fault":
					if f["attempts"] >= 2:
						f["progress"] = "Kapı izole edildi (yolcu bilgilendirildi)"
						_resolve(f, "kapı izole edildi")
					else:
						f["acked"] = false
						f["progress"] = "Önce iki kapatma denemesi yapın (%d/2)" % f["attempts"]
				"signal_fault":
					var sg: TrackSignal = f.get("signal")
					if sg and train.is_stopped() and sg.track_pos - train.offset < 80.0 and sg.track_pos > train.offset:
						f["progress"] = "Merkez aranıyor… izin bekleniyor (8 sn)"
					else:
						f["acked"] = false
						f["progress"] = "Önce sinyalin önünde (80 m içinde) durun"
				"traction_fault":
					if train.is_stopped() and not route.get_station_at(train.offset).is_empty():
						f["progress"] = "Çekiş sistemi yeniden başlatılıyor (10 sn)…"
					else:
						f["acked"] = false
						f["progress"] = "Yeniden başlatma yalnızca istasyonda duruşta"
				"passenger_delay":
					f["progress"] = "Merkez bilgilendirildi — onay bekleniyor"
				"emergency_alarm":
					if train.is_stopped() and not route.get_station_at(train.offset).is_empty() and not train.doors.all_closed():
						f["progress"] = "Alarm sıfırlandı"
						_resolve(f, "istasyonda kontrol edildi")
					else:
						f["acked"] = false
						f["progress"] = "Sıfırlama: istasyonda, kapılar açıkken"
				_:
					pass
			return

func _process(delta: float) -> void:
	if GameState.paused or GameState.phase == GameState.Phase.BRIEFING or not enabled:
		return
	_time += delta
	_check_running_triggers()
	for f in active.duplicate():
		f["t"] = float(f["t"]) + delta
		_update_fault(f, delta)

func _check_running_triggers() -> void:
	if mission.state != MissionManager.State.RUNNING:
		return
	var leg := mission.stop_index
	var a: float = float(route.stations[leg]["stop_pos"])
	var b: float = float(route.stations[mini(leg + 1, route.stations.size() - 1)]["stop_pos"])
	var frac := (train.offset - a) / maxf(b - a, 1.0)
	for s in scheduled.duplicate():
		if s["trigger"] == "running" and int(s["leg"]) == leg and frac >= float(s["frac"]):
			scheduled.erase(s)
			_start(s["id"])

func _on_departure_requested(st: Dictionary) -> void:
	pass

func _on_doors_closing(_side: String) -> void:
	# Kapı arızası: kapatma komutu geldiğinde tetiklenir (ilgili istasyonda)
	for s in scheduled.duplicate():
		if s["trigger"] == "station_close" and int(s["station"]) == mission.stop_index and (mission.state == MissionManager.State.BOARDING or mission.state == MissionManager.State.DWELL):
			scheduled.erase(s)
			_start(s["id"])
			return

func _on_doors_closed(_side: String) -> void:
	var f := find_fault("door_fault")
	if not f.is_empty():
		f["attempts"] = int(f["attempts"]) + 1
		if rng.randf() < 0.45:
			_resolve(f, "kapı %d. denemede kapandı" % f["attempts"])
		else:
			f["progress"] = "Kapı kapanmadı (%d deneme). %s" % [f["attempts"], "F ile izole edin" if f["attempts"] >= 2 else "Tekrar deneyin"]
			fault_message.emit("Kapı hâlâ açık — " + str(f["progress"]))

func _on_doors_opened(st: Dictionary, _side: String, _correct: bool) -> void:
	for s in scheduled.duplicate():
		if s["trigger"] == "station_dwell" and int(s["station"]) == int(st.get("index", -1)):
			scheduled.erase(s)
			_start(s["id"])

func _on_arrived(_st: Dictionary, _err: float) -> void:
	pass

func _on_departed(_st: Dictionary) -> void:
	# Tünelde durulmaması gereken alarm: kalkışta hatırlat
	var f := find_fault("emergency_alarm")
	if not f.is_empty():
		f["progress"] = "Sonraki istasyonda durun"

func _update_fault(f: Dictionary, _delta: float) -> void:
	var t: float = f["t"]
	match f["id"]:
		"power_loss":
			if t >= float(f["duration"]):
				if train.is_lever_neutral():
					_resolve(f, "gerilim geldi, çekiş hazır")
				else:
					f["progress"] = "Gerilim geldi — çekiş için kolu NÖTR'e alın"
			else:
				f["progress"] = "Gerilim bekleniyor (%d sn)" % int(float(f["duration"]) - t)
		"mmi_fault":
			if t >= float(f["duration"]):
				_resolve(f, "ekran yeniden başlatıldı")
			elif t >= float(f["duration"]) - 6.0 and _mmi:
				_mmi.blackout = false
				_mmi.flicker = true
		"brake_warning":
			if train.speed_kmh() > 53.0:
				if not f.get("over_flag", false):
					f["over_flag"] = true
					Scoring.add_penalty("fault_ignored", "fren uyarısında 50 km/s aşıldı")
			else:
				f["over_flag"] = false
			if train.is_stopped() and not route.get_station_at(train.offset).is_empty() and train.lever <= -0.9:
				f["test_t"] = float(f.get("test_t", 0.0)) + _delta
				f["progress"] = "Fren testi… %.1f / 3 sn" % float(f["test_t"])
				if float(f["test_t"]) >= 3.0:
					_resolve(f, "fren testi başarılı")
			else:
				f["test_t"] = 0.0
				if f["progress"].begins_with("Fren testi"):
					f["progress"] = ""
		"signal_fault":
			var sg: TrackSignal = f.get("signal")
			if f["acked"] and t - float(f.get("ack_t", 0.0)) >= 8.0 and sg:
				sg.forced_red = false
				sg.forced_yellow = true
				sg.set_aspect("yellow")
				train.temp_speed_restriction_kmh = 25.0
				f["progress"] = "İzin verildi: 25 km/s ile geçin"
				if train.offset > sg.track_pos + 60.0:
					sg.forced_yellow = false
					train.temp_speed_restriction_kmh = 0.0
					_resolve(f, "arızalı sinyal izinle geçildi")
			elif sg and train.offset > sg.track_pos:
				# izinsiz geçildi — SPAD zaten uygulanır
				sg.forced_red = false
				_resolve(f, "sinyal izinsiz geçildi (ihlal)")
		"traction_fault":
			if f["acked"] and t - float(f.get("ack_t", 0.0)) >= 10.0:
				_resolve(f, "çekiş sistemi yeniden başlatıldı")
		"passenger_delay":
			if f["acked"] and t - float(f.get("ack_t", 0.0)) >= 12.0:
				_resolve(f, "merkez onayı alındı, kalkabilirsiniz")
			if train.doors.all_closed() and not f["acked"]:
				if not f.get("closed_flag", false):
					f["closed_flag"] = true
					Scoring.add_penalty("fault_ignored", "yolcu gecikmesinde kapılar erken kapatıldı")
		"emergency_alarm":
			if train.is_stopped() and route.get_station_at(train.offset).is_empty() and mission.state == MissionManager.State.RUNNING and train.speed == 0.0:
				if not f.get("tunnel_stop_flag", false) and t > 5.0:
					f["tunnel_stop_flag"] = true
					Scoring.add_penalty("fault_ignored", "imdat alarmında tünelde duruldu")
