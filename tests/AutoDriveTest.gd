extends Node
## AutoDriveTest v2 — headless tam hat entegrasyon testi.
## Otopilot: tüm istasyonlarda durur, kapıları doğru tarafta açar/kapatır, sinyallere
## (öndeki tren trafiği dahil) uyar, arızaları prosedürle çözer. Sonunda rapor basar.
##   godot --headless --path . res://tests/AutoDriveTest.tscn [--seed N] [--reverse]
## Çıkış kodu: 0 başarı (tüm istasyonlar servis edildi, puan >= 60), 1 hata.

const TARGET_MARGIN_KMH := 3.0
const SERVICE_DECEL := 0.75
const TIME_SCALE := 12.0

var main: Node
var train: TrainController
var route: RouteData
var mission: MissionManager
var traffic: TrafficManager
var faults: FaultManager
var world: TrackBuilder
var t := 0.0
var _finished := false
var _opened_at := ""
var _brake_test_hold := 0.0
var _ack_cool := 0.0

func _ready() -> void:
	GameState.auto_test_mode = true
	var args := OS.get_cmdline_user_args()
	var m := GameState.default_mission()
	m["seed"] = 12345
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			m["seed"] = int(args[i + 1])
		if args[i] == "--reverse":
			m["direction"] = "reverse"
		if args[i] == "--no-faults":
			m["faults_enabled"] = false
	GameState.apply_mission(m)
	Engine.time_scale = TIME_SCALE
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	route = GameState.route
	mission = main.get_node("Mission")
	traffic = main.get_node("Traffic")
	faults = main.get_node("Faults")
	world = main.get_node("World")
	print("[TEST] Yön: %s, hat uzunluğu %.1f m, %d istasyon, tohum %d" % [route.direction, route.track_length, route.stations.size(), int(m["seed"])])
	print("[TEST] Sinyaller: %d, planlanan arıza: %s" % [route.signals.size(), str(faults.scheduled)])
	GameState.phase_changed.connect(func(p: int) -> void: print("[TEST] %.0fs Faz -> %s" % [t, GameState.Phase.keys()[p]]))
	mission.state_changed.connect(func(s: int) -> void: print("[TEST] %.0fs Görev -> %s (durak %d)" % [t, MissionManager.State.keys()[s], mission.stop_index]))
	Scoring.penalty_added.connect(func(code: String, pts: int, text: String) -> void: print("[TEST] %.0fs   CEZA %s (-%d): %s" % [t, code, pts, text]))
	faults.fault_started.connect(func(f: Dictionary) -> void: print("[TEST] %.0fs   ARIZA BAŞLADI: %s" % [t, f["title"]]))
	faults.fault_resolved.connect(func(f: Dictionary) -> void: print("[TEST] %.0fs   ARIZA GİDERİLDİ: %s" % [t, f["title"]]))
	traffic.message.connect(func(txt: String, _ack: bool) -> void: print("[TEST] %.0fs   MERKEZ: %s" % [t, txt]))

func _physics_process(delta: float) -> void:
	t += delta
	if _finished:
		return
	_ack_cool = maxf(0.0, _ack_cool - delta)
	if t > 2400.0:
		print("[TEST] ZAMAN AŞIMI — görev %s, durak %d, offset %.1f, hız %.1f, acil %s" % [MissionManager.State.keys()[mission.state], mission.stop_index, train.offset, train.speed_kmh(), str(train.active_reason_names())])
		_quit(1)
		return
	match GameState.phase:
		GameState.Phase.BRIEFING:
			if t > 0.5:
				main.get_node("MissionBrief").visible = false
				main.get_node("MissionBrief").accepted.emit()
		_:
			_step(delta)

func _step(delta: float) -> void:
	var st := mission.current_station()
	var side := str(st.get("door_side", "right"))
	_handle_emergency()
	_handle_faults(delta)
	match mission.state:
		MissionManager.State.BOARDING:
			if train.doors.state[side] == TrainDoors.State.OPEN and not faults.has_fault("door_fault"):
				train.doors.request_close(side)
		MissionManager.State.READY:
			train.lever = 0.0 if not _brake_testing() else -1.0
			if GameState.departure_cleared and train.doors.all_closed() and not train.emergency_active() and not _brake_testing():
				_drive(delta)
		MissionManager.State.RUNNING:
			_drive(delta)
		MissionManager.State.ARRIVED:
			train.lever = -0.5
			if train.is_stopped() and _opened_at != str(st["id"]):
				_opened_at = str(st["id"])
				train.doors.request_open(side)
		MissionManager.State.DWELL:
			train.lever = -0.5 if not _brake_testing() else -1.0
			if mission.dwell_timer <= 0.0 and train.doors.state[side] == TrainDoors.State.OPEN and not _blocking_fault():
				train.doors.request_close(side)
		MissionManager.State.FINISHED:
			_finished = true
			_report()

func _brake_testing() -> bool:
	return faults.has_fault("brake_warning") and train.is_stopped() and not route.get_station_at(train.offset).is_empty()

func _blocking_fault() -> bool:
	# Kapıları kapatmadan önce çözülmesi gereken arızalar
	if faults.has_fault("passenger_delay"):
		return true
	if faults.has_fault("emergency_alarm"):
		return true
	if faults.has_fault("traction_fault"):
		return true
	if faults.has_fault("brake_warning"):
		return true
	return false

func _handle_emergency() -> void:
	if not train.emergency_active():
		return
	train.lever = 0.0
	if train.has_reason(TrainController.EmergencyReason.SPAD) and not train.spad_acknowledged and train.is_stopped():
		train.acknowledge()
	if train.can_reset_emergency()["ok"]:
		train.reset_emergency()

