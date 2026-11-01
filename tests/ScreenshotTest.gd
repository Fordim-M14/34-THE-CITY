extends Node
## ScreenshotTest v2 — anahtar anlarda ekran görüntüsü (sanal ekran + yazılım GL ile de çalışır):
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/ScreenshotTest.tscn

var main: Node
var train: TrainController
var mission: MissionManager
var world: TrackBuilder
var shots: Array = []
var _ext_cam: Camera3D

func _ready() -> void:
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 2024
	m["start_time_s"] = 8 * 3600 + 5 * 60
	GameState.apply_mission(m)
	DirAccess.make_dir_recursive_absolute("user://shots")
	_run()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _run() -> void:
	# Ana menü
	var menu: Node = load("res://scenes/ui/MainMenu.tscn").instantiate()
	add_child(menu)
	await _wait(1.5)
	await _shot("00_main_menu")
	menu.queue_free()
	await _wait(0.2)
	# Oyun
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	mission = main.get_node("Mission")
	world = main.get_node("World")
	await _wait(1.0)
	await _shot("01_brief")
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	await _wait(1.0)
	# Kabin: bir kontrole bak (fare yakalı değil → merkez ışını)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	train.camera.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(8.0), 0)
	await _wait(0.6)
	await _shot("02_cabin_panel_look_down")
	train.camera.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0)
	await _wait(0.3)
	await _shot("03_cabin_sgh_boarding")
	await _exterior_shot("04_sgh_platform_passengers", true)
	var side := str(mission.current_station()["door_side"])
	train.doors.request_close(side)
	await _wait(5.0)
	await _shot("05_departure_signal_green")
	train.lever = 0.7
	var t0 := 0.0
	while train.speed_kmh() < 30.0 and t0 < 40.0:
		await get_tree().physics_frame
		t0 += get_physics_process_delta_time()
	train.lever = 0.0
	# Tünel içi: offset 1000'e ışınla, 70 km/s
	train.offset = 1000.0
	train.speed = 70.0 / 3.6
	await _wait(0.6)
	await _shot("06_tunnel_70kmh")
	await _exterior_shot("07_train_exterior_tunnel", false)
	# Açık kesime ışınla
	train.offset = 3600.0
	train.speed = 60.0 / 3.6
	train.lever = 0.0
	await _wait(0.8)
	await _shot("08_open_section_cabin")
	await _exterior_shot("09_open_section_exterior", false)
	# Yayalar istasyonu (açık kesim istasyonu) yaklaşım
	train.offset = float(GameState.route.get_station_by_id("YYS")["stop_pos"]) - 0.1
	train.speed = 0.0
	train.lever = -0.5
	await _wait(1.0)
	await _shot("10_yayalar_platform_cabin")
	# Kurtköy'e geri: varış + yolcu iniş/biniş (görev akışı için durak indeksini ayarla)
	mission.stop_index = 0
	mission._set_state(MissionManager.State.RUNNING)
	train.offset = float(GameState.route.get_station_by_id("KRT")["stop_pos"]) - 40.0
	train.speed = 20.0 / 3.6
	train.lever = -0.6
	var t := 0.0
	while mission.state != MissionManager.State.ARRIVED and t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _wait(0.5)
	train.doors.request_open("right")
	await _wait(4.0)
	await _exterior_shot("11_kurtkoy_alighting", true)
	await _shot("12_kurtkoy_cabin_dwell")
	# MMI arıza sayfası
	main.get_node("MMI").set_page(1)
	train.camera.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-4.0), 0)
	await _wait(0.5)
	await _shot("13_mmi_fault_page")
	main.get_node("MMI").set_page(0)
	train.camera.rotation = Vector3.ZERO
	# Duraklatma menüsü
	main.get_node("PauseMenu").open()
	await _wait(0.5)
	await _shot("14_pause_menu")
	main.get_node("PauseMenu").resume()
	# Puan ekranı
	mission._finish("")
	await _wait(1.0)
	await _shot("15_score")
	print("[SHOT] Kaydedilen görüntüler: ", shots)
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	shots.append(name)
	print("[SHOT] ", name, " ", img.get_size())

func _exterior_shot(name: String, at_platform: bool) -> void:
	if _ext_cam == null:
		_ext_cam = Camera3D.new()
		_ext_cam.far = 900.0
		add_child(_ext_cam)
	var xf := world.get_track_transform(train.offset)
	var eye: Vector3
	var target: Vector3
	if at_platform:
		eye = xf.translated_local(Vector3(4.6, 3.2, 10.0)).origin
		target = xf.translated_local(Vector3(0.5, 1.8, -30.0)).origin
	else:
		eye = xf.translated_local(Vector3(2.2, 2.6, -18.0)).origin
		target = xf.translated_local(Vector3(0.0, 2.0, 6.0)).origin
	_ext_cam.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	_ext_cam.current = true
	main.get_node("HUD").visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	shots.append(name)
	print("[SHOT] ", name, " ", img.get_size())
	main.get_node("HUD").visible = true
	train.camera.current = true
