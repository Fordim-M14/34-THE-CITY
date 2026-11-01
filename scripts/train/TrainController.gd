class_name TrainController
extends Node3D
## TrainController — metro dizisinin sürüş fiziği, hat üzerindeki konumu,
## ATP (hız denetimi), sinyal kontrolü, acil fren yönetimi ve olay üretimi.
## Konum "offset" (m, hat başından itibaren, dizinin BURNU) ile tutulur.
##
## ACİL FREN MODELİ (v2):
##   Birden fazla "neden" aynı anda aktif olabilir (MANUAL, ATP, SPAD, FAULT).
##   Tren, nedenlerden en az biri aktifken çekiş uygulayamaz ve acil fren ivmesiyle durur.
##   Sıfırlama (Shift+R) yalnızca: tren durmuş + kol nötr + her nedenin kendi şartı sağlanmışsa.
##     MANUAL : ek şart yok.
##     ATP    : hız ihlali ortadan kalkmış olmalı (duruşta otomatik sağlanır).
##     SPAD   : makinist ihlali onaylamış (F) ve merkezden izin gelmiş olmalı.
##     FAULT  : ilgili arıza giderilmiş olmalı (FaultManager temizler).

signal stopped_at_platform(station: Dictionary, error_m: float)
signal stopped_anywhere()
signal started_moving()
signal signal_passed(sig: TrackSignal)
signal spad(sig: TrackSignal)
signal buffer_hit()
signal atp_intervention()
signal overran_platform(station: Dictionary)
signal emergency_changed(active: bool, reasons: Array)
signal emergency_reset_failed(message: String)
signal emergency_reset_done()
signal spad_permission_granted()
signal headlights_changed(on: bool)
signal cabin_light_changed(on: bool)
signal horn_sounded()

enum EmergencyReason { MANUAL, ATP, SPAD, FAULT }
const REASON_NAMES := {
	EmergencyReason.MANUAL: "MANUEL",
	EmergencyReason.ATP: "ATP (HIZ)",
	EmergencyReason.SPAD: "SİNYAL İHLALİ",
	EmergencyReason.FAULT: "ARIZA",
}

# --- Araç parametreleri (ARS T-400) ---
const CAR_LENGTH := 21.5
const CAR_GAP := 0.6
const TRACTION_MAX := 1.1        # m/s²
const BRAKE_MAX := 1.2           # m/s²  (servis freni)
const EMERGENCY_BRAKE := 1.5     # m/s²
const LEVER_RATE := 1.3          # kol hareket hızı (birim/s)
const ACCEL_TAU := 0.45          # ivme yumuşatma (s)
const MAX_SPEED_MS := 80.0 / 3.6
const HARD_BRAKE_THRESHOLD := 1.12  # m/s² (servis freninin ~%93'ü)
const JERK_THRESHOLD := 2.2         # m/s³
const OVERSPEED_WARN := 3.0         # km/s
const OVERSPEED_ATP := 10.0         # km/s
const NEUTRAL_EPS := 0.05

var world: TrackBuilder
var route: RouteData
var car_count: int = 4

# --- Durum ---
var offset: float = 0.0
var speed: float = 0.0            # m/s (daima >= 0; yön move_dir ile)
var accel: float = 0.0            # gerçekleşen ivme (işaretli)
var lever: float = 0.0            # -1 (tam fren) .. +1 (tam çekiş)
var reverser: int = 1             # 1 ileri, 0 nötr, -1 geri
var move_dir: int = 1             # fiilî hareket yönü
var controls_enabled: bool = false
var distance_travelled: float = 0.0
var atp_warning: bool = false

# Acil fren
var emergency_reasons: Dictionary = {}    # EmergencyReason -> true
var spad_acknowledged: bool = false
var spad_permission: bool = false         # merkezden izin (TrafficManager/MissionManager verir)
var spad_permission_timer: float = -1.0
var fault_emergency_clear: bool = true    # FaultManager false yaparsa FAULT nedeni sıfırlanamaz