func _handle_faults(delta: float) -> void:
	for f in faults.active_faults():
		match f["id"]:
			"door_fault":
				var side := str(f["side"])
				if train.doors.state[side] == TrainDoors.State.OPEN:
					if int(f["attempts"]) >= 2:
						if _ack_cool <= 0.0:
							faults.acknowledge()
							_ack_cool = 2.0
					elif _ack_cool <= 0.0:
						train.doors.request_close(side)
						_ack_cool = 3.0
			"power_loss":
				pass   # _drive kolu nötrde tutar
			"signal_fault":
				pass   # _drive sinyal önünde durur; duruşta ack
			"traction_fault", "passenger_delay", "emergency_alarm":
				if not f["acked"] and _ack_cool <= 0.0 and train.is_stopped():
					faults.acknowledge()
					_ack_cool = 2.0
			"brake_warning":
				pass
	# Sinyal arızası: sinyal önünde durunca onayla
	var sf := faults.find_fault("signal_fault")
	if not sf.is_empty() and not sf["acked"] and train.is_stopped() and _ack_cool <= 0.0:
		faults.acknowledge()
		_ack_cool = 2.0

func _drive(delta: float) -> void:
	if train.traction_cut:
		train.lever = move_toward(train.lever, 0.0, 1.0 * delta)
		return
	var v := train.speed
	var pos := train.offset
	var tgt_st := mission.next_station()
	var stop_pos: float = float(tgt_st["stop_pos"]) if not tgt_st.is_empty() else route.buffer_end - 20.0
	var d_stop := stop_pos - pos
	var limit_kmh := train.current_limit_kmh()
	if faults.has_fault("brake_warning"):
		limit_kmh = minf(limit_kmh, 48.0)
	var target := (limit_kmh - TARGET_MARGIN_KMH) / 3.6
	for sl in route.speed_limits:
		var from_pos: float = float(sl["from"])
		if from_pos > pos:
			var lim := (float(sl["limit_kmh"]) - TARGET_MARGIN_KMH) / 3.6
			if faults.has_fault("brake_warning"):
				lim = minf(lim, 45.0 / 3.6)
			var allowed := sqrt(maxf(lim * lim + 2.0 * SERVICE_DECEL * (from_pos - pos), 0.0))
			target = minf(target, allowed)
	# TSR
	if not traffic.tsr.is_empty():
		var tf: float = float(traffic.tsr["from"]) - train.train_length()
		if tf > pos:
			var lim := (float(traffic.tsr["limit"]) - TARGET_MARGIN_KMH) / 3.6
			target = minf(target, sqrt(maxf(lim * lim + 2.0 * SERVICE_DECEL * (tf - pos), 0.0)))
	# Sinyaller: kırmızı ise 15 m önünde dur; sarı ise 40 km/s
	var sg := route.get_next_signal(pos)
	if not sg.is_empty():
		var sig: TrackSignal = world.signals_by_id[str(sg["id"])]
		var d_sig := sig.track_pos - pos
		if sig.aspect == "red":
			var d := d_sig - 15.0
			target = minf(target, sqrt(2.0 * SERVICE_DECEL * maxf(d, 0.0)))
			if d < 12.0:
				target = minf(target, maxf(d * 0.3, 0.0))
			if d < 0.6:
				target = 0.0
		elif sig.aspect == "yellow":
			target = minf(target, 40.0 / 3.6)
			if sig.forced_yellow:
				target = minf(target, 22.0 / 3.6)
	# Duruş noktası
	if d_stop > 0.0:
		target = minf(target, sqrt(2.0 * SERVICE_DECEL * d_stop))
		if d_stop < 20.0:
			target = minf(target, maxf(d_stop * 0.3, 0.5))
		if d_stop < 0.4:
			target = 0.0
	else:
		target = 0.0
	var err := target - v
	var desired := clampf(err * 0.7, -0.85, 1.0)
	if target <= 0.0 and v < 0.3:
		desired = -0.8
	train.lever = move_toward(train.lever, desired, 0.8 * delta)

func _report() -> void:
	print("")
	print("========== SEFER RAPORU (%s) ==========" % route.direction)
	print("Puan: %d / 100  (%s)%s" % [Scoring.total_score(), Scoring.grade(), ("  BAŞARISIZ: " + mission.failed_reason) if mission.failed_reason != "" else ""])
	for line in Scoring.summary_lines():
		print("  " + line)
	print("Süre: %.1f s · mesafe %.0f m · azami %.1f km/s · hız aşımı %.1f s" % [GameState.mission_time, float(Scoring.stats["distance_m"]), float(Scoring.stats["max_speed_kmh"]), float(Scoring.stats["overspeed_seconds"])])
	print("İstasyonlar:")
	for sp in Scoring.stats["stops"]:
		print("  %-26s duruş %+.2f m   tarife %+d sn" % [str(sp["name"]), float(sp["err"]), int(sp["delta"])])
	print("Yolcu: bindi %d, indi %d · Arıza %d / %d" % [int(Scoring.stats["passengers_boarded"]), int(Scoring.stats["passengers_alighted"]), int(Scoring.stats["faults_resolved"]), int(Scoring.stats["faults"])])
	print("Cezalar (%d):" % Scoring.penalties.size())
	for p in Scoring.penalties:
		print("  -%d  %s" % [int(p["points"]), str(p["text"])])
	print("=============================================")
	var served: int = int(Scoring.stats["stations_served"])
	var ok := mission.failed_reason == "" and served == route.stations.size() - 1 and Scoring.total_score() >= 60
	print("[TEST] %s (servis edilen istasyon %d/%d)" % ["BAŞARILI" if ok else "BAŞARISIZ", served, route.stations.size() - 1])
	_quit(0 if ok else 1)

func _quit(code: int) -> void:
	_finished = true
	get_tree().quit(code)
