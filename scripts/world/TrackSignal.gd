class_name TrackSignal
extends Node3D
## TrackSignal v3 — Blender modeli (signal_head.glb) + emissive lamba malzemeleri.
## Trene (+Z tarafına) dönük yerleştirilir. Aspect: red / yellow / green.

var signal_id: String = ""
var signal_type: String = "block"
var track_pos: float = 0.0
var station_id: String = ""
var aspect: String = "red"
var forced_red: bool = false
var forced_yellow: bool = false

var _mats: Dictionary = {}
var _glow: OmniLight3D

const COLORS := {
	"red": Color(1.0, 0.12, 0.08),
	"yellow": Color(1.0, 0.75, 0.1),
	"green": Color(0.1, 1.0, 0.35),
}

func build() -> void:
	var model := MeshUtil.instance_prop("signal_head")
	if model:
		add_child(model)
		for key in COLORS:
			var lamp := model.find_child("Lamp_" + key, true, false) as MeshInstance3D
			if lamp:
				var m := StandardMaterial3D.new()
				m.albedo_color = COLORS[key] * 0.2
				m.emission_enabled = true
				m.emission = COLORS[key]
				m.emission_energy_multiplier = 0.0
				m.roughness = 0.2
				lamp.material_override = m
				_mats[key] = m
	else:
		_build_fallback()
	_glow = OmniLight3D.new()
	_glow.omni_range = 3.0
	_glow.light_energy = 0.8
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 2.9, 0.4)
	add_child(_glow)
	var lbl := Label3D.new()
	lbl.text = signal_id
	lbl.font_size = 36
	lbl.pixel_size = 0.0035
	lbl.modulate = Color(0.1, 0.1, 0.1)
	lbl.position = Vector3(0, 2.2, 0.135)
	add_child(lbl)

func _build_fallback() -> void:
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.2, 0.2, 0.22)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, 2.4, 0.1)
	pm.material = post_mat
	post.mesh = pm
	post.position = Vector3(0, 1.2, 0)
	add_child(post)
	var order := ["green", "yellow", "red"]
	for i in order.size():
		var key: String = order[i]
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[key] * 0.25
		m.emission_enabled = true
		m.emission = COLORS[key]
		m.emission_energy_multiplier = 0.0
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		sm.material = m
		lamp.mesh = sm
		lamp.position = Vector3(0, 2.55 + i * 0.35, 0.14)
		add_child(lamp)
		_mats[key] = m

func set_aspect(a: String) -> void:
	if not COLORS.has(a):
		return
	aspect = a
	for key in _mats:
		var m: StandardMaterial3D = _mats[key]
		m.emission_energy_multiplier = 5.0 if key == a else 0.0
		m.albedo_color = COLORS[key] * (1.0 if key == a else 0.2)
	if _glow:
		_glow.light_color = COLORS[a]

func is_red() -> bool:
	return aspect == "red"