# Dış etkiler (arıza, yolcu yükü)
var traction_factor: float = 1.0          # 0..1 (çekiş motoru arızası)
var brake_factor: float = 1.0             # servis fren verimi
var traction_cut: bool = false            # elektrik kesintisi
var load_factor: float = 0.0              # 0 boş .. 1 tam dolu (yolcu)
var headlights_on: bool = true
var cabin_light_on: bool = true
var temp_speed_restriction_kmh: float = 0.0   # 0 = yok (trafik / merkez)

var _prev_offset: float = 0.0
var _was_stopped: bool = true
var _overspeed_timer: float = 0.0
var _hard_brake_flagged: bool = false
var _jerk_cooldown: float = 0.0
var _atp_flagged: bool = false
var _overrun_flagged: Dictionary = {}
var _buffer_done: bool = false

var cars: Array[Node3D] = []
var visual: TrainVisual
var doors: TrainDoors
var camera: Camera3D

func setup(p_world: TrackBuilder, p_route: RouteData, start_offset: float) -> void:
	world = p_world
	route = p_route
	car_count = int(route.raw.get("train_cars", 4))
	offset = start_offset
	_prev_offset = offset
	visual = TrainVisual.new()
	visual.name = "Visual"
	add_child(visual)
	cars = visual.build(car_count, CAR_LENGTH)
	camera = visual.camera
	if camera and "train" in camera:
		camera.train = self
	doors = TrainDoors.new()
	doors.name = "Doors"
	add_child(doors)
	doors.setup(self, visual.door_panels_left, visual.door_panels_right)
	_update_car_transforms()
	visual.set_headlights(headlights_on)
	visual.set_cabin_light(cabin_light_on)

func train_length() -> float:
	return car_count * CAR_LENGTH + (car_count - 1) * CAR_GAP

func speed_kmh() -> float:
	return speed * 3.6

## Geçerli hız limiti: hat limiti ve varsa geçici kısıtlamanın küçüğü.
func current_limit_kmh() -> float:
	var l := route.get_speed_limit_kmh(offset)
	if temp_speed_restriction_kmh > 0.0:
		l = minf(l, temp_speed_restriction_kmh)
	return l

func is_stopped() -> bool:
	return speed == 0.0

func is_lever_neutral() -> bool:
	return absf(lever) < NEUTRAL_EPS

# ---------------------------------------------------------------------------
# Acil fren

func emergency_active() -> bool:
	return not emergency_reasons.is_empty()

func has_reason(r: int) -> bool:
	return emergency_reasons.has(r)

func active_reason_names() -> Array:
	var out := []
	for r in emergency_reasons:
		out.append(REASON_NAMES[r])
	return out

func trigger_emergency(reason: int, note: String = "") -> void:
	var was_active := emergency_active()
	if emergency_reasons.has(reason):
		return
	emergency_reasons[reason] = true
	match reason:
		EmergencyReason.MANUAL:
			Scoring.add_penalty("emergency_used")
			Scoring.stats["emergency_count"] = int(Scoring.stats["emergency_count"]) + 1
		EmergencyReason.ATP:
			Scoring.add_penalty("overspeed_atp", "%d km/s @ limit %d" % [int(speed_kmh()), int(current_limit_kmh())])
			atp_intervention.emit()
		EmergencyReason.SPAD:
			spad_acknowledged = false
			spad_permission = false
			spad_permission_timer = -1.0
		EmergencyReason.FAULT:
			fault_emergency_clear = false
			Scoring.log_event("Arıza kaynaklı acil fren" + (" — " + note if note != "" else ""))
	if not was_active:
		emergency_changed.emit(true, active_reason_names())

## Sıfırlama şartlarını kontrol eder. {"ok": bool, "message": String}
func can_reset_emergency() -> Dictionary:
	if not emergency_active():
		return {"ok": false, "message": "Acil fren devrede değil"}
	if not is_stopped():
		return {"ok": false, "message": "Sıfırlama için tren tamamen durmalı"}
	if not is_lever_neutral():
		return {"ok": false, "message": "Sıfırlama için kolu NÖTR konuma alın (N)"}
	if has_reason(EmergencyReason.ATP) and speed_kmh() > current_limit_kmh():
		return {"ok": false, "message": "ATP: hız ihlali sürüyor"}
	if has_reason(EmergencyReason.SPAD):
		if not spad_acknowledged:
			return {"ok": false, "message": "Sinyal ihlalini onaylayın (F) — merkez bilgilendirilecek"}
		if not spad_permission:
			return {"ok": false, "message": "Merkezden hareket izni bekleniyor…"}
	if has_reason(EmergencyReason.FAULT) and not fault_emergency_clear:
		return {"ok": false, "message": "Arıza giderilmeden acil fren sıfırlanamaz (MMI'ya bakın)"}
	return {"ok": true, "message": "Acil fren sıfırlanabilir"}

