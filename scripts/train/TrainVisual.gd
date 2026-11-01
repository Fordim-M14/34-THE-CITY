class_name TrainVisual
extends Node3D
## TrainVisual v4 — ARS T-400 dizisi Blender'da modellenmiş GLB'lerden kurulur
## (assets/models/t400_front.glb, t400_mid.glb). Kabin kontrolleri GLB'deki adlandırılmış
## düğümlerden bulunur (Ctl_lever, Ctl_reverser, Btn_*, Sw_*, Knob_*, Lamp_*, Speedo_Needle,
## MMI_Screen, CCTV_Screen, Radio_Display, Door_L/R_i_a/b, Headlight_L/R, Cam_Eye, CabinLight,
## InteriorLight_*, Dest_*, PIS_*, RouteMap_*, AdPanel_*, SeatPos_*, CabDoorPivot, CCTV_Cam_*).
## v4: PBR malzeme kütüphanesi tüm trene uygulanır; statik iç mekân çarpışmaları (yürüme modu);
## kabin kapısı menteşesi; yolcu bilgi ekranları ve hat haritası; CCTV ekranı dokusu.
## Dış API (TrainController/TrainDoors/CabinInteraction için) v3 ile uyumludur.

const CAR_WIDTH := 2.85
const FLOOR_Y := 1.1
const ROOF_Y := 3.55
const DOOR_H := 1.95
const DOOR_SLIDE := 0.66
const FRONT_GLB := "res://assets/models/t400_front.glb"
const MID_GLB := "res://assets/models/t400_mid.glb"

var camera: Camera3D
var eye_node: Node3D
var door_panels_left: Array = []
var door_panels_right: Array = []
var controls: Array[Area3D] = []
var lamp_mats: Dictionary = {}
var seat_positions: Array = []        # [{car: int, node: Node3D}]
var cctv_cam_nodes: Array = []        # [{car: int, node: Node3D, kind: String}]
var cab_door_pivot: Node3D
var cab_door_open: bool = false
var _lever_node: Node3D
var _lever_base: Basis
var _reverser_node: Node3D
var _reverser_base: Basis
var _speedo_needle: Node3D
var _needle_base: Basis
var _spot_lights: Array = []
var _cabin_light: OmniLight3D
var _cabin_strip_mat: StandardMaterial3D
var _emergency_mat: StandardMaterial3D
var _headlight_mats: Array = []
var _mmi_mesh: MeshInstance3D
var _mmi_mat: StandardMaterial3D
var _cctv_mesh: MeshInstance3D
var _cctv_mat: StandardMaterial3D
var _radio_label: Label3D
var _speed_digital: Label3D
var _dest_labels: Array[Label3D] = []
var _pis_labels: Array[Label3D] = []
var _btn_nodes: Dictionary = {}
var _btn_rest: Dictionary = {}
var _sw_nodes: Dictionary = {}
var _sw_state: Dictionary = {}
var _knob_node: Node3D
var _knob_base: Basis
var _fan_hub: Node3D
var _cars: Array[Node3D] = []
var _models: Array[Node3D] = []
var _door_colliders: Array = []
var _signal_lamp_timer := 0.0

static var _lamp_colors := {
	"doors": Color(0.1, 0.9, 0.3), "emergency": Color(1.0, 0.1, 0.1), "atp": Color(1.0, 0.75, 0.1),
	"traction": Color(1.0, 0.75, 0.1), "fault": Color(1.0, 0.45, 0.1), "message": Color(0.2, 0.5, 1.0),
}

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

# ---------------------------------------------------------------------------

func build(car_count: int, _car_length: float) -> Array[Node3D]:
	var front_scene: PackedScene = load(FRONT_GLB)
	var mid_scene: PackedScene = load(MID_GLB)
	for i in car_count:
		var is_front := i == 0
		var is_rear := i == car_count - 1
		var car := Node3D.new()
		car.name = "Car%d" % i
		add_child(car)
		var model: Node3D = (front_scene if (is_front or is_rear) else mid_scene).instantiate()
		model.name = "Model"
		car.add_child(model)
		if is_rear and not is_front:
			model.rotation.y = PI
		MaterialLib.apply_to(model)
		_setup_doors(model, is_rear and not is_front)
		_setup_lights(model, car, is_front, is_rear and not is_front)
		_setup_destination(model, is_front)
		_setup_interior_lights(model, i == 0)
		_setup_saloon(model, i)
		if is_front:
			_setup_cabin(model, car)
		_cars.append(car)
		_models.append(model)
	return _cars

func _find(root: Node, name: String) -> Node:
	return root.find_child(name, true, false)

