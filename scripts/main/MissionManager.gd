class_name MissionManager
extends Node
## MissionManager — çok duraklı sefer akışı:
##   BRIEFING → BOARDING(i) → READY(i) → RUNNING(i→i+1) → ARRIVED(i+1) → DWELL(i+1) → …
##   Son istasyonda kapılar kapanınca FINISHED.
## Her istasyonda duruş hassasiyeti ve tarife değerlendirilir; yolcu/arıza/trafik sistemleri
## bu sınıfın sinyallerine abone olur.

signal state_changed(state: int)
signal arrived_at_station(station: Dictionary, err_m: float)
signal doors_opened_at_station(station: Dictionary, side: String, correct: bool)
signal dwell_finished(station: Dictionary)
signal departed_station(station: Dictionary)
signal departure_requested(station: Dictionary)      # kapılar kapandı, izin bekleniyor
signal departure_cleared(station: Dictionary)        # kalkış izni verildi (sinyal yeşil)
signal mission_finished(failed_reason: String)
signal hint_changed(text: String)
signal station_skipped(station: Dictionary)

enum State { BRIEFING, BOARDING, READY, RUNNING, ARRIVED, DWELL, FINISHED }

var train: TrainController
var route: RouteData
var world: TrackBuilder
var state: int = State.BRIEFING
var stop_index: int = 0                   # bulunulan / son ayrılınan istasyon dizini
var dwell_timer: float = -1.0
var dwell_required: float = 0.0           # yolcu sayısına göre uzatılabilir
var departure_timer: float = -1.0
var departure_hold: float = 0.0           # merkez regülasyonu (TrafficManager)
var failed_reason: String = ""
var arrival_err: float = 0.0
var hint: String = ""
var _doors_open_station_id: String = ""
var extra_dwell_from_passengers: float = 0.0   # PassengerManager günceller

func setup(p_train: TrainController, p_route: RouteData, p_world: TrackBuilder) -> void:
	train = p_train
	route = p_route
	world = p_world
	train.started_moving.connect(_on_started_moving)
	train.stopped_at_platform.connect(_on_stopped_at_platform)
	train.overran_platform.connect(_on_overran)
	train.buffer_hit.connect(_on_buffer_hit)
	train.doors.doors_opened.connect(_on_doors_opened)
	train.doors.doors_closed.connect(_on_doors_closed)
	train.emergency_reset_done.connect(func() -> void: _set_hint(""))
	train.emergency_reset_failed.connect(func(msg: String) -> void: _set_hint(msg))
	train.doors.door_command_rejected.connect(func(reason: String) -> void: _set_hint(reason))

func current_station() -> Dictionary:
	return route.stations[stop_index]

func next_station() -> Dictionary:
	if stop_index + 1 < route.stations.size():
		return route.stations[stop_index + 1]
	return {}

## HUD için: hedef istasyon (durulacak olan)
func target_station() -> Dictionary:
	match state:
		State.BOARDING, State.READY, State.ARRIVED, State.DWELL:
			return current_station()
		State.RUNNING:
			return next_station()
	return next_station() if not next_station().is_empty() else current_station()

func planned_arrival_s(st: Dictionary) -> float:
	return route.schedule_for(int(st.get("index", 0)))

func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
	match s:
		State.BOARDING, State.READY: GameState.set_phase(GameState.Phase.PREPARING)
		State.RUNNING: GameState.set_phase(GameState.Phase.DRIVING)
		State.ARRIVED, State.DWELL: GameState.set_phase(GameState.Phase.ARRIVED)
		State.FINISHED: GameState.set_phase(GameState.Phase.FINISHED)

func _set_hint(t: String) -> void:
	hint = t
	hint_changed.emit(t)

func begin() -> void:
	stop_index = 0
	var st := current_station()
	train.doors.force_open(str(st.get("door_side", "right")))
	_doors_open_station_id = str(st["id"])
	train.controls_enabled = true
	_set_state(State.BOARDING)
	_set_hint("%s — yolcu alımı. Hazır olunca kapıları kapatın (%s)" % [str(st["name"]), _door_key(st)])

func _door_key(st: Dictionary) -> String:
	return "E" if str(st.get("door_side", "right")) == "right" else "Q"

