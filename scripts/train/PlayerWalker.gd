class_name PlayerWalker
extends CharacterBody3D
## PlayerWalker — gezilebilir tren içi. Tren tamamen durduğunda makinist koltuğundan kalkılır
## (X), kabin ve dört vagon içinde yürünür (WASD, Shift: hızlı), kabin kapısı ve geçişlerden
## geçilir, koltuğa dönülüp (X, koltuk yanında) sürüşe devam edilir.
## CharacterBody3D + kapsül; iç mekân çarpışmaları TrainVisual.build_walk_collisions() ile
## statik mesh'lerden (trimesh) üretilir, kapı kanatları ve kabin kapısı ayrıca kutu çarpışmalıdır.
## Oyuncu vagonun çocuğudur: tren hareket etse de içinde kalır. Zeminden düşerse koltuğa döner.

signal mode_changed(walking: bool)

const EYE_H := 1.62
const STEP_H := 0.32
const WALK_SPEED := 1.6
const RUN_SPEED := 2.7
const SENS := 0.0022

var train: TrainController
var hud: Node
var walking: bool = false
var cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _bob := 0.0
var _hover: Area3D
var _seat_area: Area3D
var _enabled_interaction: bool = true
var seated_on: Node3D = null          # yolcu koltuğunda oturuyorsa koltuk düğümü
var _seat_return: Vector3 = Vector3.ZERO
var _seat_yaw := 0.0
var _info_timer := 0.0

func setup(p_train: TrainController, p_hud: Node) -> void:
	train = p_train
	hud = p_hud
	collision_layer = 0
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	cam = Camera3D.new()
	cam.name = "WalkCamera"
	cam.fov = Settings.fov
	cam.near = 0.05
	cam.far = 600.0
	cam.position = Vector3(0, EYE_H, 0)
	cam.current = false
	add_child(cam)
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02
	# Makinist koltuğu etkileşim alanı
	_seat_area = Area3D.new()
	_seat_area.name = "Ctl_sit"
	_seat_area.collision_layer = 2
	_seat_area.collision_mask = 0
	var sc := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(0.7, 1.3, 0.7)
	sc.shape = sb
	_seat_area.add_child(sc)
	_seat_area.set_meta("action", "sit")
	_seat_area.set_meta("label", "Makinist koltuğuna otur")
	var eye := train.visual.eye_node
	if eye:
		eye.get_parent().add_child(_seat_area)
		_seat_area.position = eye.position + Vector3(0, -0.6, 0.15)
	visible = false
	process_mode = Node.PROCESS_MODE_PAUSABLE

func can_stand() -> bool:
	return train.is_stopped() and train.is_lever_neutral() and not train.emergency_active() \
		and GameState.phase != GameState.Phase.BRIEFING

## Koltuktan kalk
func stand_up() -> bool:
	if walking:
		return false
	if not can_stand():
		if hud and hud.has_method("push_center_message"):
			hud.push_center_message("Kalkmak için tren tamamen durmalı, kol NÖTR ve acil fren devrede olmamalı", false)
		return false
	train.visual.build_walk_collisions()
	var seat_xf := train.visual.driver_seat_global()
	# Koltuğun sağ yanı (kabin kapısı tarafı): koltuk arkası ile bölme duvarı arası kapsüle dar
	# (v0.4'te oraya doğan oyuncu duvardan salona itiliyordu).
	var pos := seat_xf.origin + seat_xf.basis.x * 0.7 + seat_xf.basis.z * 0.15
	pos.y = seat_xf.origin.y - 1.25 + 0.02
	global_position = pos
	velocity = Vector3.ZERO
	_yaw = train.camera.global_rotation.y if train.camera else 0.0
	_pitch = 0.0
	walking = true
	GameState.walking = true
	visible = true
	train.controls_enabled = false
	cam.current = true
	if train.camera and "look_enabled" in train.camera:
		train.camera.look_enabled = false
	Scoring.log_event("Makinist koltuktan kalktı (yürüme modu)")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("Yürüme modu — WASD yürü · Shift hızlı · Tık/E etkileşim · %s koltuğa dön (koltuk yanında)" % GameState.binding_text("stand_up"))
	mode_changed.emit(true)
	return true