func _setup_doors(model: Node3D, mirrored: bool) -> void:
	for i in 3:
		for tag in ["L", "R"]:
			var a := _find(model, "Door_%s_%d_a" % [tag, i]) as Node3D
			var b := _find(model, "Door_%s_%d_b" % [tag, i]) as Node3D
			if a == null or b == null:
				continue
			# [ileri kanat (-Z yönüne açılır), geri kanat (+Z yönüne açılır)]
			var pair := [b, a]
			var physical_left: bool = (tag == "L") != mirrored
			if physical_left:
				door_panels_left.append(pair)
			else:
				door_panels_right.append(pair)
			# Kapı kanadı çarpışması (yürüme modu: kapalı kapıdan düşülmez)
			for leaf in [a, b]:
				var sb := StaticBody3D.new()
				sb.collision_layer = 1
				sb.collision_mask = 0
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.06, DOOR_H, 0.64)
				cs.shape = bs
				sb.add_child(cs)
				leaf.add_child(sb)
				_door_colliders.append(sb)

func _setup_lights(model: Node3D, car: Node3D, is_front: bool, is_rear_rotated: bool) -> void:
	for tag in ["L", "R"]:
		var e := _find(model, "Headlight_" + tag) as Node3D
		if e == null:
			continue
		if is_front:
			var spot := SpotLight3D.new()
			spot.light_color = Color(1.0, 0.97, 0.9)
			spot.light_energy = 12.0
			spot.spot_range = 140.0
			spot.spot_angle = 24.0
			spot.spot_attenuation = 0.7
			spot.shadow_enabled = Settings.headlight_shadows()
			spot.shadow_bias = 0.08
			e.add_child(spot)
			_spot_lights.append(spot)
			var fill := SpotLight3D.new()
			fill.light_color = Color(1.0, 0.95, 0.85)
			fill.light_energy = 3.0
			fill.spot_range = 45.0
			fill.spot_angle = 55.0
			fill.shadow_enabled = false
			e.add_child(fill)
			_spot_lights.append(fill)
	if is_rear_rotated:
		for n in model.find_children("HeadLens_*", "MeshInstance3D", true, false):
			n.material_override = _emissive(Color(1.0, 0.1, 0.08), 2.5)
		for n in model.find_children("TailLens_*", "MeshInstance3D", true, false):
			n.material_override = _emissive(Color(1.0, 0.97, 0.85), 3.0)
		for n in model.find_children("TopLens_*", "MeshInstance3D", true, false):
			n.material_override = _emissive(Color(1.0, 0.1, 0.08), 1.5)
	elif is_front:
		for n in model.find_children("HeadLens_*", "MeshInstance3D", true, false):
			var m := _emissive(Color(1.0, 0.97, 0.85), 6.0)
			n.material_override = m
			_headlight_mats.append(m)
		for n in model.find_children("TopLens_*", "MeshInstance3D", true, false):
			var m2 := _emissive(Color(1.0, 0.97, 0.85), 5.0)
			n.material_override = m2
			_headlight_mats.append(m2)

func _setup_destination(model: Node3D, _is_front: bool) -> void:
	for n in model.find_children("Dest_*", "MeshInstance3D", true, false):
		var lbl := Label3D.new()
		lbl.text = "4"
		lbl.font_size = 40
		lbl.pixel_size = 0.003
		lbl.modulate = Color(1.0, 0.6, 0.1)
		lbl.outline_size = 0
		lbl.double_sided = false
		n.add_child(lbl)
		lbl.rotation_degrees = Vector3(-90, 0, 0)
		lbl.position = Vector3(0, 0.004, 0)
		_dest_labels.append(lbl)

func _setup_interior_lights(model: Node3D, enable: bool) -> void:
	if not enable or not Settings.interior_lights():
		return
	var k := 0
	for e in model.find_children("InteriorLight_*", "Node3D", true, false):
		if k % 2 == 1:
			k += 1
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(0.95, 0.97, 1.0)
		l.light_energy = 1.2
		l.omni_range = 4.5
		l.shadow_enabled = false
		e.add_child(l)
		k += 1