func _process(delta: float) -> void:
	if GameState.paused:
		return
	if departure_timer > 0.0:
		departure_timer -= delta
		if departure_timer <= 0.0:
			departure_timer = -1.0
			_clear_departure()
	if dwell_timer > 0.0:
		dwell_timer -= delta
		if dwell_timer <= 0.0:
			dwell_timer = -1.0
			_on_dwell_finished()
	# Kapılar açıkken hareket
	if (state == State.DWELL or state == State.ARRIVED or state == State.BOARDING) and train.speed > 0.5 and not train.doors.all_closed():
		if not _moved_doors_open_flagged:
			_moved_doors_open_flagged = true
			Scoring.add_penalty("moved_doors_open")
	elif train.speed < 0.1:
		_moved_doors_open_flagged = false
	# Farsız sürüş (tünelde)
	if _no_headlight_timer < 0.0:
		_no_headlight_timer = minf(_no_headlight_timer + delta, 0.0)   # ceza sonrası bekleme
	elif state == State.RUNNING and not train.headlights_on and train.speed > 5.0 and route.get_segment_type(train.offset) == "tunnel":
		_no_headlight_timer += delta
		if _no_headlight_timer > 10.0:
			_no_headlight_timer = -30.0
			Scoring.add_penalty("no_headlights")
	else:
		_no_headlight_timer = 0.0
	Scoring.stats["distance_m"] = train.distance_travelled

var _moved_doors_open_flagged := false
var _no_headlight_timer := 0.0

# --- Kapılar -----------------------------------------------------------------

func _on_doors_closed(_side: String) -> void:
	if not train.doors.all_closed():
		return
	match state:
		State.BOARDING:
			_request_departure()
		State.DWELL:
			if dwell_timer > 0.0:
				# Erken kapatma
				Scoring.add_penalty("early_door_close", str(current_station()["name"]))
				dwell_timer = -1.0
			if current_station().get("is_end", false):
				_finish("")
			else:
				_request_departure()
		State.ARRIVED:
			# Kapılar hiç açılmadan tekrar kapandı (yanlış taraf açılıp kapatıldı vb.)
			pass

func _request_departure() -> void:
	_set_state(State.READY)
	departure_requested.emit(current_station())
	var hold := maxf(2.0, departure_hold)
	departure_hold = 0.0
	departure_timer = hold
	_set_hint("Kapılar kapalı — kalkış izni bekleniyor…")

func _clear_departure() -> void:
	GameState.departure_cleared = true
	_set_hint("Kalkış izni verildi — sinyale bakın, kolu ileri alın (W)")
	departure_cleared.emit(current_station())

func _on_started_moving() -> void:
	match state:
		State.READY:
			var st := current_station()
			_set_state(State.RUNNING)
			departed_station.emit(st)
			var nxt := next_station()
			_set_hint("")
			Scoring.log_event("%s istasyonundan kalkış → %s" % [str(st["name"]), str(nxt.get("name", "?"))])
		State.BOARDING:
			Scoring.log_event("Kapılar açıkken hareket!")
		State.DWELL, State.ARRIVED:
			if not train.doors.all_closed():
				Scoring.log_event("Varışta kapılar açıkken hareket!")

func _on_stopped_at_platform(st: Dictionary, err: float) -> void:
	if state != State.RUNNING:
		return
	var nxt := next_station()
	if nxt.is_empty() or str(st["id"]) != str(nxt["id"]):
		return
	arrival_err = err
	GameState.departure_cleared = false
	_set_state(State.ARRIVED)
	stop_index += 1
	arrived_at_station.emit(st, err)
	var key := _door_key(st)
	if absf(err) <= 0.5:
		_set_hint("Mükemmel duruş (%+.2f m) — kapıları açın (%s)" % [err, key])
	elif absf(err) <= 1.5:
		_set_hint("Duruş sapması %+.2f m — kabul edilebilir. Kapıları açın (%s)" % [err, key])
	elif absf(err) <= 3.0:
		_set_hint("Duruş sapması %+.2f m — düzeltin ya da kapıları açın (ceza)" % err)
	else:
		_set_hint("Duruş noktasından %.1f m uzaktasınız — düzeltin (R: yön)" % absf(err))

