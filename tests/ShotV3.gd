extends Node
## ShotV3 — v0.3 görsel doğrulama (Forward+ ile): kabin ön görüş, panel, tren dışı,
## peron, tünel, yolcu binişi. Az sayıda kare, uzun bekleme yok.
##   xvfb-run godot --path . --rendering-driver vulkan res://tests/ShotV3.tscn

var main: Node
var train: TrainController
var mission: MissionManager
var world: TrackBuilder
var _ext_cam: Camera3D
var only := ""

func _ready() -> void:
	GameState.auto_test_mode = true
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1]
	var m := GameState.default_mission()
	m["seed"] = 2026
	m["start_time_s"] = 8 * 3600 + 5 * 60
	m["faults_enabled"] = false
	GameState.apply_mission(m)
	DirAccess.make_dir_recursive_absolute("user://shots")
	_run()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	mission = main.get_node("Mission")
	world = main.get_node("World")
	await _frames(3)
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(3)
	if only == "" or only == "cab":
		await _shot("v3_01_cabin_forward")
		train.camera.set_look(6.0, -32.0)
		await _frames(2)
		await _shot("v3_02_cabin_panel")
		train.camera.set_look(-70.0, -10.0)
		await _frames(2)
		await _shot("v3_03_cabin_left")
		train.camera.set_look(0.0, 0.0)
	if only == "" or only == "ext":
		await _exterior_shot("v3_04_train_platform", Vector3(5.5, 2.6, 14.0), Vector3(0.0, 2.0, -22.0))
		await _exterior_shot("v3_05_train_front", Vector3(3.0, 1.8, -9.0), Vector3(0.0, 2.2, 6.0))
	if only == "" or only == "tunnel":
		train.doors.request_close("right")
		train.offset = 1000.0
		train.speed = 65.0 / 3.6
		await _frames(3)
		await _shot("v3_06_tunnel_cabin")
		await _exterior_shot("v3_07_tunnel_exterior", Vector3(2.3, 2.4, -16.0), Vector3(0.0, 2.0, 5.0))
	if only == "" or only == "station":
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
		train.doors.request_open("right")
		# Yolcu hareketi için biraz fizik zamanı
		for i in 60:
			await get_tree().physics_frame
		await _shot("v3_08_kurtkoy_cabin")
		await _exterior_shot("v3_09_kurtkoy_boarding", Vector3(3.4, 2.1, 14.0), Vector3(1.2, 1.5, 36.0))
		await _exterior_shot("v3_10_kurtkoy_platform_wide", Vector3(5.8, 3.2, 4.0), Vector3(1.0, 1.3, 70.0))
	print("[SHOT] bitti")
	get_tree().quit(0)

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
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	print("[SHOT] ", name)
	main.get_node("HUD").visible = true
	train.camera.current = true