## Salon: PIS LED ekranları, hat haritaları, reklam panoları, koltuk/kamera noktaları
func _setup_saloon(model: Node3D, car_index: int) -> void:
	var pis_mat := _emissive(Color(0.02, 0.02, 0.02), 0.0)
	pis_mat.albedo_color = Color(0.02, 0.02, 0.025)
	for n in model.find_children("PIS_*", "MeshInstance3D", true, false):
		n.material_override = pis_mat
		var lbl := Label3D.new()
		lbl.text = "ARS · HAT 4"
		lbl.font_size = 30
		lbl.pixel_size = 0.0028
		lbl.modulate = Color(1.0, 0.62, 0.12)
		lbl.outline_size = 0
		lbl.double_sided = false
		lbl.width = 300
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.add_child(lbl)
		lbl.rotation_degrees = Vector3(-90, 0, 0)
		lbl.position = Vector3(0, 0.003, 0)
		# Ekran genişliği (mesh AABB'nin en uzun yatay kenarı) — uzun metin ekrana sığacak şekilde ölçeklenir
		var sz: Vector3 = (n as MeshInstance3D).get_aabb().size
		lbl.set_meta("avail_w", maxf(sz.x, sz.z) - 0.06)
		_pis_labels.append(lbl)
	var rm := RouteMapFactory.route_map_texture()
	var rm_mat := StandardMaterial3D.new()
	rm_mat.albedo_texture = rm
	rm_mat.roughness = 0.35
	for n in model.find_children("RouteMap_*", "MeshInstance3D", true, false):
		n.material_override = rm_mat
		RouteMapFactory.add_route_labels(n)
	var k := 0
	for n in model.find_children("AdPanel_*", "MeshInstance3D", true, false):
		var am := StandardMaterial3D.new()
		am.albedo_texture = RouteMapFactory.ad_texture((k + car_index) % RouteMapFactory.AD_COUNT)
		am.roughness = 0.4
		n.material_override = am
		RouteMapFactory.add_ad_labels(n, (k + car_index) % RouteMapFactory.AD_COUNT)
		k += 1
	for n in model.find_children("SeatPos_*", "Node3D", true, false):
		seat_positions.append({"car": car_index, "node": n})
		# Yürüme modu: boş koltuğa oturma alanı
		var a := Area3D.new()
		a.name = "Ctl_seat"
		a.collision_layer = 2
		a.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.44, 0.5, 0.44)
		cs.shape = bs
		a.add_child(cs)
		a.set_meta("action", "seat_sit")
		a.set_meta("label", "Koltuğa otur")
		a.set_meta("seat", n)
		n.add_child(a)
	# İncelenebilir nesneler: PIS ekranları, hat haritaları, kapı üstü acil açma kolları, interkom
	for n in model.find_children("PIS_*", "MeshInstance3D", true, false):
		_add_inspect(n, Vector3(0.9, 0.25, 0.2), "Yolcu bilgi ekranı", "pis")
	for n in model.find_children("RouteMap_*", "MeshInstance3D", true, false):
		_add_inspect(n, Vector3(1.4, 0.25, 0.2), "Hat haritası", "routemap")
	for i in 3:
		for tag in ["L", "R"]:
			var a2 := _find(model, "Door_%s_%d_a" % [tag, i]) as Node3D
			if a2 == null:
				continue
			var sx := -1.0 if tag == "L" else 1.0
			var hot := Node3D.new()
			hot.position = Vector3(sx * 1.3, FLOOR_Y + 2.2, a2.position.z - 0.33 - 0.85)
			model.add_child(hot)
			_add_inspect(hot, Vector3(0.2, 0.2, 0.2), "Acil kapı açma kolu (mühürlü)", "emergency_release")
	var ic := Node3D.new()
	ic.position = Vector3(1.33, FLOOR_Y + 1.35, -(0.5 if car_index % 2 == 0 else 0.0) - 1.0)
	model.add_child(ic)
	_add_inspect(ic, Vector3(0.15, 0.3, 0.25), "Acil çağrı butonu (makinistle konuşma)", "intercom")
	for n in model.find_children("CCTV_Cam_*", "Node3D", true, false):
		cctv_cam_nodes.append({"car": car_index, "node": n, "kind": "saloon"})
	# Vagon içi tavan CCTV kubbeleri koyu cam
	for n in model.find_children("CCTVDome_*", "MeshInstance3D", true, false):
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.05, 0.05, 0.06, 0.75)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.roughness = 0.05
		dm.metallic = 0.2
		n.material_override = dm

