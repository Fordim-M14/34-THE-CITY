extends Node
## WalkthroughRegressionTest — gerçek oyuncu kapsülü ve move_and_slide ile tren içi geçiş testi.
## Kabin → V1 → V2 → V3 → V4 → V3 → V2 → V1 → Kabin; kapı açık/kapalı çarpışması; duvar/dış/zemin;
## koltuğa oturma ve sürüşe dönüş. godot --headless --path . res://tests/WalkthroughRegressionTest.tscn

var main: Node
var train: TrainController
var walker: PlayerWalker
var failures: Array[String] = []
var checks := 0
var verbose := false

func _ready() -> void:
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 5
	m["faults_enabled"] = false
	GameState.apply_mission(m)
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	verbose = OS.get_cmdline_user_args().has("--verbose")
	_run()

func _check(cond: bool, name: String) -> void:
	checks += 1
	print("  [%s] %s" % ["OK" if cond else "FAIL", name])
	if not cond:
		failures.append(name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

## Tren yerel koordinatı (Car0 çerçevesi: -z ileri/kabin, +z arka): araç i'nin yerel z'si
func _car_z(car: int, local_z: float) -> float:
	return local_z + car * (TrainController.CAR_LENGTH + TrainController.CAR_GAP)

func _local() -> Vector3:
	return train.cars[0].to_local(walker.global_position)

## Hedefe doğru gerçek yürüyüş (bakış yönü hedefe çevrilir, W basılı tutulur). Varırsa true.
func _walk_to(target_local: Vector3, max_frames: int = 1500, tol: float = 0.35, retry: bool = true) -> bool:
	var car0: Node3D = train.cars[0]
	var last := _local()
	var stuck := 0
	for i in max_frames:
		var p := _local()
		var d := Vector2(target_local.x - p.x, target_local.z - p.z)
		if d.length() < tol:
			Input.action_release("throttle_up")
			return true
		# Yerel +z yönüne yürümek için yaw = PI (model -z ileri)
		var world_dir := car0.global_transform.basis * Vector3(d.x, 0, d.y)
		walker._yaw = atan2(-world_dir.x, -world_dir.z)
		Input.action_press("throttle_up")
		await get_tree().physics_frame
		if (_local() - last).length() < 0.002:
			stuck += 1
			if stuck > 40:
				break
		else:
			stuck = 0
		last = _local()
	Input.action_release("throttle_up")
	if retry:
		print("    !! TAKILDI, yeniden deneme: konum ", _local(), " hedef ", target_local)
		# Köşeye sıkışma (ör. kapı cebi + koltuk bölücü): önce koridor ortasına çık, sonra tekrar dene
		var p := _local()
		await _walk_to(Vector3(0.0, 1.13, p.z), 240, 0.3, false)
		return await _walk_to(target_local, max_frames, tol, false)
	if verbose:
		print("    takıldı: ", _local(), " hedef ", target_local)
	return false

func _set_local(p: Vector3) -> void:
	walker.global_position = train.cars[0].to_global(p)
	walker.velocity = Vector3.ZERO

## Yalnız W basılı, sabit bakış yönüyle (+z ya da -z) düz yürüyüş — oyuncu davranışının birebir taklidi
func _straight(dir: float, z_end: float, max_frames: int = 3000) -> Dictionary:
	walker._yaw = PI if dir > 0 else 0.0
	var last := _local()
	var stuck := 0
	for i in max_frames:
		var p := _local()
		if (dir > 0 and p.z >= z_end) or (dir < 0 and p.z <= z_end):
			Input.action_release("throttle_up")
			return {"ok": true, "pos": p}
		Input.action_press("throttle_up")
		await get_tree().physics_frame
		if (_local() - last).length() < 0.002:
			stuck += 1
			if stuck > 30:
				Input.action_release("throttle_up")
				return {"ok": false, "pos": _local()}
		else:
			stuck = 0
		last = _local()
	Input.action_release("throttle_up")
	return {"ok": false, "pos": _local()}

func _run() -> void:
	await _wait(0.3)
	walker = train.cars[0].get_node("Walker")
	train.lever = 0.0
	print("--- Kalkış ---")
	_check(walker.stand_up(), "Koltuktan kalkıldı")
	_check(walker.walking and walker.cam.current, "Yürüme kamerası aktif")
	# Kapalı kapıdan geçilememeli
	var door_front := Vector3(0.48, 1.13, -8.5)   # kabin tarafı, kapının önü (koridor hizası)
	var saloon_side := Vector3(0.48, 1.13, -7.2)
	_check(await _walk_to(door_front, 600), "Kabin kapısının önüne yüründü")
	var passed := await _walk_to(saloon_side, 240, 0.3)
	_check(not passed and _local().z < -7.9, "Kapalı kabin kapısından geçilemedi (z=%.2f)" % _local().z)
	# Kapıyı aç → geçilmeli
	train.visual.set_cab_door(true)
	await _wait(0.8)
	_check(await _walk_to(saloon_side, 400), "Açık kabin kapısından salona geçildi (Kabin → V1)")
	# Vagon içinde ilerleme: direklerin yanından (x=0,45), geçişlerde orta (x=0)
	var route_pts: Array = []
	for car in range(0, 4):
		route_pts.append(Vector3(0.45, 1.13, _car_z(car, -5.0)))
		route_pts.append(Vector3(0.45, 1.13, _car_z(car, 5.0)))
		if car < 3:
			route_pts.append(Vector3(0.0, 1.13, _car_z(car, 10.3)))     # geçiş
			route_pts.append(Vector3(0.0, 1.13, _car_z(car + 1, -10.3)))
	var names := ["V1 orta", "V1 son", "V1→V2 geçiş a", "V1→V2 geçiş b", "V2 orta", "V2 son", "V2→V3 geçiş a", "V2→V3 geçiş b", "V3 orta", "V3 son", "V3→V4 geçiş a", "V3→V4 geçiş b", "V4 orta", "V4 son"]
	print("--- İleri: V1 → V4 ---")
	for i in route_pts.size():
		var ok := await _walk_to(route_pts[i], 900)
		_check(ok, "%s (%.1f, %.1f) ulaşıldı" % [names[i], _local().x, _local().z])
		if not ok:
			break
	var far := _local()
	_check(far.z > _car_z(3, 3.0), "4. vagonun sonuna varıldı (z=%.1f)" % far.z)
	_check(absf(far.y - 1.13) < 0.25, "Zemin seviyesi korundu (y=%.2f)" % far.y)
	print("--- Geri: V4 → Kabin ---")
	route_pts.reverse()
	names.reverse()
	for i in route_pts.size():
		var ok := await _walk_to(route_pts[i], 900)
		_check(ok, "geri: %s ulaşıldı" % names[i])
		if not ok:
			break
	_check(await _walk_to(saloon_side, 900), "V1 → kabin kapısı önü")
	_check(await _walk_to(door_front, 400), "Kabine girildi")
	print("--- Duvar / dış / zemin ---")
	await _walk_to(Vector3(0.0, 1.13, -4.0), 600)
	await _walk_to(Vector3(2.5, 1.13, -4.0), 240)
	_check(absf(_local().x) < 1.4, "Yan duvardan geçilmedi (x=%.2f)" % _local().x)
	await _walk_to(Vector3(0.0, 1.13, -4.0), 600)
	await _walk_to(Vector3(0.0, 1.13, 0.5), 400)
	await _walk_to(Vector3(2.5, 1.13, 0.5), 240)     # sağ kapı hizası (kapalı)
	_check(absf(_local().x) < 1.4, "Kapalı yolcu kapısından dışarı çıkılmadı (x=%.2f)" % _local().x)
	_check(_local().y > 1.0, "Zeminden düşülmedi (y=%.2f)" % _local().y)
	print("--- Vagon içi etkileşim ---")
	var free_seat: Node3D = null
	for d in train.visual.seat_positions:
		if int(d["car"]) != 0:
			continue
		var sn: Node3D = d["node"]
		var occupied := false
		for ch in sn.get_children():
			if ch is Node3D and not (ch is Area3D):
				occupied = true
		if not occupied and absf(sn.position.z + 4.0) < 3.0:
			free_seat = sn
			break
	_check(free_seat != null, "Boş yolcu koltuğu bulundu")
	if free_seat:
		var before := walker.global_position
		walker._hover = null
		walker._sit_on_seat(free_seat)
		_check(walker.seated_on == free_seat and walker.global_position.distance_to(free_seat.global_position) < 0.6, "Boş koltuğa oturuldu (kamera koltukta)")
		await get_tree().physics_frame
		walker._stand_from_seat()
		_check(walker.seated_on == null and walker.global_position.distance_to(before) < 0.05, "Koltuktan kalkıldı, eski konuma dönüldü")
	var hud = main.get_node("HUD")
	walker._inspect("routemap", "Hat haritası")
	_check(str(hud.center_msg_label.text).contains("Pendik"), "Hat haritası incelendi (bilgi mesajı: %s)" % str(hud.center_msg_label.text).left(40))
	print("--- Düz çizgi taraması (W basılı, koridorun 4 hizası, ileri + geri) ---")
	for x in [-0.45, -0.3, 0.3, 0.45]:
		_set_local(Vector3(x, 1.13, -6.0))
		await get_tree().physics_frame
		var r1: Dictionary = await _straight(1.0, _car_z(3, 6.0))
		_check(bool(r1["ok"]), "x=%.2f ileri Kabin→V4 düz yürüyüş (%s)" % [x, str(r1["pos"]) if not r1["ok"] else "OK"])
		_set_local(Vector3(x, 1.13, _car_z(3, 6.0)))
		await get_tree().physics_frame
		var r2: Dictionary = await _straight(-1.0, -6.0)
		_check(bool(r2["ok"]), "x=%.2f geri V4→V1 düz yürüyüş (%s)" % [x, str(r2["pos"]) if not r2["ok"] else "OK"])
	print("--- Hata enjeksiyonu: 2. vagon zemin çarpışması kapalıyken (v0.4 hatası) geçiş ---")
	var disabled: Array = []
	for mi in train.cars[1].find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).contains("Floor"):
			for ch in mi.get_children():
				if ch is StaticBody3D:
					ch.collision_layer = 0
					disabled.append(ch)
	_check(disabled.size() > 0, "2. vagon zemin çarpışma gövdeleri kapatıldı (%d)" % disabled.size())
	_set_local(Vector3(0.3, 1.13, -6.0))
	await get_tree().physics_frame
	var rf: Dictionary = await _straight(1.0, _car_z(2, -6.0))
	_check(bool(rf["ok"]), "Zemin boşluğuna rağmen V1→V2→V3 geçildi (basamak tırmanma + zemin emniyeti)")
	var rb: Dictionary = await _straight(-1.0, -6.0)
	_check(bool(rb["ok"]), "Zemin boşluğuna rağmen V3→V2→V1 geri dönüldü")
	var lp := train.cars[1].to_local(walker.global_position) if not rb["ok"] else Vector3(0, 1.13, 0)
	_check(absf(lp.y - 1.13) < 0.2, "Oyuncu zeminin altına inmedi (y=%.2f)" % lp.y)
	for ch in disabled:
		ch.collision_layer = 1
	_set_local(Vector3(0.45, 1.13, -5.0))
	await get_tree().physics_frame
	print("--- Tren içi yolcu yerleşimi ---")
	var pm: Node = main.get_node("Passengers")
	for i in 80:
		pm._add_onboard_passenger()
	var in_cab := 0
	var mh_count := 0
	for d in pm.onboard_nodes:
		var n: Node3D = d["node"]
		if str(n.scene_file_path).contains("passenger_"):
			mh_count += 1
		var l0 := train.cars[0].to_local(n.global_position)
		var l3 := train.cars[3].to_local(n.global_position)
		if (absf(l0.x) < 1.4 and l0.z < -7.0 and l0.z > -11.0) or (absf(l3.x) < 1.4 and l3.z > 7.0 and l3.z < 11.0):
			in_cab += 1
	_check(pm.onboard_nodes.size() >= 60, "Görünür tren içi yolcu oluşturuldu (%d)" % pm.onboard_nodes.size())
	_check(in_cab == 0, "Makinist kabinlerine yolcu konmadı (%d)" % in_cab)
	_check(mh_count == pm.onboard_nodes.size(), "Tüm tren içi yolcular MakeHuman modeli (%d/%d)" % [mh_count, pm.onboard_nodes.size()])
	for d in pm.onboard_nodes:
		(d["node"] as Node).queue_free()
	pm.onboard_nodes.clear()
	print("--- Oturma ---")
	await _walk_to(saloon_side, 600)
	await _walk_to(door_front, 600)
	await _walk_to(Vector3(0.4, 1.13, -8.5), 400)
	_check(walker.near_seat(), "Koltuk yanında")
	walker.sit_down()
	train.visual.set_cab_door(false)
	_check(not walker.walking and train.camera.current and train.controls_enabled, "Oturuldu, sürüş kontrolleri aktif")
	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  ✗ ", f)
	print("[TEST] " + ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
