extends Node
## SystemsTest — v0.4 sistemleri (headless): tren modeli düğümleri, CCTV, yürüme modu, kabin kapısı,
## PIS/hat haritası, şalterler, telsiz. godot --headless --path . res://tests/SystemsTest.tscn

var main: Node
var train: TrainController
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 11
	m["faults_enabled"] = false
	GameState.apply_mission(m)
	Engine.time_scale = 8.0
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

func _run() -> void:
	await _wait(0.5)
	var v: TrainVisual = train.visual
	print("--- Tren modeli ---")
	_check(train.cars.size() == 4, "4 araç kuruldu")
	_check(v.eye_node != null and v.camera != null, "Cam_Eye + kabin kamerası")
	_check(v.cab_door_pivot != null, "Kabin kapısı menteşesi (CabDoorPivot)")
	_check(v.seat_positions.size() >= 120, "Koltuk noktaları ≥ 120 (%d)" % v.seat_positions.size())
	_check(v.cctv_cam_nodes.size() == 8, "Vagon içi CCTV noktaları 8 (%d)" % v.cctv_cam_nodes.size())
	_check(v.door_panels_left.size() == 12 and v.door_panels_right.size() == 12, "Kapı çiftleri 12/12")
	var n_static := 0
	for mi in train.find_children("Static_*", "MeshInstance3D", true, false):
		n_static += 1
	_check(n_static >= 40, "Statik iç mekân mesh'leri birleştirilmiş (%d)" % n_static)
	_check(v.controls.size() >= 25, "Etkileşimli kontrol sayısı ≥ 25 (%d)" % v.controls.size())
	var actions := {}
	for a in v.controls:
		actions[str(a.get_meta("action"))] = true
	for need in ["lever", "reverser", "emergency_brake", "cctv_toggle", "cctv_next", "sw_headlight_mode", "knob_brightness", "cab_door", "radio_ptt", "pis_announce"]:
		_check(actions.has(need), "Kontrol: " + need)

	print("--- CCTV ---")
	var cctv: CCTVSystem = main.get_node("CCTV")
	_check(cctv.camera_count() == 16, "16 kamera (8 iç + 8 kapı) (%d)" % cctv.camera_count())
	var first := cctv.current_name()
	cctv.next_camera()
	_check(cctv.current_name() != first, "Kamera değiştirme: %s → %s" % [first, cctv.current_name()])
	cctv.select_door_side("right")
	_check(cctv.current_name().contains("SAĞ"), "Kapı kamerası seçimi (sağ): " + cctv.current_name())
	cctv.toggle()
	_check(not cctv.enabled_monitor, "Monitör kapatıldı")
	cctv.toggle()
	_check(cctv.enabled_monitor, "Monitör açıldı")

	print("--- Şalter / parlaklık / telsiz ---")
	_check(v.toggle_switch("headlight_mode") == true and v.switch_state("headlight_mode"), "Far modu şalteri AÇIK")
	_check(v.toggle_switch("headlight_mode") == false, "Far modu şalteri KAPALI")
	v.set_screen_brightness(0.4)
	v.set_radio_text("TEST")
	var traffic = main.get_node("Traffic")
	var before: int = traffic.messages.size()
	traffic.driver_call()
	_check(traffic.messages.size() == before + 1, "Telsiz PTT → merkez yanıtı")

	print("--- Yürüme modu ---")
	var walker: PlayerWalker = train.cars[0].get_node("Walker")
	train.lever = 0.4
	_check(not walker.stand_up(), "Kol çekişteyken kalkılamaz")
	train.lever = 0.0
	_check(walker.stand_up(), "Duruşta koltuktan kalkıldı")
	_check(walker.walking and walker.cam.current and not train.controls_enabled, "Yürüme kamerası aktif, sürüş kontrolleri kapalı")
	var sb := 0
	for s in train.find_children("*", "StaticBody3D", true, false):
		sb += 1
	_check(sb >= 60, "İç mekân çarpışmaları üretildi (%d StaticBody)" % sb)
	v.set_cab_door(true)
	await _wait(0.8)
	_check(v.cab_door_open and absf(v.cab_door_pivot.rotation_degrees.y + 168.0) < 2.0, "Kabin kapısı açıldı (%.0f°)" % v.cab_door_pivot.rotation_degrees.y)
	# Kabin kapısından salona yürü (ileri = -z yerel; kabin önde, salon arkada)
	var car0: Node3D = train.cars[0]
	walker.global_position = car0.to_global(Vector3(0.48, 1.15, -8.3))
	walker._yaw = PI
	for i in 20:
		Input.action_press("throttle_up")
		await get_tree().physics_frame
	Input.action_release("throttle_up")
	var local := car0.to_local(walker.global_position)
	_check(local.z > -7.6 and local.z < -1.5 and absf(local.y - 1.1) < 0.3, "Kapıdan salona yüründü (z=%.1f, y=%.2f)" % [local.z, local.y])
	# Duvara doğru yürü: dışarı çıkılmamalı
	walker._yaw = PI / 2.0
	for i in 90:
		Input.action_press("throttle_up")
		await get_tree().physics_frame
	Input.action_release("throttle_up")
	local = car0.to_local(walker.global_position)
	_check(absf(local.x) < 1.35, "Duvardan geçilmedi (x=%.2f)" % local.x)
	# Vagon sonuna (geçiş) yürü
	walker.global_position = car0.to_global(Vector3(0.0, 1.15, 9.0))
	walker._yaw = PI
	for i in 150:
		Input.action_press("throttle_up")
		await get_tree().physics_frame
	Input.action_release("throttle_up")
	local = car0.to_local(walker.global_position)
	_check(local.z > 10.5, "Geçişten ikinci vagona geçildi (z=%.1f)" % local.z)
	_check(not walker.near_seat(), "Koltuktan uzakta")
	walker.global_position = car0.to_global(Vector3(-0.3, 1.15, -8.2))
	await get_tree().physics_frame
	_check(walker.near_seat(), "Koltuk yanında")
	walker.sit_down()
	_check(not walker.walking and train.camera.current and train.controls_enabled, "Koltuğa oturuldu, sürüş kontrolleri açık")
	v.set_cab_door(false)

	print("--- PIS / hat haritası ---")
	var labels := 0
	for l in train.find_children("*", "Label3D", true, false):
		labels += 1
	_check(labels >= 200, "Label3D metinleri (kadran, etiketler, PIS, harita) ≥ 200 (%d)" % labels)
	v.set_pis_text("TEST")
	_check(v._pis_labels.size() >= 24 and v._pis_labels[0].text == "TEST", "PIS ekranları güncellendi (%d)" % v._pis_labels.size())

	print("--- Otomatik kayıt / devam ---")
	var mission: MissionManager = main.get_node("Mission")
	mission.stop_index = 2
	mission._set_state(MissionManager.State.RUNNING)
	train.offset = 3210.0
	train.speed = 12.0
	_check(SaveGame.save_from_main(main), "Kayıt yazıldı")
	var d := SaveGame.load_save()
	_check(not d.is_empty() and absf(float(d["train"]["offset"]) - 3210.0) < 0.01 and int(d["progress"]["stop_index"]) == 2, "Kayıt doğrulandı (offset 3210, istasyon 2)")
	_check(SaveGame.describe(d).contains("istasyon 3/6"), "Kayıt açıklaması: " + SaveGame.describe(d))
	# Bozuk kayıt: oyunu bozmamalı
	var fw := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	fw.store_string("{bozuk json !!")
	fw.close()
	_check(SaveGame.load_save().is_empty() and not FileAccess.file_exists(SaveGame.PATH), "Bozuk kayıt yok sayıldı ve silindi")
	# Devam: yeni Main örneği kaydı uygular
	SaveGame.save_from_main(main)
	d = SaveGame.load_save()
	main.queue_free()
	await get_tree().process_frame
	AudioManager.detach()
	GameState.apply_mission(d["mission"])
	SaveGame.resume_data = d
	var main2: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main2)
	await _wait(0.3)
	var train2: TrainController = main2.get_node("Train")
	var mission2: MissionManager = main2.get_node("Mission")
	_check(absf(train2.offset - 3210.0) < 60.0 and mission2.stop_index == 2 and mission2.state == MissionManager.State.RUNNING and train2.controls_enabled, "Kayıttan devam: konum/istasyon/durum geri yüklendi (offset %.0f)" % train2.offset)
	_check(not main2.get_node("MissionBrief").visible, "Devamda brifing atlandı")
	SaveGame.clear()
	_check(not SaveGame.has_save(), "Kayıt temizlendi")

	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  ✗ ", f)
	print("[TEST] " + ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