func _setup_cabin(model: Node3D, car: Node3D) -> void:
	eye_node = _find(model, "Cam_Eye") as Node3D
	_lever_node = _find(model, "Ctl_lever") as Node3D
	_reverser_node = _find(model, "Ctl_reverser") as Node3D
	_speedo_needle = _find(model, "Speedo_Needle") as Node3D
	_knob_node = _find(model, "Knob_brightness") as Node3D
	_fan_hub = _find(model, "Fan_Hub") as Node3D
	cab_door_pivot = _find(model, "CabDoorPivot") as Node3D
	if _lever_node:
		_lever_base = _lever_node.transform.basis
	if _reverser_node:
		_reverser_base = _reverser_node.transform.basis
	if _speedo_needle:
		_needle_base = _speedo_needle.transform.basis
	if _knob_node:
		_knob_base = _knob_node.transform.basis
	# MMI ekranı: gölgesiz dokulu malzeme
	_mmi_mesh = _find(model, "MMI_Screen") as MeshInstance3D
	_mmi_mat = StandardMaterial3D.new()
	_mmi_mat.albedo_color = Color(0.02, 0.05, 0.07)
	_mmi_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _mmi_mesh:
		_mmi_mesh.material_override = _mmi_mat
	# CCTV monitörü
	_cctv_mesh = _find(model, "CCTV_Screen") as MeshInstance3D
	_cctv_mat = StandardMaterial3D.new()
	_cctv_mat.albedo_color = Color(0.01, 0.012, 0.015)
	_cctv_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _cctv_mesh:
		_cctv_mesh.material_override = _cctv_mat
	# Telsiz ekranı
	var rd := _find(model, "Radio_Display") as MeshInstance3D
	if rd:
		rd.material_override = _emissive(Color(0.02, 0.06, 0.03), 0.3)
		_radio_label = Label3D.new()
		_radio_label.text = "KANAL 4 · MERKEZ"
		_radio_label.font_size = 20
		_radio_label.pixel_size = 0.0011
		_radio_label.modulate = Color(0.5, 1.0, 0.55)
		_radio_label.rotation_degrees = Vector3(-90, 0, 0)
		_radio_label.position = Vector3(0, 0.002, 0)
		rd.add_child(_radio_label)
	# Dijital hız
	var sd := _find(model, "SpeedDigital") as MeshInstance3D
	if sd:
		sd.material_override = _emissive(Color(0.02, 0.05, 0.06), 0.4)
		_speed_digital = Label3D.new()
		_speed_digital.text = "0"
		_speed_digital.font_size = 48
		_speed_digital.pixel_size = 0.001
		_speed_digital.modulate = Color(0.4, 1.0, 0.6)
		sd.add_child(_speed_digital)
		_speed_digital.rotation_degrees = Vector3(-90, 0, 0)
		_speed_digital.position = Vector3(0, 0.003, 0)
	# İkaz lambaları
	for id in _lamp_colors:
		var lamp := _find(model, "Lamp_" + id) as MeshInstance3D
		if lamp:
			var m := _emissive(_lamp_colors[id], 0.0)
			m.albedo_color = _lamp_colors[id] * 0.2
			lamp.material_override = m
			lamp_mats[id] = m
	# Acil fren mantarı lambası
	var mush := _find(model, "Btn_emergency_brake") as MeshInstance3D
	if mush:
		_emergency_mat = _emissive(Color(1.0, 0.1, 0.1), 0.0)
		_emergency_mat.albedo_color = Color(0.7, 0.08, 0.08)
		mush.material_override = _emergency_mat
	# Kabin ışığı
	var cl := _find(model, "CabinLight") as Node3D
	if cl:
		_cabin_light = OmniLight3D.new()
		_cabin_light.light_color = Color(0.9, 0.93, 1.0)
		_cabin_light.light_energy = 0.35
		_cabin_light.omni_range = 3.5
		_cabin_light.shadow_enabled = Settings.quality >= 3
		cl.add_child(_cabin_light)
	var strip := _find(model, "CabLightStrip") as MeshInstance3D
	if strip:
		_cabin_strip_mat = _emissive(Color(0.95, 0.97, 1.0), 1.2)
		strip.material_override = _cabin_strip_mat
	# Etkileşimli öğeler: düğmeler, şalterler, potansiyometre, kol, yön kolu, MMI, CCTV, kabin kapısı
	for n in model.find_children("Btn_*", "MeshInstance3D", true, false):
		var action := n.name.trim_prefix("Btn_")
		if action.begins_with("mmi_"):
			action = "mmi_next"
		_btn_nodes[n.name] = n
		_btn_rest[n.name] = n.position
		var size := Vector3(0.09, 0.08, 0.09)
		if action == "emergency_brake":
			size = Vector3(0.16, 0.12, 0.16)
		elif action == "radio_ptt":
			size = Vector3(0.06, 0.05, 0.18)
		_add_control(n, action, _label_for(action), size, Vector3.ZERO, n)
	for n in model.find_children("Sw_*", "Node3D", true, false):
		var sid := str(n.name).trim_prefix("Sw_")
		_sw_nodes[sid] = n
		_sw_state[sid] = false
		var rocker := n.get_child(0) if n.get_child_count() > 0 else null
		_add_control(n, "sw_" + sid, _label_for("sw_" + sid), Vector3(0.07, 0.06, 0.1), Vector3(0, 0.01, 0), rocker as MeshInstance3D)
	if _knob_node:
		_add_control(_knob_node, "knob_brightness", "Ekran parlaklığı (tekerlek)", Vector3(0.06, 0.06, 0.06), Vector3.ZERO, _knob_node as MeshInstance3D)
	if _lever_node:
		_add_control(_lever_node, "lever", "Çekiş/Fren kolu (tık: ön=çekiş, arka=fren · tekerlek)", Vector3(0.3, 0.42, 0.5), Vector3(0, 0.18, 0), null)
	if _reverser_node:
		_add_control(_reverser_node, "reverser", "Yön kolu", Vector3(0.2, 0.28, 0.3), Vector3(0, 0.1, 0), null)
	if _mmi_mesh:
		_add_control(_mmi_mesh, "mmi_next", "MMI sayfa", Vector3(0.46, 0.08, 0.34), Vector3.ZERO, null)
	if _cctv_mesh:
		_add_control(_cctv_mesh, "cctv_next", "CCTV kamera değiştir", Vector3(0.34, 0.08, 0.26), Vector3.ZERO, null)
	if cab_door_pivot:
		# Etkileşim alanı kapı açıklığında sabit (pivotun ebeveyninde), kapı dönse de aynı yerde
		var door_hot := Node3D.new()
		door_hot.position = cab_door_pivot.position + Vector3(0.36, 0, 0)
		cab_door_pivot.get_parent().add_child(door_hot)
		_add_control(door_hot, "cab_door", "Kabin kapısı", Vector3(0.8, 2.0, 0.5), Vector3(0.0, 1.0, 0), null)
		# Kapı çarpışması (pivota bağlı, kapıyla döner)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.70, 1.95, 0.05)
		cs.shape = bs
		cs.position = Vector3(0.35, 0.975, 0)
		sb.add_child(cs)
		cab_door_pivot.add_child(sb)
	_setup_cabin_labels(model)
	# Kamera
	camera = Camera3D.new()
	camera.name = "CabinCamera"
	camera.fov = Settings.fov
	camera.near = 0.04
	camera.far = 1200.0
	camera.set_script(load("res://scripts/train/CabinCamera.gd"))
	if eye_node:
		eye_node.add_child(camera)
	else:
		car.add_child(camera)
		camera.position = Vector3(-0.3, FLOOR_Y + 1.25, -10.75 + 2.1)

