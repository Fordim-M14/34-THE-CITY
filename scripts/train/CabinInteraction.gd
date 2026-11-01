class_name CabinInteraction
extends Node
## CabinInteraction — kabindeki fiziksel kontrollerle fare etkileşimi.
## Fare yakalıyken ekran merkezinden (nişangâh), serbestken imleçten ışın atılır;
## bakılan kontrol vurgulanır ve HUD'da adı gösterilir. Sol tık: işlem, tekerlek: kol.

var train: TrainController
var hud: Node
var hovered: Area3D
var _orig_mats: Dictionary = {}
var _highlight: StandardMaterial3D
var enabled: bool = true
var screen_brightness: float = 0.65

func setup(p_train: TrainController, p_hud: Node) -> void:
	train = p_train
	hud = p_hud
	_highlight = StandardMaterial3D.new()
	_highlight.albedo_color = Color(1, 1, 1)
	_highlight.emission_enabled = true
	_highlight.emission = Color(1.0, 0.9, 0.5)
	_highlight.emission_energy_multiplier = 1.5

func _physics_process(_delta: float) -> void:
	if not enabled or GameState.paused or GameState.phase == GameState.Phase.BRIEFING or not train.controls_enabled:
		_set_hovered(null)
		return
	var cam := train.camera
	if cam == null:
		return
	var vp := cam.get_viewport()
	var screen_pos: Vector2
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		screen_pos = vp.get_visible_rect().size * 0.5
	else:
		screen_pos = vp.get_mouse_position()
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2.5)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_set_hovered(null)
		return
	var area := hit["collider"] as Area3D
	if area == null or not area.has_meta("action"):
		_set_hovered(null)
		return
	_set_hovered(area)
	hovered.set_meta("hit_pos", hit["position"])

func _set_hovered(a: Area3D) -> void:
	if hovered == a:
		return
	if hovered and hovered.has_meta("mesh"):
		var mesh: MeshInstance3D = hovered.get_meta("mesh")
		if is_instance_valid(mesh):
			mesh.material_override = null
	hovered = a
	if hovered and hovered.has_meta("mesh"):
		var mesh2: MeshInstance3D = hovered.get_meta("mesh")
		if is_instance_valid(mesh2):
			mesh2.material_override = _highlight
	if hud and hud.has_method("set_crosshair_label"):
		var txt := ""
		if hovered:
			txt = str(hovered.get_meta("label"))
			var action := str(hovered.get_meta("action"))
			var key := _key_hint(action)
			if key != "":
				txt += "  [%s]" % key
		hud.set_crosshair_label(txt)

func _key_hint(action: String) -> String:
	match action:
		"lever": return "W/S"
		"doors_left_open", "doors_left_close": return GameState.binding_text("doors_left")
		"doors_right_open", "doors_right_close": return GameState.binding_text("doors_right")
		"emergency_reset": return "Shift+R"
		"mmi_next": return GameState.binding_text("mmi_next")
		"cab_door": return "Tık"
		"knob_brightness": return "Tekerlek"
	if GameState.DEFAULT_BINDINGS.has(action):
		return GameState.binding_text(action)
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if hovered == null or not enabled or GameState.paused:
		return
	if event.is_action_pressed("interact"):
		_activate(str(hovered.get_meta("action")))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and str(hovered.get_meta("action")) == "lever":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			train.set_lever(snappedf(train.lever + 0.1, 0.1))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			train.set_lever(snappedf(train.lever - 0.1, 0.1))
	elif event is InputEventMouseButton and event.pressed and str(hovered.get_meta("action")) == "knob_brightness":
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			screen_brightness = clampf(screen_brightness + 0.1, 0.3, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			screen_brightness = clampf(screen_brightness - 0.1, 0.3, 1.0)
		train.visual.set_screen_brightness(screen_brightness)
		AudioManager.play_click()

func _activate(action: String) -> void:
	match action:
		"lever":
			# Tıklanan nokta kol pivotunun önünde mi (çekiş) arkasında mı (fren)
			var hit: Vector3 = hovered.get_meta("hit_pos")
			var local := hovered.to_local(hit)
			if local.z < 0.0:
				train.set_lever(snappedf(train.lever + 0.25, 0.25))
			else:
				train.set_lever(snappedf(train.lever - 0.25, 0.25))
		"reverser": train.cycle_reverser()
		"doors_left_open": train.doors.request_open("left")
		"doors_left_close": train.doors.request_close("left")
		"doors_right_open": train.doors.request_open("right")
		"doors_right_close": train.doors.request_close("right")
		"headlights": train.toggle_headlights()
		"cabin_light": train.toggle_cabin_light()
		"horn": train.horn()
		"acknowledge":
			train.acknowledge()
			var main := get_parent()
			if main.has_node("Traffic"):
				main.get_node("Traffic").acknowledge()
			if main.has_node("Faults"):
				main.get_node("Faults").acknowledge()
		"emergency_brake": train.trigger_emergency(TrainController.EmergencyReason.MANUAL)
		"emergency_reset": train.reset_emergency()
		"mmi_next":
			var main2 := get_parent()
			if main2.has_node("MMI"):
				main2.get_node("MMI").next_page()
		"cctv_toggle":
			var m3 := get_parent()
			if m3.has_node("CCTV"):
				m3.get_node("CCTV").toggle()
		"cctv_next":
			var m4 := get_parent()
			if m4.has_node("CCTV"):
				m4.get_node("CCTV").next_camera()
		"pis_announce":
			var m5 := get_parent()
			if m5.has_node("PIS"):
				m5.get_node("PIS").manual_announce()
		"radio_ptt":
			var m6 := get_parent()
			if m6.has_node("Traffic"):
				m6.get_node("Traffic").driver_call()
		"cab_door":
			train.visual.set_cab_door(not train.visual.cab_door_open)
		"knob_brightness":
			pass
		_:
			if action.begins_with("sw_"):
				var sid := action.trim_prefix("sw_")
				var st := train.visual.toggle_switch(sid)
				match sid:
					"headlight_mode": train.visual.set_high_beam(st)
					"pis_lang":
						var m7 := get_parent()
						if m7.has_node("PIS"):
							m7.get_node("PIS").set_bilingual(st)
					"wiper":
						pass
	if train.visual.has_method("press_button"):
		train.visual.press_button(action)
	AudioManager.play_click()