func reset_emergency() -> bool:
	var chk := can_reset_emergency()
	if not chk["ok"]:
		emergency_reset_failed.emit(chk["message"])
		Scoring.log_event("Acil fren sıfırlanamadı: %s" % chk["message"])
		return false
	emergency_reasons.clear()
	_atp_flagged = false
	spad_acknowledged = false
	spad_permission = false
	Scoring.log_event("Acil fren sıfırlandı (Shift+R)")
	emergency_changed.emit(false, [])
	emergency_reset_done.emit()
	return true

func acknowledge() -> void:
	if has_reason(EmergencyReason.SPAD) and not spad_acknowledged:
		spad_acknowledged = true
		# Merkez, onaydan belirli süre sonra hareket izni verir (TrafficManager kısaltabilir)
		spad_permission_timer = 12.0
		Scoring.log_event("Sinyal ihlali onaylandı — merkez bilgilendirildi, izin bekleniyor")

func grant_spad_permission() -> void:
	if has_reason(EmergencyReason.SPAD):
		spad_permission = true
		spad_permission_timer = -1.0
		Scoring.log_event("Merkez: hareket izni verildi — Shift+R ile acil freni sıfırlayın")
		spad_permission_granted.emit()

## FaultManager, arıza giderildiğinde çağırır.
func clear_fault_emergency() -> void:
	fault_emergency_clear = true

# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if controls_enabled:
		_read_input(delta)
	if spad_permission_timer > 0.0:
		spad_permission_timer -= delta
		if spad_permission_timer <= 0.0:
			grant_spad_permission()
	_integrate(delta)
	_check_atp(delta)
	_check_signals()
	_check_platform_events()
	_update_car_transforms()
	visual.update_lever_visual(lever, emergency_active(), reverser)
	visual.update_speedo(speed_kmh())
	_prev_offset = offset

func _read_input(delta: float) -> void:
	if Settings.control_mode == 1:
		_read_input_easy(delta)
	else:
		if Input.is_action_pressed("throttle_up"):
			lever = minf(lever + LEVER_RATE * delta, 1.0)
		if Input.is_action_pressed("throttle_down"):
			lever = maxf(lever - LEVER_RATE * delta, -1.0)
	if Input.is_action_just_pressed("lever_neutral"):
		lever = 0.0
	if Input.is_action_just_pressed("emergency_brake"):
		trigger_emergency(EmergencyReason.MANUAL)
	if Input.is_action_just_pressed("emergency_reset"):
		reset_emergency()
	elif Input.is_action_just_pressed("reverser", true):
		cycle_reverser()
	if Input.is_action_just_pressed("acknowledge"):
		acknowledge()
	if Settings.control_mode == 1:
		# Kolay mod: Q/E her ikisi de peron tarafındaki kapıları açar/kapatır
		if Input.is_action_just_pressed("doors_left") or Input.is_action_just_pressed("doors_right"):
			var st := route.get_station_at(offset)
			doors.toggle(str(st.get("door_side", "right")) if not st.is_empty() else "right")
	else:
		if Input.is_action_just_pressed("doors_left"):
			doors.toggle("left")
		if Input.is_action_just_pressed("doors_right"):
			doors.toggle("right")
	if Input.is_action_just_pressed("headlights"):
		toggle_headlights()
	if Input.is_action_just_pressed("cabin_light"):
		toggle_cabin_light()
	if Input.is_action_just_pressed("horn"):
		horn()