## Düğme etiketleri, kol kademeleri, hız saati rakamları, ARS plakası ve sefer çizelgesi metinleri
func _setup_cabin_labels(model: Node3D) -> void:
	var short := {"doors_left_open": "SOL AÇ", "doors_left_close": "SOL KAPAT", "doors_right_open": "SAĞ AÇ",
		"doors_right_close": "SAĞ KAPAT", "headlights": "FAR", "cabin_light": "KABİN", "horn": "KORNA",
		"acknowledge": "ONAY", "emergency_reset": "RESET", "emergency_brake": "ACİL FREN",
		"cctv_toggle": "CCTV", "cctv_next": "KAM ►", "pis_announce": "ANONS", "radio_ptt": "PTT"}
	for n in model.find_children("Btn_*", "MeshInstance3D", true, false):
		var action := str(n.name).trim_prefix("Btn_")
		if not short.has(action):
			continue
		var l := Label3D.new()
		l.text = short[action]
		l.font_size = 20
		l.pixel_size = 0.0011
		l.modulate = Color(0.92, 0.92, 0.94)
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.position = Vector3(0, -0.012, 0.055 if action != "emergency_brake" else 0.11)
		if action == "radio_ptt":
			continue
		n.get_parent().add_child(l)
		l.position += n.position
	# Şalter etiketleri
	var sw_lbl := {"headlight_mode": "FAR UZUN", "wiper": "SİLECEK", "cab_fan": "FAN", "pis_lang": "TR / EN"}
	for sid in _sw_nodes:
		var n: Node3D = _sw_nodes[sid]
		var l := Label3D.new()
		l.text = sw_lbl.get(sid, sid.to_upper())
		l.font_size = 18
		l.pixel_size = 0.001
		l.modulate = Color(0.92, 0.92, 0.94)
		l.rotation_degrees = Vector3(-90, 0, 0)
		n.get_parent().add_child(l)
		l.position = n.position + Vector3(0, -0.008, 0.06)
	# Kol kademeleri (P4..0..B7) — yuva sağında
	if _lever_node:
		var holder := Node3D.new()
		holder.position = _lever_node.position + Vector3(0.1, -0.003, 0)
		_lever_node.get_parent().add_child(holder)
		var names := ["B7", "B6", "B5", "B4", "B3", "B2", "B1", "0", "P1", "P2", "P3", "P4"]
		for k in names.size():
			var l := Label3D.new()
			l.text = names[k]
			l.font_size = 14
			l.pixel_size = 0.0008
			l.modulate = Color(0.85, 0.85, 0.88) if names[k] != "0" else Color(1, 1, 1)
			l.rotation_degrees = Vector3(-90, 0, 0)
			l.position = Vector3(0, 0.0, -(k - 7) * 0.028)
			holder.add_child(l)
	# Hız saati rakamları (ibrenin kardeşi, dönmez)
	if _speedo_needle:
		var holder := Node3D.new()
		holder.transform = _speedo_needle.transform
		_speedo_needle.get_parent().add_child(holder)
		for i in 9:
			var ang := deg_to_rad(-135.0 + i * 33.75)
			var l := Label3D.new()
			l.text = str(i * 10)
			l.font_size = 22
			l.pixel_size = 0.0009
			l.modulate = Color(0.1, 0.1, 0.12) if i < 7 else Color(0.75, 0.1, 0.1)
			l.rotation_degrees = Vector3(-90, 0, 0)
			l.position = Vector3(sin(ang) * 0.082, 0.001, -cos(ang) * 0.082)
			holder.add_child(l)
		var unit := Label3D.new()
		unit.text = "km/s"
		unit.font_size = 20
		unit.pixel_size = 0.001
		unit.modulate = Color(0.25, 0.25, 0.3)
		unit.rotation_degrees = Vector3(-90, 0, 0)
		unit.position = Vector3(0, 0.001, 0.045)
		holder.add_child(unit)
		var brand := Label3D.new()
		brand.text = "ARS"
		brand.font_size = 16
		brand.pixel_size = 0.0008
		brand.modulate = Color(0.3, 0.3, 0.35)
		brand.rotation_degrees = Vector3(-90, 0, 0)
		brand.position = Vector3(0, 0.001, -0.05)
		holder.add_child(brand)
	# ARS plakası
	var plate := _find(model, "ARSPlate") as MeshInstance3D
	if plate:
		var l := Label3D.new()
		l.text = "ARS  ·  T-400 \"BOĞAZ\"  ·  01"
		l.font_size = 24
		l.pixel_size = 0.0012
		l.modulate = Color(0.15, 0.1, 0.05)
		l.rotation_degrees = Vector3(0, 180, 0)
		l.position = Vector3(0, 0, -0.003)
		plate.add_child(l)
	# Sefer çizelgesi
	var tt := _find(model, "Timetable") as MeshInstance3D
	if tt and GameState.route:
		var lines := ["ARS · HAT 4 · SEFER %s" % str(GameState.mission.get("service_number", "")), "%s" % GameState.route.direction_label, ""]
		for st in GameState.route.stations:
			var t := GameState.route.schedule_for(int(st["index"]))
			lines.append("%02d:%02d  %s" % [int(t) / 60, int(t) % 60, str(st["short"])])
		var l := Label3D.new()
		l.text = "\n".join(lines)
		l.font_size = 18
		l.pixel_size = 0.00075
		l.modulate = Color(0.1, 0.1, 0.12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.position = Vector3(-0.06, 0.002, -0.02)
		tt.add_child(l)
	# Sigorta panosu etiketi, yangın tüpü etiketi, kapı üstü uyarı plakaları
	_text_on(model, "FuseLabel", "ŞALTER PANOSU · 110 V DC", 16, Color(0.1, 0.1, 0.1), Vector3(-90, 0, 90))
	_text_on(model, "ExtLabel", "YANGIN\nSÖNDÜRÜCÜ\n6 kg ABC", 14, Color(0.9, 0.1, 0.1), Vector3(0, -90, 0))

func _text_on(model: Node3D, node_name: String, text: String, size: int, color: Color, rot: Vector3) -> void:
	var n := _find(model, node_name) as MeshInstance3D
	if n == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.001
	l.modulate = color
	l.rotation_degrees = rot
	l.position = Vector3(-0.004, 0, 0)
	n.add_child(l)

func _label_for(action: String) -> String:
	match action:
		"doors_left_open": return "SOL KAPILAR AÇ"
		"doors_left_close": return "SOL KAPILAR KAPAT"
		"doors_right_open": return "SAĞ KAPILAR AÇ"
		"doors_right_close": return "SAĞ KAPILAR KAPAT"
		"headlights": return "FARLAR"
		"cabin_light": return "KABİN IŞIĞI"
		"horn": return "KORNA"
		"acknowledge": return "ONAY / MERKEZ"
		"emergency_reset": return "ACİL FREN RESET"
		"emergency_brake": return "ACİL FREN"
		"mmi_next": return "MMI SAYFA"
		"cctv_toggle": return "CCTV MONİTÖR AÇ/KAPAT"
		"cctv_next": return "CCTV KAMERA DEĞİŞTİR"
		"pis_announce": return "YOLCU ANONSU (sonraki istasyon)"
		"radio_ptt": return "TELSİZ — MERKEZİ ARA"
		"sw_headlight_mode": return "FAR MODU (KISA / UZUN)"
		"sw_wiper": return "SİLECEK"
		"sw_cab_fan": return "KABİN FANI"
		"sw_pis_lang": return "ANONS DİLİ (TR / TR+EN)"
		"cab_door": return "KABİN KAPISI"
	return action

func _add_inspect(parent: Node3D, size: Vector3, label: String, kind: String) -> void:
	var a := Area3D.new()
	a.name = "Ctl_inspect"
	a.collision_layer = 2
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.set_meta("action", "inspect")
	a.set_meta("label", label)
	a.set_meta("kind", kind)
	parent.add_child(a)

## Etkileşimli öğe: Area3D (katman 2) + kutu çarpışma, meta: action/label/mesh
func _add_control(parent: Node3D, action: String, label: String, size: Vector3, offset: Vector3, mesh: MeshInstance3D) -> void:
	var area := Area3D.new()
	area.name = "Ctl_" + action
	area.position = offset
	area.collision_layer = 2
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	area.add_child(cs)
	area.set_meta("action", action)
	area.set_meta("label", label)
	if mesh:
		area.set_meta("mesh", mesh)
	parent.add_child(area)
	controls.append(area)

## Yürüme modu için statik iç mekân çarpışmaları (bir kez, istendiğinde üretilir)
var _collisions_built := false
func build_walk_collisions() -> void:
	if _collisions_built:
		return
	_collisions_built = true
	for model in _models:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var nm := str(mi.name)
			# StaticNC_*: tavan/asılı ince parçalar (tutamak halkaları, direk kolları, armatürler) — çarpışma yok
			var ok := nm.begins_with("Static_") or nm.ends_with("_Shell") or nm.begins_with("GangPlate") \
				or nm.begins_with("Bulkhead_1") or nm.begins_with("EndWall") or nm.begins_with("CabSeat_") \
				or nm.begins_with("Glass_") or nm.begins_with("GlassCab") or nm.begins_with("Windshield") or nm == "Floor"
			if not ok:
				continue
			if nm.begins_with("Static_Light") or nm.begins_with("Static_Paper") or nm.begins_with("Static_Btn"):
				continue
			mi.create_trimesh_collision()
			for ch in mi.get_children():
				if ch is StaticBody3D:
					ch.collision_layer = 1
					ch.collision_mask = 0

# ---------------------------------------------------------------------------
# Dinamik güncellemeler

func _process(delta: float) -> void:
	if _fan_hub and _sw_state.get("cab_fan", false):
		_fan_hub.rotate_object_local(Vector3(0, 0, 1), delta * 18.0)

func update_lever_visual(lever: float, emergency: bool, reverser: int = 1) -> void:
	if _lever_node:
		_lever_node.transform.basis = _lever_base * Basis(Vector3.RIGHT, deg_to_rad(-lever * 32.0))
	if _reverser_node:
		_reverser_node.transform.basis = _reverser_base * Basis(Vector3.RIGHT, deg_to_rad(-reverser * 28.0))
	if _emergency_mat:
		_emergency_mat.emission_energy_multiplier = 3.0 if emergency else 0.0
	set_lamp("emergency", emergency)

func update_speedo(kmh: float) -> void:
	if _speedo_needle:
		var t := clampf(kmh / 80.0, 0.0, 1.05)
		var ang := deg_to_rad(135.0 - t * 270.0)
		_speedo_needle.transform.basis = _needle_base * Basis(Vector3.UP, ang)
	if _speed_digital:
		_speed_digital.text = str(int(round(kmh)))

func set_lamp(id: String, on: bool, energy: float = 2.5) -> void:
	if lamp_mats.has(id):
		var m: StandardMaterial3D = lamp_mats[id]
		m.emission_energy_multiplier = energy if on else 0.0
		m.albedo_color = _lamp_colors[id] * (1.0 if on else 0.2)

func set_headlights(on: bool) -> void:
	for s in _spot_lights:
		s.visible = on
	for m in _headlight_mats:
		m.emission_energy_multiplier = 6.0 if on else 0.0

func set_high_beam(on: bool) -> void:
	for s in _spot_lights:
		if s.spot_angle < 30.0:
			s.light_energy = 20.0 if on else 12.0
			s.spot_range = 220.0 if on else 140.0

func set_cabin_light(on: bool) -> void:
	if _cabin_light:
		_cabin_light.visible = on
	if _cabin_strip_mat:
		_cabin_strip_mat.emission_energy_multiplier = 1.2 if on else 0.0

func set_destination(text: String) -> void:
	for l in _dest_labels:
		l.text = text

## Salon LED ekranları (kapı üstü)
func set_pis_text(text: String, color: Color = Color(1.0, 0.62, 0.12)) -> void:
	for l in _pis_labels:
		l.text = text
		l.modulate = color
		_fit_label(l)

## Label3D metnini ekrana sığdır (LED yazısı kutunun dışına taşmasın)
func _fit_label(l: Label3D) -> void:
	if not l.has_meta("avail_w"):
		return
	var avail: float = float(l.get_meta("avail_w"))
	var f: Font = l.font if l.font else ThemeDB.fallback_font
	var w: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size
	var k: float = 1.0 if w <= avail or w <= 0.0 else avail / w
	l.scale = Vector3(k, k, 1.0)

func set_radio_text(text: String) -> void:
	if _radio_label:
		_radio_label.text = text

func attach_mmi(mmi: Node) -> void:
	if _mmi_mat and mmi.has_method("get_texture"):
		_mmi_mat.albedo_texture = mmi.get_texture()
		_mmi_mat.albedo_color = Color(1, 1, 1)

func attach_cctv(tex: Texture2D) -> void:
	if _cctv_mat:
		_cctv_mat.albedo_texture = tex
		_cctv_mat.albedo_color = Color(1, 1, 1) if tex else Color(0.01, 0.012, 0.015)

func set_screen_brightness(v: float) -> void:
	if _mmi_mat:
		_mmi_mat.albedo_color = Color(v, v, v) if _mmi_mat.albedo_texture else _mmi_mat.albedo_color
	if _cctv_mat and _cctv_mat.albedo_texture:
		_cctv_mat.albedo_color = Color(v, v, v)
	if _knob_node:
		_knob_node.transform.basis = _knob_base * Basis(Vector3.UP, deg_to_rad(-(v - 0.65) * 300.0))

## Şalter konumu (görsel + durum). Döndürür: yeni durum
func toggle_switch(sid: String) -> bool:
	if not _sw_nodes.has(sid):
		return false
	var st: bool = not _sw_state[sid]
	_sw_state[sid] = st
	var n: Node3D = _sw_nodes[sid]
	var tw := n.create_tween()
	tw.tween_property(n, "rotation_degrees:x", -22.0 if st else 0.0, 0.08)
	return st

func switch_state(sid: String) -> bool:
	return bool(_sw_state.get(sid, false))

## Kabin kapısı aç/kapat (menteşe etrafında döner; yürüme modunda geçiş için)
func set_cab_door(open: bool) -> void:
	if cab_door_pivot == null or cab_door_open == open:
		return
	cab_door_open = open
	var tw := cab_door_pivot.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(cab_door_pivot, "rotation_degrees:y", -168.0 if open else 0.0, 0.7)

## Düğme basılma animasyonu (CabinInteraction çağırır)
func press_button(action: String) -> void:
	for name in _btn_nodes:
		var n: MeshInstance3D = _btn_nodes[name]
		var a: String = str(name).trim_prefix("Btn_")
		if a.begins_with("mmi_"):
			a = "mmi_next"
		if a != action:
			continue
		var rest: Vector3 = _btn_rest[name]
		var tw := n.create_tween()
		tw.tween_property(n, "position", rest + Vector3(0, -0.008, 0), 0.06)
		tw.tween_property(n, "position", rest, 0.12)

func door_world_positions(side: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pairs: Array = door_panels_left if side == "left" else door_panels_right
	for pair in pairs:
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		out.append((a.global_position + b.global_position) * 0.5)
	return out

## Makinist koltuğu dünya konumu (yürüme modundan dönüş için)
func driver_seat_global() -> Transform3D:
	if eye_node:
		return eye_node.global_transform
	return global_transform

func apply_quality() -> void:
	for s in _spot_lights:
		if s.spot_angle < 30.0:
			s.shadow_enabled = Settings.headlight_shadows()
