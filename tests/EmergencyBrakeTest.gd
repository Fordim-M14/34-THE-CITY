extends Node
## EmergencyBrakeTest — acil fren mekanizmasının otomatik testi (headless).
##   godot --headless --path . res://tests/EmergencyBrakeTest.tscn
## Senaryolar:
##   1. Manuel acil fren: Space → çekiş yok → durur → kol nötr değilken reset reddedilir →
##      kol nötr → Shift+R reset → tren yeniden hareket eder.
##   2. ATP acil fren: limit +10 km/s aşımı → ATP nedeni → hareket halinde reset reddedilir →
##      duruşta reset kabul edilir.
##   3. SPAD: kırmızı sinyal geçilir → onay (F) olmadan reset reddedilir → onay + merkez izni → reset.
##   4. Tuş haritası: Shift+R "emergency_reset" tetikler, "reverser" tetiklemez (exact match).

var main: Node
var train: TrainController
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 7
	m["faults_enabled"] = false
	GameState.apply_mission(m)
	Engine.time_scale = 10.0
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	_run()

func _check(cond: bool, name: String) -> void:
	checks += 1
	if cond:
		print("  [OK]   ", name)
	else:
		print("  [FAIL] ", name)
		failures.append(name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _wait_until_stopped(max_sec: float = 60.0) -> void:
	var t := 0.0
	while not train.is_stopped() and t < max_sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _accelerate_to(kmh: float, max_sec: float = 60.0) -> void:
	train.lever = 0.8
	var t := 0.0
	while train.speed_kmh() < kmh and t < max_sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	train.lever = 0.0

func _prepare_departure() -> void:
	train.doors.request_close("right")
	await _wait(4.5)   # kapı animasyonu + 2 sn kalkış izni
	_check(GameState.departure_cleared, "Kalkış sinyali yeşile döndü")

func _run() -> void:
	await _wait(0.5)
	await _prepare_departure()

	print("\n--- Senaryo 1: Manuel acil fren ---")
	await _accelerate_to(35.0)
	_check(train.speed_kmh() >= 34.0, "Tren 35 km/s'e ulaştı")
	# Space tuşu simülasyonu (InputMap üzerinden)
	Input.action_press("emergency_brake")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("emergency_brake")
	_check(train.has_reason(TrainController.EmergencyReason.MANUAL), "Space → MANUEL acil fren devrede")
	var v_before := train.speed
	train.lever = 1.0   # çekiş denemesi
	await _wait(1.0)
	_check(train.speed < v_before, "Acil fren devredeyken çekiş uygulanamıyor (hız düşüyor)")
	await _wait_until_stopped()
	_check(train.is_stopped(), "Tren tamamen durdu")
	var r1 := train.reset_emergency()   # kol hâlâ +1
	_check(r1 == false and train.emergency_active(), "Kol nötr değilken reset reddedildi")
	train.lever = 0.0
	Input.action_press("emergency_reset")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("emergency_reset")
	_check(not train.emergency_active(), "Shift+R → acil fren sıfırlandı")
	await _accelerate_to(10.0, 20.0)
	_check(train.speed_kmh() >= 9.0, "Reset sonrası tren yeniden hareket etti")
	train.lever = -0.6
	await _wait_until_stopped()
	train.lever = 0.0

	print("\n--- Senaryo 2: ATP acil fren ---")
	# Limit 40 bölgesine (offset 100) ışınlan; hızı zorla limit+12'ye çıkar
	train.offset = 100.0
	train.speed = (train.current_limit_kmh() + 12.0) / 3.6
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(train.has_reason(TrainController.EmergencyReason.ATP), "Limit +12 km/s → ATP acil fren devrede")
	train.lever = 0.0
	var r2 := train.reset_emergency()
	_check(r2 == false and train.emergency_active(), "Hareket halinde ATP reset reddedildi")
	await _wait_until_stopped()
	var r3 := train.reset_emergency()
	_check(r3 == true and not train.emergency_active(), "Duruşta, kol nötr → ATP reset kabul edildi")

	print("\n--- Senaryo 3: SPAD (kırmızı sinyal) ---")
	var world: TrackBuilder = main.get_node("World")
	var sig: TrackSignal = null
	for id in world.signals_by_id:
		var cand: TrackSignal = world.signals_by_id[id]
		if cand.signal_type == "block" and cand.track_pos > 400.0 and (sig == null or cand.track_pos < sig.track_pos):
			sig = cand
	sig.forced_red = true
	sig.set_aspect("red")
	train.offset = sig.track_pos - 30.0
	train.speed = 20.0 / 3.6
	train.lever = 0.3
	var t := 0.0
	while not train.has_reason(TrainController.EmergencyReason.SPAD) and t < 20.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(train.has_reason(TrainController.EmergencyReason.SPAD), "Kırmızı sinyal geçildi → SPAD acil fren")
	train.lever = 0.0
	await _wait_until_stopped()
	var r4 := train.reset_emergency()
	_check(r4 == false, "Onay (F) olmadan SPAD reset reddedildi")
	train.acknowledge()
	var r5 := train.reset_emergency()
	_check(r5 == false, "Merkez izni olmadan SPAD reset reddedildi")
	train.grant_spad_permission()
	var r6 := train.reset_emergency()
	_check(r6 == true and not train.emergency_active(), "Onay + izin → SPAD reset kabul edildi")
	sig.forced_red = false

	print("\n--- Senaryo 4: Tuş haritası ---")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_R
	ev.shift_pressed = true
	ev.pressed = true
	_check(InputMap.event_is_action(ev, "emergency_reset"), "Shift+R → emergency_reset eşleşiyor")
	_check(not InputMap.event_is_action(ev, "reverser", true), "Shift+R → reverser ile TAM eşleşmiyor")
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_R
	ev2.pressed = true
	_check(InputMap.event_is_action(ev2, "reverser", true), "R → reverser eşleşiyor")
	_check(not InputMap.event_is_action(ev2, "emergency_reset"), "R (shift'siz) → emergency_reset eşleşmiyor")

	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  HATA: ", f)
	print("[TEST] %s" % ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
