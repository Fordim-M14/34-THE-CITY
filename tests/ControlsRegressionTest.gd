extends Node
## ControlsRegressionTest — kolay/gerçekçi sürüş, serbest sürüş, kamera titreşimi, ayar kaydet/yükle.
##   godot --headless --path . res://tests/ControlsRegressionTest.tscn

var main: Node
var train: TrainController
var failures: Array[String] = []
var checks := 0

func _check(cond: bool, name: String) -> void:
	checks += 1
	print("  [%s] %s" % ["OK" if cond else "FAIL", name])
	if not cond:
		failures.append(name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _boot(mode: String, direction: String = "forward") -> void:
	if main:
		main.queue_free()
		await get_tree().process_frame
		AudioManager.detach()
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 21
	m["faults_enabled"] = false
	m["traffic_enabled"] = false
	m["mode"] = mode
	m["direction"] = direction
	GameState.apply_mission(m)
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	await _wait(0.2)
	train.doors.request_close("right")
	await _wait(4.5)

func _ready() -> void:
	Engine.time_scale = 8.0
	_run()

func _run() -> void:
	await _boot("career")
	print("--- Kolay sürüş ---")
	Settings.control_mode = 1
	Settings.apply()
	var hud = main.get_node("HUD")
	var help: Label = hud.get_node("Root/Help")
	_check(help.text.begins_with("W hızlan"), "HUD tuş satırı kolay moda göre güncellendi")
	Input.action_press("throttle_up")
	await _ticks(90)
	_check(train.lever > 0.5 and train.speed_kmh() > 2.0, "W basılı → çekiş kolu %.2f, hız %.1f km/s" % [train.lever, train.speed_kmh()])
	Input.action_release("throttle_up")
	await _ticks(30)
	_check(absf(train.lever) < 0.05, "Tuş bırakılınca kol nötr (%.2f)" % train.lever)
	# Hız limiti yardımcısı: açık hatta (kırmızı sinyal yok) limiti aşmamalı, limite yakın gitmeli
	train.offset = 1200.0
	train.speed = 0.0
	train.emergency_reasons.clear()
	Input.action_press("throttle_up")
	await _ticks(60 * 60)
	_check(not train.has_reason(TrainController.EmergencyReason.ATP), "Kolay mod 60 s boyunca ATP müdahalesi tetiklemedi")
	var limit := train.current_limit_kmh()
	_check(train.speed_kmh() <= limit + 1.5 and train.speed_kmh() > limit - 8.0, "Hız limiti yardımcısı: %.1f km/s (limit %.0f)" % [train.speed_kmh(), limit])
	Input.action_release("throttle_up")
	Input.action_press("throttle_down")
	await _ticks(60 * 25)
	_check(train.lever < -0.5 or train.is_stopped(), "S basılı → fren (kol %.2f, hız %.1f)" % [train.lever, train.speed_kmh()])
	await _ticks(60 * 30)
	Input.action_release("throttle_down")
	_check(train.is_stopped(), "S ile durdu")
	# Kapı kontrolü: kolay modda Q da peron tarafını (sağ) açar — istasyonda olmadığımız için ret
	var rejected := []
	train.doors.door_command_rejected.connect(func(r: String) -> void: rejected.append(r))
	train.offset = float(GameState.route.stations[0]["stop_pos"])
	train.speed = 0.0
	await _ticks(5)
	Input.action_press("doors_left")
	await _ticks(2)
	Input.action_release("doors_left")
	await _wait(2.5)
	_check(train.doors.is_open("right") and not train.doors.is_open("left"), "Kolay mod: Q peron tarafındaki (sağ) kapıları açtı")
	train.doors.request_close("right")
	await _wait(3.0)
	print("--- Gerçekçi sürüş ---")
	Settings.control_mode = 0
	Settings.apply()
	_check(help.text.begins_with("W/S kol"), "HUD tuş satırı gerçekçi moda döndü")
	train.offset = 400.0
	train.lever = 0.0
	Input.action_press("throttle_up")
	await _ticks(30)
	Input.action_release("throttle_up")
	var l1 := train.lever
	await _ticks(30)
	_check(l1 > 0.3 and absf(train.lever - l1) < 0.01, "Gerçekçi mod: kol kademeli kalır (%.2f)" % train.lever)
	train.lever = 0.0
	print("--- Kamera titreşimleri ---")
	var cam: Camera3D = train.camera
	Settings.camera_shake = false
	Settings.camera_sway = 0.6
	train.speed = 70.0 / 3.6
	await _ticks(20)
	var off_off: Vector3 = cam.position - Vector3(0.0, Settings.seat_height, -Settings.seat_forward)
	_check(off_off.length() < 0.0001 and absf(cam.rotation.z) < 0.0001, "Titreşim kapalı: kamera ofseti/yatışı sıfır")
	Settings.camera_shake = true
	await _ticks(40)
	var off_on: Vector3 = cam.position - Vector3(0.0, Settings.seat_height, -Settings.seat_forward)
	_check(off_on.length() > 0.0005, "Titreşim açık: 70 km/s'de ray titreşimi var (%.4f m)" % off_on.length())
	Settings.camera_sway = 0.0
	await _ticks(40)
	var off_zero: Vector3 = cam.position - Vector3(0.0, Settings.seat_height, -Settings.seat_forward)
	_check(off_zero.length() < 0.0001, "Şiddet 0: titreşim yok")
	Settings.camera_sway = 1.0
	cam.set_look(30.0, -10.0)
	await _ticks(10)
	_check(absf(cam.rotation.y - deg_to_rad(30.0)) < 0.02, "Titreşim fare bakışını bozmuyor (yaw %.1f°)" % rad_to_deg(cam.rotation.y))
	train.speed = 0.0
	print("--- Ayar kaydet/yükle ---")
	Settings.control_mode = 1
	Settings.camera_shake = false
	Settings.camera_sway = 0.33
	Settings.show_fps = true
	Settings.save_settings()
	Settings.control_mode = 0
	Settings.camera_shake = true
	Settings.camera_sway = 0.6
	Settings.show_fps = false
	Settings.load_settings()
	_check(Settings.control_mode == 1 and Settings.camera_shake == false and absf(Settings.camera_sway - 0.33) < 0.001 and Settings.show_fps, "Ayarlar kaydedildi ve geri yüklendi")
	Settings.control_mode = 0
	Settings.camera_shake = true
	Settings.camera_sway = 0.6
	Settings.show_fps = false
	Settings.save_settings()
	print("--- Serbest sürüş ---")
	Career.new_profile("Test")
	var xp0 := int(Career.profile["xp"])
	var missions0 := int(Career.profile["stats"]["missions"])
	await _boot("free", "reverse")
	_check(GameState.is_free_mode() and GameState.route.direction == "reverse", "Serbest sürüş dönüş yönünde başladı")
	var mission = main.get_node("Mission")
	var score0 := Scoring.total_score()
	# Zaman baskısı: 10 dakika geç varış + kapı açılışı → zamanlama puanı düşmemeli
	var st1: Dictionary = GameState.route.stations[1]
	train.offset = float(st1["stop_pos"]) - 0.1
	train.speed = 0.0
	mission.stop_index = 0
	mission._set_state(MissionManager.State.RUNNING)
	GameState.mission_time = 600.0
	mission._on_stopped_at_platform(st1, -0.1)
	mission._on_doors_opened(str(st1.get("door_side", "right")), st1, true)
	_check(Scoring.total_score() == score0 and int(Scoring.category_scores[Scoring.Cat.TIMING]) == 25, "Serbest sürüşte 10 dk gecikmeye zaman cezası yok (puan %d, zamanlama %d/25)" % [Scoring.total_score(), int(Scoring.category_scores[Scoring.Cat.TIMING])])
	# İstasyon atlama: başarısızlık yok
	train.offset = float(GameState.route.stations[1]["platform_end"]) + 130.0
	mission._set_state(MissionManager.State.RUNNING)
	mission._overrun_station = GameState.route.stations[1]
	await _ticks(3)
	_check(mission.state != MissionManager.State.FINISHED, "Serbest sürüşte istasyon atlanınca sefer bitmiyor")
	mission.end_free_drive()
	await _wait(0.3)
	_check(mission.state == MissionManager.State.FINISHED, "Serbest sürüş istenildiği an bitirildi")
	_check(int(Career.profile["xp"]) == xp0 and int(Career.profile["stats"]["missions"]) == missions0, "Kariyer XP/istatistikleri değişmedi")
	Career.delete_profile()
	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  ✗ ", f)
	print("[TEST] " + ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