## Kolay kontrol modu: W basılı → çekiş (yumuşak), S basılı → fren, ikisi de yoksa kol nötr;
## hız limiti otomatik korunur (limit −2 km/s üstünde çekiş kesilir, +1 üstünde hafif fren).
func _read_input_easy(delta: float) -> void:
	var target := 0.0
	if Input.is_action_pressed("throttle_up"):
		target = 0.75
	if Input.is_action_pressed("throttle_down"):
		target = -0.8
	# İzin verilen hız: mevcut limit ve ileriki limit düşüşü için fren mesafesi (0,9 m/s²)
	var allowed := current_limit_kmh()
	var up := route.get_upcoming_limit(offset, 450.0)
	if not up.is_empty():
		var lim2 := float(up["limit_kmh"]) / 3.6
		var d := maxf(float(up["distance"]), 0.0)
		allowed = minf(allowed, sqrt(lim2 * lim2 + 2.0 * 0.9 * d) * 3.6)
	var v := speed_kmh()
	if target > 0.0 and v > allowed - 2.0:
		target = 0.0
	if target >= 0.0 and v > allowed + 0.5:
		target = -clampf(0.3 + (v - allowed) * 0.08, 0.3, 0.9)
	if reverser == 0 and target > 0.0:
		reverser = 1
	lever = move_toward(lever, target, LEVER_RATE * 2.0 * delta)

func horn() -> void:
	horn_sounded.emit()

func toggle_headlights() -> void:
	headlights_on = not headlights_on
	visual.set_headlights(headlights_on)
	headlights_changed.emit(headlights_on)
	Scoring.log_event("Farlar %s" % ("AÇIK" if headlights_on else "KAPALI"))

func toggle_cabin_light() -> void:
	cabin_light_on = not cabin_light_on
	visual.set_cabin_light(cabin_light_on)
	cabin_light_changed.emit(cabin_light_on)

func set_lever(v: float) -> void:
	lever = clampf(v, -1.0, 1.0)

func cycle_reverser() -> void:
	if speed > 0.05:
		Scoring.log_event("Yön kolu sadece duruşta değiştirilebilir")
		return
	if lever > 0.05:
		Scoring.log_event("Yön değiştirmek için kolu nötr/frene alın")
		return
	reverser = 0 if reverser == 1 else (-1 if reverser == 0 else 1)
	var names := {1: "İLERİ", 0: "NÖTR", -1: "GERİ"}
	Scoring.log_event("Yön kolu: %s" % names[reverser])

func set_reverser(v: int) -> void:
	if speed > 0.05 or lever > 0.05:
		cycle_reverser()   # aynı uyarı mesajlarını üretir
		return
	reverser = clampi(v, -1, 1)

func _integrate(delta: float) -> void:
	var cmd := 0.0
	var emergency := emergency_active()
	if emergency:
		cmd = -EMERGENCY_BRAKE
	else:
		if lever > 0.0:
			if reverser != 0 and doors.all_closed() and not traction_cut:
				var v_factor := 1.0
				if speed > 10.0:
					v_factor = 10.0 / speed      # sabit güç bölgesi
				var mass_factor := 1.0 / (1.0 + 0.25 * load_factor)
				cmd = TRACTION_MAX * lever * v_factor * traction_factor * mass_factor
		elif lever < 0.0:
			cmd = BRAKE_MAX * lever * brake_factor
	var resistance := 0.0
	if speed > 0.0:
		resistance = 0.03 + 0.00045 * speed * speed
	var target_accel := cmd - resistance
	var alpha := clampf(delta / ACCEL_TAU, 0.0, 1.0)
	var prev_accel := accel
	accel = lerpf(accel, target_accel, alpha)
	var new_speed := speed + accel * delta
	if new_speed <= 0.0:
		new_speed = 0.0
		if accel < 0.0 and speed <= 0.0:
			accel = 0.0
	speed = minf(new_speed, MAX_SPEED_MS)
	if speed <= 0.02 and (cmd <= 0.0 or reverser == 0):
		speed = 0.0
	if reverser != 0 and speed == 0.0:
		move_dir = reverser
	var ds := speed * delta * float(move_dir)
	offset += ds
	distance_travelled += absf(ds)
	offset = clampf(offset, 0.0, route.buffer_end)
	if offset >= route.buffer_end - 0.01 and speed > 0.2 and not _buffer_done:
		_buffer_done = true
		Scoring.add_penalty("buffer_hit", "%d km/s" % int(speed_kmh()))
		speed = 0.0
		accel = 0.0
		buffer_hit.emit()
	Scoring.stats["max_speed_kmh"] = maxf(float(Scoring.stats["max_speed_kmh"]), speed_kmh())
	if speed > 0.1:
		Scoring.stats["moving_seconds"] = float(Scoring.stats.get("moving_seconds", 0.0)) + delta
	# Konfor: sert fren
	if accel < -HARD_BRAKE_THRESHOLD and speed > 1.5 and not emergency:
		if not _hard_brake_flagged:
			_hard_brake_flagged = true
			Scoring.stats["hard_brakes"] = int(Scoring.stats["hard_brakes"]) + 1
			Scoring.add_penalty("hard_brake", "%.2f m/s²" % absf(accel))
	elif accel > -0.6:
		_hard_brake_flagged = false
	# Konfor: sarsıntı
	_jerk_cooldown = maxf(0.0, _jerk_cooldown - delta)
	if delta > 0.0 and speed > 0.5:
		var jerk := absf(accel - prev_accel) / delta
		if jerk > JERK_THRESHOLD and _jerk_cooldown <= 0.0 and not emergency:
			_jerk_cooldown = 4.0
			Scoring.add_penalty("jerk")
	if _was_stopped and speed > 0.3:
		_was_stopped = false
		started_moving.emit()
	elif not _was_stopped and speed == 0.0:
		_was_stopped = true
		_on_stopped()

