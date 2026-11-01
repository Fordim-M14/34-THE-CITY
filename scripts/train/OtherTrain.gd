class_name OtherTrain
extends Node3D
## OtherTrain — yapay zekâ metro dizisinin 3B görseli (öndeki sefer, karşı yön seferleri).
## Aynı T-400 GLB'lerinden kurulur; far/stop lambaları, iç ışık malzemeleri, hedef yazısı.
## LOD: 220 m'den uzakta iç mekân (Static_*) gizlenir, 900 m'den uzakta tüm dizi gizlenir.
## Konum: hat ofseti (burun) + yanal ofset (karşı hat için world.opp_x) + yön (dir=-1 ters).

const CAR_LENGTH := 21.5
const CAR_GAP := 0.6

var world: TrackBuilder
var cars: Array[Node3D] = []
var car_count := 4
var lateral := 0.0
var dir := 1
var service := ""
var _interior_nodes: Array = []
var _lod_state := -1
var _head_spot: SpotLight3D
var _dest_labels: Array[Label3D] = []

func build(p_world: TrackBuilder, p_car_count: int, p_lateral: float, p_dir: int, dest_text: String) -> void:
	world = p_world
	car_count = p_car_count
	lateral = p_lateral
	dir = p_dir
	var front_scene: PackedScene = load(TrainVisual.FRONT_GLB)
	var mid_scene: PackedScene = load(TrainVisual.MID_GLB)
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
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var nm := str(mi.name)
			if nm.begins_with("Static_") or nm.begins_with("Seat") or nm.begins_with("PIS") or nm.begins_with("RouteMap") or nm.begins_with("AdPanel"):
				_interior_nodes.append(mi)
			# Kabin kontrolleri vs. gereksiz — görünür kalabilir (ucuz)
		if is_front:
			for n in model.find_children("HeadLens_*", "MeshInstance3D", true, false):
				n.material_override = _emissive(Color(1.0, 0.97, 0.85), 6.0)
			for n in model.find_children("TopLens_*", "MeshInstance3D", true, false):
				n.material_override = _emissive(Color(1.0, 0.97, 0.85), 5.0)
			var e := model.find_child("Headlight_L", true, false) as Node3D
			if e:
				_head_spot = SpotLight3D.new()
				_head_spot.light_color = Color(1.0, 0.97, 0.9)
				_head_spot.light_energy = 8.0
				_head_spot.spot_range = 90.0
				_head_spot.spot_angle = 30.0
				_head_spot.shadow_enabled = false
				_head_spot.position = Vector3(0.82, 0, 0)
				e.add_child(_head_spot)
		elif is_rear:
			for n in model.find_children("HeadLens_*", "MeshInstance3D", true, false):
				n.material_override = _emissive(Color(1.0, 0.1, 0.08), 2.5)
			for n in model.find_children("TopLens_*", "MeshInstance3D", true, false):
				n.material_override = _emissive(Color(1.0, 0.1, 0.08), 1.5)
		for n in model.find_children("Dest_*", "MeshInstance3D", true, false):
			var lbl := Label3D.new()
			lbl.text = dest_text
			lbl.font_size = 40
			lbl.pixel_size = 0.003
			lbl.modulate = Color(1.0, 0.6, 0.1)
			lbl.rotation_degrees = Vector3(-90, 0, 0)
			lbl.position = Vector3(0, 0.004, 0)
			n.add_child(lbl)
			_dest_labels.append(lbl)
		# PIS/CCTV ekran plakaları koyu
		for n in model.find_children("PIS_*", "MeshInstance3D", true, false):
			n.material_override = _emissive(Color(0.02, 0.02, 0.02), 0.0)
		cars.append(car)

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func train_length() -> float:
	return car_count * CAR_LENGTH + (car_count - 1) * CAR_GAP

## nose_offset: burnun hat ofseti (dir=+1: ileri yön; dir=-1: ters yön, burun azalan ofsete bakar)
func place(nose_offset: float, player_offset: float) -> void:
	var dist := absf(nose_offset - player_offset)
	var lod := 0
	if dist > 900.0:
		lod = 2
	elif dist > 220.0:
		lod = 1
	if lod != _lod_state:
		_lod_state = lod
		visible = lod < 2
		for n in _interior_nodes:
			n.visible = lod == 0
		if _head_spot:
			_head_spot.visible = lod == 0
	if lod == 2:
		return
	for i in car_count:
		var center := nose_offset - dir * (CAR_LENGTH * 0.5 + i * (CAR_LENGTH + CAR_GAP))
		var xf := world.get_track_transform(center)
		xf = xf.translated_local(Vector3(lateral, 0.0, 0.0))
		if dir < 0:
			xf.basis = xf.basis * Basis(Vector3.UP, PI)
		cars[i].global_transform = xf