func _on_doors_opened(side: String, st: Dictionary, correct: bool) -> void:
	if state != State.ARRIVED:
		# Varış dışı açılış (yeniden açma vb.)
		doors_opened_at_station.emit(st, side, correct)
		return
	if str(st["id"]) != str(current_station()["id"]):
		return
	var err := train.stop_error_at(st)
	var a := absf(err)
	if a > 3.0:
		Scoring.add_penalty("stop_fail", "%s %+.2f m" % [str(st["name"]), err])
	elif a > 1.5:
		Scoring.add_penalty("stop_major", "%s %+.2f m" % [str(st["name"]), err])
	elif a > 0.5:
		Scoring.add_penalty("stop_minor", "%s %+.2f m" % [str(st["name"]), err])
	else:
		Scoring.log_event("%s: duruş hassasiyeti %+.2f m — mükemmel" % [str(st["name"]), err])
	var delta := 0.0
	if not GameState.is_free_mode():
		delta = GameState.mission_time - planned_arrival_s(st)
		Scoring.record_arrival(st, err, delta, route.schedule_tolerance)
	else:
		(Scoring.stats["stops"] as Array).append({"id": str(st["id"]), "name": str(st["name"]), "err": err, "delta": 0.0})
		Scoring.stats["stations_served"] = int(Scoring.stats["stations_served"]) + 1
	Scoring.stats["stop_error_m"] = err
	_set_state(State.DWELL)
	dwell_required = route.dwell_seconds + extra_dwell_from_passengers
	dwell_timer = dwell_required
	doors_opened_at_station.emit(st, side, correct)
	if not correct:
		_set_hint("Kapılar YANLIŞ tarafta açıldı! Kapatıp doğru tarafı (%s) açın" % _door_key(st))
	else:
		_set_hint("%s — yolcu iniş/binişi (%d sn)…" % [str(st["name"]), int(dwell_required)])

func _on_dwell_finished() -> void:
	var st := current_station()
	dwell_finished.emit(st)
	if st.get("is_end", false):
		_set_hint("Son istasyon %s — kapıları kapatın (%s), sefer tamamlanacak" % [str(st["name"]), _door_key(st)])
	else:
		_set_hint("Yolcu alımı tamamlandı — kapıları kapatın (%s)" % _door_key(st))

func _on_overran(st: Dictionary) -> void:
	# Peron sonu geçildi; 120 m sonra istasyon atlandı sayılır
	var nxt := next_station()
	if nxt.is_empty() or str(st["id"]) != str(nxt["id"]):
		return
	_set_hint("Peron geçildi! Durup geri manevra yapın (R: GERİ)")
	_overrun_station = st

var _overrun_station: Dictionary = {}

func _physics_process(_delta: float) -> void:
	if not _overrun_station.is_empty() and state == State.RUNNING:
		if train.offset > float(_overrun_station["platform_end"]) + 120.0:
			var st: Dictionary = _overrun_station
			_overrun_station = {}
			if not GameState.is_free_mode():
				Scoring.add_penalty("station_skipped", str(st["name"]))
			station_skipped.emit(st)
			stop_index += 1
			if current_station().get("is_end", false) and not GameState.is_free_mode():
				_finish("Son istasyon durulmadan geçildi")
			else:
				_set_hint("İstasyon atlandı — sonraki: %s" % str(next_station().get("name", "")))
		elif train.offset <= float(_overrun_station["platform_end"]):
			_overrun_station = {}

func _on_buffer_hit() -> void:
	_finish("Tampona çarpma")

## Serbest sürüş: oyuncu istediği zaman seferi bitirir (ceza/kariyer etkisi yok)
func end_free_drive() -> void:
	if GameState.is_free_mode():
		_finish("")

func _finish(reason: String) -> void:
	if state == State.FINISHED:
		return
	failed_reason = reason
	train.controls_enabled = false
	_set_state(State.FINISHED)
	Scoring.stats["mission_time"] = GameState.mission_time
	Scoring.log_event("Sefer tamamlandı — puan %d (%s)" % [Scoring.total_score(), Scoring.grade()])
	_set_hint("")
	mission_finished.emit(reason)