func _check_atp(delta: float) -> void:
	var limit := current_limit_kmh()
	var v := speed_kmh()
	atp_warning = v > limit + OVERSPEED_WARN
	if atp_warning:
		_overspeed_timer += delta
		Scoring.stats["overspeed_seconds"] = float(Scoring.stats["overspeed_seconds"]) + delta
		if _overspeed_timer >= 3.0:
			_overspeed_timer = 0.0
			Scoring.add_penalty("overspeed", "%d km/s @ limit %d" % [int(v), int(limit)])
		if v > limit + OVERSPEED_ATP and not _atp_flagged:
			_atp_flagged = true
			trigger_emergency(EmergencyReason.ATP)
	else:
		_overspeed_timer = 0.0

func _check_signals() -> void:
	if offset == _prev_offset:
		return
	var lo := minf(_prev_offset, offset)
	var hi := maxf(_prev_offset, offset)
	for id in world.signals_by_id:
		var sig: TrackSignal = world.signals_by_id[id]
		if sig.track_pos > lo and sig.track_pos <= hi and move_dir > 0:
			signal_passed.emit(sig)
			if sig.is_red():
				Scoring.stats["spad_count"] = int(Scoring.stats["spad_count"]) + 1
				Scoring.add_penalty("spad", sig.signal_id)
				trigger_emergency(EmergencyReason.SPAD)
				spad.emit(sig)

func _check_platform_events() -> void:
	var nxt := route.get_next_station(_prev_offset)
	if nxt.is_empty():
		return
	var pend: float = float(nxt["platform_end"])
	var sid: String = str(nxt["id"])
	if _prev_offset <= pend and offset > pend and not _overrun_flagged.get(sid, false) and not nxt.get("is_start", false):
		_overrun_flagged[sid] = true
		Scoring.add_penalty("overrun", str(nxt["name"]))
		overran_platform.emit(nxt)

func _on_stopped() -> void:
	stopped_anywhere.emit()
	var st := route.get_station_at(offset)
	if st.is_empty():
		return
	var err: float = offset - float(st["stop_pos"])
	stopped_at_platform.emit(st, err)

func stop_error_at(st: Dictionary) -> float:
	return offset - float(st["stop_pos"])

func _update_car_transforms() -> void:
	var half := CAR_LENGTH * 0.5
	for i in cars.size():
		var center_off: float = offset - (half + i * (CAR_LENGTH + CAR_GAP))
		cars[i].global_transform = world.get_track_transform(center_off)

## Hat üzerindeki yerel konumdan dünya konumu (yolcular, kameralar için).
func door_world_positions(side: String) -> Array[Vector3]:
	return visual.door_world_positions(side)