## Koltuğa otur
func sit_down() -> void:
	if not walking:
		return
	if seated_on != null:
		_stand_from_seat()
	walking = false
	GameState.walking = false
	visible = false
	_set_hover(null)
	if train.camera:
		train.camera.current = true
		if "look_enabled" in train.camera:
			train.camera.look_enabled = true
		if train.camera.has_method("recenter"):
			train.camera.recenter()
	cam.current = false
	train.controls_enabled = GameState.phase != GameState.Phase.BRIEFING
	Scoring.log_event("Makinist koltuğa oturdu")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("")
	mode_changed.emit(false)

func near_seat() -> bool:
	if _seat_area == null:
		return false
	return global_position.distance_to(_seat_area.global_position) < 1.2

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("stand_up") and not GameState.paused:
		if walking and seated_on != null:
			_stand_from_seat()
			get_viewport().set_input_as_handled()
			return
		if walking:
			if near_seat():
				sit_down()
			elif hud and hud.has_method("push_center_message"):
				hud.push_center_message("Koltuğa dönmek için makinist koltuğunun yanına gelin", false)
		else:
			stand_up()
		get_viewport().set_input_as_handled()
		return
	if not walking:
		return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or GameState.auto_test_mode):
		_yaw -= event.relative.x * SENS * Settings.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * SENS * Settings.mouse_sensitivity, deg_to_rad(-80), deg_to_rad(80))
	if (event.is_action_pressed("interact") or event.is_action_pressed("doors_right")):
		if seated_on != null:
			_stand_from_seat()
			get_viewport().set_input_as_handled()
			return
		if _hover:
			_activate(str(_hover.get_meta("action")))
			get_viewport().set_input_as_handled()

func _activate(action: String) -> void:
	match action:
		"sit":
			sit_down()
		"cab_door":
			train.visual.set_cab_door(not train.visual.cab_door_open)
			AudioManager.play_click()
		"seat_sit":
			_sit_on_seat(_hover.get_meta("seat") as Node3D)
		"inspect":
			_inspect(str(_hover.get_meta("kind")), str(_hover.get_meta("label")))
		_:
			pass

## Boş yolcu koltuğuna oturma: kamera koltuk üstüne, koridora dönük; X/E ile kalkılır
func _sit_on_seat(seat: Node3D) -> void:
	if seat == null or seated_on != null:
		return
	# Koltuk dolu mu? (SeatPos altında yolcu modeli var mı)
	for ch in seat.get_children():
		if ch is Node3D and not (ch is Area3D) and ch.visible:
			if hud and hud.has_method("push_center_message"):
				hud.push_center_message("Bu koltuk dolu", false)
			return
	seated_on = seat
	_seat_return = global_position
	_seat_yaw = _yaw
	var xf := seat.global_transform
	# Koltuk yüzeyinden 0,62 m yukarı, 0,08 m geri; koridora (koltuğun -Z'si) bakış
	global_position = xf.origin + Vector3(0, -0.4, 0) + xf.basis.z * 0.1
	var fwd := -xf.basis.z
	_yaw = atan2(-fwd.x, -fwd.z)
	_pitch = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	Scoring.log_event("Yolcu koltuğuna oturuldu")
	if hud and hud.has_method("set_hint"):
		hud.set_hint("Koltukta oturuyorsunuz — etrafa bakın · %s ya da E: kalk" % GameState.binding_text("stand_up"))
	_set_hover(null)

func _stand_from_seat() -> void:
	if seated_on == null:
		return
	seated_on = null
	collision_mask = 1
	global_position = _seat_return
	_yaw = _seat_yaw
	velocity = Vector3.ZERO
	if hud and hud.has_method("set_hint"):
		hud.set_hint("Yürüme modu — WASD yürü · Shift hızlı · Tık/E etkileşim · %s koltuğa dön (koltuk yanında)" % GameState.binding_text("stand_up"))

