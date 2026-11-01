extends Node
## SaveRegressionTest — otomatik kayıt, kaldığın yerden devam, kariyer korunması, yürüme modunda kayıt/yükleme.
##   godot --headless --path . res://tests/SaveRegressionTest.tscn

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

func _boot(resume: Dictionary = {}) -> void:
	if main:
		main.queue_free()
		await get_tree().process_frame
		AudioManager.detach()
	GameState.auto_test_mode = true
	if resume.is_empty():
		var m := GameState.default_mission()
		m["seed"] = 41
		m["faults_enabled"] = true
		GameState.apply_mission(m)
	else:
		GameState.apply_mission(resume["mission"])
		SaveGame.resume_data = resume
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	if resume.is_empty():
		main.get_node("MissionBrief").visible = false
		main.get_node("MissionBrief").accepted.emit()
	await _wait(0.3)

func _ready() -> void:
	_run()

func _run() -> void:
	SaveGame.clear()
	Career.new_profile("Kayıt Test")
	Career.profile["xp"] = 777
	Career.profile["money"] = 4321
	Career.save_profile()
	await _boot()
	print("--- Otomatik kayıt ---")
	var mission = main.get_node("Mission")
	var faults = main.get_node("Faults")
	mission.stop_index = 1
	mission._set_state(MissionManager.State.RUNNING)
	train.offset = 2800.0
	train.speed = 8.0
	train.headlights_on = false
	train.visual.set_headlights(false)
	faults._start("brake_warning")
	Scoring.add_penalty("hard_brake", "test")
	var pm = main.get_node("Passengers")
	pm.onboard = 321
	# Düzenli kayıt tetikleyicisi (SaveGame._process 20 sn) yerine doğrudan
	_check(SaveGame.save_from_main(main), "Kayıt yazıldı (sürüş sırasında)")
	var d := SaveGame.load_save()
	_check(not d.is_empty() and int(d["progress"]["stop_index"]) == 1 and "brake_warning" in d["progress"]["faults"] and int(d["progress"]["onboard"]) == 321 and d["train"]["headlights"] == false, "Kayıt içeriği: istasyon, arıza, doluluk, farlar")
	_check(d["scoring"]["penalties"].size() == 1, "Puanlama cezaları kaydedildi")
	print("--- Kaldığın yerden devam ---")
	await _boot(d)
	var mission2 = main.get_node("Mission")
	var faults2 = main.get_node("Faults")
	_check(absf(train.offset - 2800.0) < 80.0, "Konum geri yüklendi (%.0f m)" % train.offset)
	_check(mission2.stop_index == 1 and mission2.state == MissionManager.State.RUNNING, "Görev durumu geri yüklendi")
	_check(faults2.has_fault("brake_warning") and absf(train.brake_factor - 0.7) < 0.01, "Aktif arıza ve etkisi geri yüklendi")
	_check(main.get_node("Passengers").onboard == 321, "Doluluk geri yüklendi")
	_check(not train.headlights_on, "Far durumu geri yüklendi")
	_check(Scoring.penalties.size() == 1 and Scoring.total_score() < 100, "Puanlama geri yüklendi (%d)" % Scoring.total_score())
	_check(train.controls_enabled and not main.get_node("MissionBrief").visible, "Sürüş kontrolleri aktif, brifing yok")
	print("--- Kariyer korunması ---")
	_check(Career.load_profile() and int(Career.profile["xp"]) == 777 and int(Career.profile["money"]) == 4321, "Kariyer profili değişmedi (777 XP, 4321 ₺)")
	print("--- Yürüme modunda kayıt ---")
	train.speed = 0.0
	train.lever = 0.0
	train.offset = float(GameState.route.stations[1]["stop_pos"])
	await get_tree().physics_frame
	var walker: PlayerWalker = train.cars[0].get_node("Walker")
	_check(walker.stand_up(), "Yürüme moduna geçildi")
	var car0: Node3D = train.cars[0]
	walker.global_position = car0.to_global(Vector3(0.0, 1.13, 3.0))
	_check(SaveGame.save_from_main(main), "Yürürken kayıt yazıldı")
	var d2 := SaveGame.load_save()
	_check(not d2.is_empty() and float(d2["train"]["speed"]) == 0.0, "Yürüme kaydı geçerli (tren durmuş)")
	await _boot(d2)
	var walker2: PlayerWalker = train.cars[0].get_node("Walker")
	_check(not walker2.walking and train.camera.current and train.controls_enabled, "Yüklemede oyuncu güvenli biçimde koltukta başlar")
	_check(walker2.stand_up(), "Yüklemeden sonra tekrar kalkılabiliyor")
	walker2.sit_down()
	print("--- Temizlik ---")
	main.get_node("Mission")._finish("")
	await get_tree().process_frame
	_check(not SaveGame.has_save(), "Sefer bitince kayıt silindi")
	Career.delete_profile()
	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  ✗ ", f)
	print("[TEST] " + ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
