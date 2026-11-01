extends Node
## ShotV4 — v0.4 görsel doğrulama (Forward+): kabin, panel, CCTV monitörü, yürüme modu salon,
## tren dışı, peron+yolcular, tünel, karşı tren.
##   xvfb-run godot --path . --rendering-driver vulkan res://tests/ShotV4.tscn [-- --only cab|saloon|ext|station|tunnel]

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

func _want(tag: String) -> bool:
	return only == "" or only == tag

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
	if _want("cab"):
		await _shot("v4_01_cabin_forward")
		train.camera.set_look(4.0, -30.0)
		await _frames(2)
		await _shot("v4_02_cabin_panel")
		train.camera.set_look(58.0, -10.0)
		await _frames(2)
		await _shot("v4_03_cabin_cctv_monitor")
		train.camera.set_look(-55.0, -14.0)
		await _frames(2)
		await _shot("v4_04_cabin_right")
		train.camera.set_look(150.0, -5.0)
		await _frames(2)
		await _shot("v4_05_cabin_rear_door")
		train.camera.set_look(0.0, 0.0)
	if _want("saloon"):
		var walker: PlayerWalker = main.get_node("Train/Visual/Car0/Walker")
		train.lever = 0.0
		if walker.stand_up():
			train.visual.set_cab_door(true)
			await _frames(5)
			# Kabin kapısı önünden salona bakış
			var car0: Node3D = train.cars[0]
			walker.global_position = car0.to_global(Vector3(0.48, 1.12, -7.4))
			walker._yaw = PI
			await _frames(3)
			await _shot("v4_06_walk_cabin_door")
			walker.global_position = car0.to_global(Vector3(0.0, 1.12, -4.0))
			walker._yaw = PI
			walker._pitch = -0.05
			await _frames(3)
			await _shot("v4_07_walk_saloon")
			walker.global_position = car0.to_global(Vector3(-0.6, 1.12, 9.5))
			walker._yaw = PI
			await _frames(3)
			await _shot("v4_08_walk_gangway")
			walker.global_position = car0.to_global(Vector3(0.0, 1.12, -4.0))
			walker.sit_down()
			train.visual.set_cab_door(false)
			await _frames(3)
	if _want("ext"):
		await _exterior_shot("v4_09_train_platform", Vector3(5.5, 2.6, 14.0), Vector3(0.0, 2.0, -22.0))
		await _exterior_shot("v4_10_train_front", Vector3(3.0, 1.8, -9.0), Vector3(0.0, 2.2, 6.0))
	if _want("tunnel"):
		train.doors.request_close("right")
		train.offset = 1000.0
		train.speed = 65.0 / 3.6
		await _frames(3)
		train.emergency_reasons.clear()
		train.visual.update_lever_visual(0.0, false, 1)
		train.speed = 65.0 / 3.6
		await _frames(2)
		await _shot("v4_11_tunnel_cabin")
		await _exterior_shot("v4_12_tunnel_exterior", Vector3(2.3, 2.4, -16.0), Vector3(0.0, 2.0, 5.0))
	if _want("opp"):
		# Karşı yön treni: en yakın karşı treni bul, yanına ışınlan ve kabinden bak
		var traffic = main.get_node("Traffic")
		train.doors.request_close("right")
		var best := {}
		var bd := INF
		for o in traffic.opp_trains:
			var dd: float = absf(float(o["offset"]) - 2000.0)
			if dd < bd:
				bd = dd
				best = o
		if not best.is_empty():
			train.offset = float(best["offset"]) - 45.0
			train.speed = 50.0 / 3.6
			await _frames(3)
			train.camera.set_look(-25.0, 0.0)
			await _frames(2)
			await _shot("v4_16_opposing_train_cabin")
			train.camera.set_look(0.0, 0.0)
			await _exterior_shot("v4_17_opposing_train_exterior", Vector3(-6.0, 2.3, -22.0), Vector3(-8.0, 1.9, -48.0))
			# Karşı peronda bekleyen tren: KRT istasyonunda
			train.offset = float(GameState.route.get_station_by_id("KRT")["stop_pos"])
			train.speed = 0.0
			await _frames(3)
			await _exterior_shot("v4_18_station_twin_track", Vector3(-13.5, 2.6, 6.0), Vector3(-2.0, 1.6, -45.0))
	if _want("station"):
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
		train.spad_acknowledged = false
		main.get_node("HUD").clear_center_message() if main.get_node("HUD").has_method("clear_center_message") else null
		train.doors.request_open("right")
		for i in 90:
			await get_tree().physics_frame
		await _shot("v4_13_kurtkoy_cabin")
		await _exterior_shot("v4_14_kurtkoy_boarding", Vector3(3.4, 2.1, 14.0), Vector3(1.2, 1.5, 36.0))
		await _exterior_shot("v4_15_kurtkoy_platform_wide", Vector3(5.8, 3.2, 4.0), Vector3(1.0, 1.3, 70.0))
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