func _inspect(kind: String, label: String) -> void:
	var txt := label
	var main := get_tree().current_scene
	match kind:
		"pis":
			var pis_l: Array = train.visual._pis_labels
			txt = "Yolcu bilgi ekranı: \"%s\"" % (str(pis_l[0].text) if pis_l.size() > 0 else "")
		"routemap":
			var names: Array[String] = []
			for st in GameState.route.stations:
				names.append(str(st["short"]))
			txt = "Hat 4 güzergâhı: " + " → ".join(names) + "  ·  Son durak: " + GameState.route.terminus
		"emergency_release":
			txt = "Acil kapı açma kolu — mühürlü. Yalnızca tren durduğunda ve tehlike hâlinde kullanılır."
		"intercom":
			txt = "Acil çağrı butonu: yolcu-makinist konuşma hattı. (Test: hat çalışıyor, merkez dinlemede.)"
			if main and main.has_node("Traffic"):
				main.get_node("Traffic")._say("Merkez: %s, vagon interkom testi alındı." % str(GameState.mission.get("service_number", "")), false, "radio_ack")
	if hud and hud.has_method("push_center_message"):
		hud.push_center_message(txt, false)
	AudioManager.play_click()

func _physics_process(delta: float) -> void:
	if not walking or GameState.paused:
		return
	rotation.y = _yaw
	if seated_on != null:
		# Oturma: hareket yok, sadece bakış (yaw ±100° koltuk yönüne göre sınırlı değil; serbest)
		cam.position = Vector3(0, EYE_H - 0.42, 0)
		cam.rotation = Vector3(_pitch, 0, 0)
		return
	var input := Vector3.ZERO
	if Input.is_action_pressed("throttle_up"):
		input.z -= 1.0
	if Input.is_action_pressed("throttle_down"):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	var speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	var dir := (global_transform.basis * input).normalized() if input.length() > 0.0 else Vector3.ZERO
	var v := velocity
	v.x = dir.x * speed
	v.z = dir.z * speed
	if not is_on_floor():
		v.y -= 9.8 * delta
	else:
		v.y = -0.5
	velocity = v
	# Basamak tırmanma: yatay hareket engelleniyorsa (geçiş plakası, eşik, zemin yükseklik farkı)
	# 0,32 m'ye kadar yukarı adım dene (CharacterBody3D dik basamakları kendiliğinden aşamaz).
	if dir.length() > 0.0 and is_on_floor():
		var motion := Vector3(v.x, 0, v.z) * delta
		if test_move(global_transform, motion):
			var up := Vector3.UP * STEP_H
			if not test_move(global_transform, up) and not test_move(global_transform.translated(up), motion):
				global_position += up
	move_and_slide()
	# Zemin emniyeti: oyuncu bir vagonun sınırları içindeyken zeminin altına inmişse (çarpışma
	# boşluğu) zemine geri al — görünmez eşik/duvar oluşmasın.
	var car := _nearest_car()
	if car:
		var lp := car.to_local(global_position)
		if absf(lp.x) < 1.35 and absf(lp.z) < 10.95 and lp.y < TrainVisual.FLOOR_Y - 0.08 and lp.y > TrainVisual.FLOOR_Y - 1.2:
			lp.y = TrainVisual.FLOOR_Y + 0.03
			global_position = car.to_global(lp)
			velocity.y = 0.0
	# Düşme koruması: vagon zemininin çok altına inince koltuğa dön
	var seat := train.visual.driver_seat_global()
	if global_position.y < seat.origin.y - 1.25 - 1.5:
		global_position = seat.origin + seat.basis.x * 0.7 + seat.basis.z * 0.15 + Vector3(0, -1.23, 0)
		velocity = Vector3.ZERO
	# Kamera: baş sallanması
	if dir.length() > 0.0 and is_on_floor():
		_bob += delta * (9.0 if speed > 2.0 else 6.5)
	cam.position = Vector3(0, EYE_H + sin(_bob) * 0.012 * Settings.camera_sway, 0)
	cam.rotation = Vector3(_pitch, 0, sin(_bob * 0.5) * 0.004 * Settings.camera_sway)
	_update_hover()

func _nearest_car() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for c in train.cars:
		var d: float = c.global_position.distance_squared_to(global_position)
		if d < bd:
			bd = d
			best = c
	return best

func _update_hover() -> void:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.2)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var a: Area3D = null
	if not hit.is_empty():
		var c := hit["collider"] as Area3D
		if c and c.has_meta("action") and str(c.get_meta("action")) in ["sit", "cab_door", "seat_sit", "inspect"]:
			a = c
	_set_hover(a)

func _set_hover(a: Area3D) -> void:
	if _hover == a:
		return
	_hover = a
	if hud and hud.has_method("set_crosshair_label"):
		var txt := ""
		if _hover:
			txt = str(_hover.get_meta("label")) + "  [Tık / E]"
		hud.set_crosshair_label(txt)
