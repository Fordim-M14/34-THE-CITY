extends Node
## ShotV41 — v0.4.1 ekran görüntüleri (Forward+): kabin, 1. vagon, 2. ve 3. vagona geçiş, 4. vagon,
## yolcu dolu istasyon, yolcu yüzü/kıyafet, koltuğa oturma, CCTV, FPS göstergesi.
##   xvfb-run godot --path . --rendering-driver vulkan res://tests/ShotV41.tscn

var main: Node
var train: TrainController
var mission: MissionManager
var world: TrackBuilder
var walker: PlayerWalker
var _ext_cam: Camera3D

func _ready() -> void:
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 2027
	m["start_time_s"] = 8 * 3600 + 10 * 60
	m["faults_enabled"] = false
	GameState.apply_mission(m)
	DirAccess.make_dir_recursive_absolute("user://shots")
	_run()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _car_z(car: int, local_z: float) -> float:
	return local_z + car * (TrainController.CAR_LENGTH + TrainController.CAR_GAP)

func _put(x: float, z: float, yaw: float, pitch: float = 0.0) -> void:
	walker.global_position = train.cars[0].to_global(Vector3(x, 1.13, z))
	walker._yaw = yaw
	walker._pitch = pitch
	await _frames(3)

var only := ""

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1]
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	mission = main.get_node("Mission")
	world = main.get_node("World")
	await _frames(3)
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Settings.show_fps = true
	Perf.visible = true
	await _frames(4)
	walker = main.get_node("Train/Visual/Car0/Walker")
	if only == "pis":
		train.lever = 0.0
		walker.stand_up()
		train.visual.set_cab_door(true)
		await _frames(5)
		train.visual.set_pis_text("Next station: Fevzi Çakmak-Hospital")
		# kapı üstü PIS'e bak (sağ taraf, z≈-0.5)
		for side in [1.0, -1.0]:
			await _put(-0.35 * side, 1.6, PI, 0.0)
			var dv := train.cars[0].to_global(Vector3(0.52 * side, 2.75, 0.5)) - walker.cam.global_position
			walker._yaw = atan2(-dv.x, -dv.z)
			walker._pitch = atan2(dv.y, Vector2(dv.x, dv.z).length())
			await _frames(3)
			await _shot("v41_12_pis_led_yazisi" + ("" if side > 0 else "_sol"))
		print("[SHOT] bitti")
		get_tree().quit(0)
		return
	if only == "station":
		await _station_shots()
		print("[SHOT] bitti")
		get_tree().quit(0)
		return
	await _shot("v41_01_makinist_kabini")
	train.lever = 0.0
	walker.stand_up()
	train.visual.set_cab_door(true)
	await _frames(5)
	await _put(0.48, -8.4, PI, -0.05)
	await _shot("v41_02_kabin_kapisi_acik")
	await _put(0.0, -4.5, PI, -0.04)
	await _shot("v41_03_birinci_vagon")
	await _put(0.0, _car_z(0, 8.8), PI, -0.03)
	await _shot("v41_04_ikinci_vagona_gecis")
	await _put(0.0, _car_z(1, 8.8), PI, -0.03)
	await _shot("v41_05_ucuncu_vagona_gecis")
	await _put(0.0, _car_z(3, -2.0), PI, -0.03)
	await _shot("v41_06_dorduncu_vagon")
	# Yolcu yüzü ve kıyafet: oturan bir yolcunun karşısına yaklaş
	var target: Node3D = null
	for d in train.visual.seat_positions:
		if int(d["car"]) != 0:
			continue
		var sn: Node3D = d["node"]
		for ch in sn.get_children():
			if ch is Node3D and not (ch is Area3D):
				target = sn
		if target:
			break
	if target:
		var sp := train.cars[0].to_local(target.global_position)
		var side := signf(sp.x)
		await _put(sp.x - side * 0.95, sp.z, (PI / 2.0) * side * -1.0, -0.12)
		# yüzüne bak: yaw hedefe doğru
		var dirv := target.global_position - walker.global_position
		walker._yaw = atan2(-dirv.x, -dirv.z)
		walker._pitch = -0.12
		await _frames(3)
		await _shot("v41_07_yolcu_yuzu_kiyafet")
	# Koltuğa oturma
	var free_seat: Node3D = null
	for d in train.visual.seat_positions:
		if int(d["car"]) != 0:
			continue
		var sn: Node3D = d["node"]
		var occ := false
		for ch in sn.get_children():
			if ch is Node3D and not (ch is Area3D):
				occ = true
		if not occ and sn.position.z > -6.0 and sn.position.z < 6.0:
			free_seat = sn
			break
	if free_seat:
		await _put(0.0, train.cars[0].to_local(free_seat.global_position).z, PI)
		walker._sit_on_seat(free_seat)
		walker._pitch = -0.05
		await _frames(4)
		await _shot("v41_08_koltukta_oturma")
		walker._stand_from_seat()
	await _put(0.0, -4.0, PI)
	walker.sit_down()
	train.visual.set_cab_door(false)
	await _frames(3)
	# CCTV + FPS: kabinde sola bak
	train.camera.set_look(58.0, -10.0)
	await _frames(3)
	await _shot("v41_09_cctv_ekrani")
	train.camera.set_look(0.0, 0.0)
	await _station_shots()
	print("[SHOT] bitti")
	get_tree().quit(0)

func _station_shots() -> void:
	# Yolcu dolu istasyon: Kurtköy'e git, kapıları aç
	mission.stop_index = 0
	mission._set_state(MissionManager.State.RUNNING)
	train.offset = float(GameState.route.get_station_by_id("KRT")["stop_pos"]) - 0.1
	train.speed = 0.0
	train.lever = -0.5
	await _frames(4)
	var t := 0.0
	while mission.state != MissionManager.State.ARRIVED and t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	train.emergency_reasons.clear()
	for i in 30:
		await get_tree().physics_frame
	await _exterior_shot("v41_10_yolcu_dolu_istasyon", Vector3(5.6, 2.1, 46.0), Vector3(3.2, 1.3, 92.0))
	train.doors.request_open("right")
	for i in 150:
		await get_tree().physics_frame
	await _exterior_shot("v41_10b_istasyon_yolcular_yakin", Vector3(3.0, 1.7, 50.0), Vector3(5.0, 1.4, 64.0))
	await _shot("v41_11_fps_gostergesi")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	print("[SHOT] ", name)

func _exterior_shot(name: String, local_eye: Vector3, local_target: Vector3) -> void:
	if _ext_cam == null:
		_ext_cam = Camera3D.new()
		_ext_cam.far = 900.0
		_ext_cam.fov = 60.0
		add_child(_ext_cam)
	var xf := world.get_track_transform(train.offset)
	var eye := xf.translated_local(local_eye).origin
	var target := xf.translated_local(local_target).origin
	_ext_cam.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	_ext_cam.current = true
	main.get_node("HUD").visible = false
	await _frames(24)   # animasyon LOD'unun yeni kameraya göre güncellenmesi için
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	print("[SHOT] ", name)
	main.get_node("HUD").visible = true
	train.camera.current = true
