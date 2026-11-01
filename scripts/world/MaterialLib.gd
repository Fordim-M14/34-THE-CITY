class_name MaterialLib
extends RefCounted
## MaterialLib — PBR malzeme kütüphanesi. Blender'da pişirilmiş doku setlerini
## (assets/textures/<set>_albedo/_normal/_rough.png) GLB'lerdeki malzeme adlarına ve
## prosedürel geometriye uygular. Dokular bir kez yüklenir, malzemeler önbelleklenir.

static var _tex_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

const TEX_DIR := "res://assets/textures/"

## GLB malzeme adı → [doku seti, uv ölçeği, albedo tint, metallic, roughness(çarpan), ekstra]
const BY_NAME := {
	"T400_Paint":        ["paint_metal", 2.0, Color(0.09, 0.56, 0.54), 0.35, 1.0, {"clearcoat": 0.6}],
	"T400_PaintDark":    ["paint_metal", 2.0, Color(0.10, 0.11, 0.12), 0.5, 1.0, {"clearcoat": 0.4}],
	"T400_Metal":        ["metal_brushed", 3.0, Color(0.8, 0.81, 0.83), 1.0, 0.85, {}],
	"T400_Accent":       ["plastic_grain", 3.0, Color(0.95, 0.72, 0.12), 0.1, 0.9, {}],
	"T400_Interior":     ["panel_lines", 1.0, Color(0.84, 0.85, 0.86), 0.05, 1.0, {}],
	"T400_Floor":        ["rubber_floor", 1.5, Color(0.55, 0.55, 0.57), 0.0, 1.0, {}],
	"T400_Seat":         ["seat_pattern", 1.6, Color(0.13, 0.26, 0.5), 0.0, 1.0, {}],
	"T400_SeatCab":      ["seat_fabric", 2.0, Color(0.14, 0.15, 0.17), 0.0, 1.0, {}],
	"T400_Ceiling":      ["ceiling_perforated", 2.0, Color(0.9, 0.9, 0.92), 0.6, 1.0, {}],
	"T400_Desk":         ["rubber_floor", 4.0, Color(0.16, 0.17, 0.19), 0.05, 0.8, {}],
	"T400_Panel":        ["rubber_floor", 6.0, Color(0.13, 0.15, 0.18), 0.1, 0.7, {}],
	"T400_DeskLight":    ["paint_metal", 3.0, Color(0.5, 0.51, 0.53), 0.1, 1.0, {}],
	"T400_PlasticDark":  ["plastic_grain", 4.0, Color(0.13, 0.135, 0.145), 0.0, 1.0, {}],
	"T400_PlasticGrey":  ["plastic_grain", 4.0, Color(0.6, 0.61, 0.62), 0.0, 1.0, {}],
	"T400_Leather":      ["leather", 3.0, Color(0.1, 0.1, 0.11), 0.0, 1.0, {"clearcoat": 0.25}],
	"T400_MetalPainted": ["metal_worn", 3.0, Color(0.45, 0.46, 0.48), 0.3, 1.0, {}],
	"T400_RubberRibbed": ["rubber_ribbed", 3.0, Color(0.5, 0.5, 0.52), 0.0, 1.0, {}],
	"T400_WallPanel":    ["panel_lines", 1.0, Color(0.86, 0.87, 0.88), 0.05, 1.0, {}],
	"T400_FloorDark":    ["rubber_floor", 1.5, Color(0.36, 0.36, 0.38), 0.0, 1.0, {}],
	"T400_InteriorDark": ["plastic_grain", 3.0, Color(0.24, 0.25, 0.27), 0.1, 1.0, {}],
	"T400_MetalDark":    ["metal_worn", 3.0, Color(0.26, 0.27, 0.29), 0.85, 0.9, {}],
	"T400_Rubber":       ["plastic_grain", 6.0, Color(0.07, 0.07, 0.075), 0.0, 1.0, {}],
	"Env_Lining":        ["concrete_lining", 0.5, Color(0.6, 0.6, 0.62), 0.0, 1.0, {}],
	"Env_Concrete":      ["concrete_rough", 0.5, Color(0.78, 0.77, 0.75), 0.0, 1.0, {}],
	"Env_Metal":         ["metal_brushed", 2.0, Color(0.75, 0.76, 0.78), 1.0, 1.0, {}],
	"Env_Galvanized":    ["metal_brushed", 3.0, Color(0.6, 0.62, 0.65), 0.9, 1.3, {}],
}

## Prosedürel geometri için setler (triplanar)
const PROC := {
	"platform_paving":   ["paving", 0.5, Color(0.72, 0.72, 0.7), 0.0, 1.0],
	"tactile":           ["tactile", 1.2, Color(1, 1, 1), 0.0, 1.0],
	"tiles":             ["tiles_small", 0.6, Color(1, 1, 1), 0.0, 1.0],
	"tiles_large":       ["tiles_small", 0.3, Color(1, 1, 1), 0.0, 1.0],
	"concrete":          ["concrete_rough", 0.4, Color(0.8, 0.79, 0.77), 0.0, 1.0],
	"concrete_dark":     ["concrete_rough", 0.4, Color(0.45, 0.45, 0.46), 0.0, 1.0],
	"lining":            ["concrete_lining", 0.5, Color(0.6, 0.6, 0.62), 0.0, 1.0],
	"ballast":           ["ballast", 1.4, Color(0.95, 0.93, 0.9), 0.0, 1.0],
	"metal":             ["metal_brushed", 2.0, Color(0.75, 0.76, 0.78), 1.0, 1.0],
	"ceiling_panels":    ["ceiling_perforated", 1.5, Color(0.92, 0.92, 0.94), 0.5, 1.0],
	"rubber":            ["rubber_floor", 1.5, Color(0.3, 0.3, 0.32), 0.0, 1.0],
	"ground":            ["ballast", 1.5, Color(0.6, 0.68, 0.5), 0.0, 1.0],
}

static func texture(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := TEX_DIR + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[name] = t
	return t

static func _build(set_name: String, scale: float, tint: Color, metallic: float, rough_mul: float, triplanar: bool, extra: Dictionary = {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metallic
	m.roughness = clampf(rough_mul, 0.0, 1.0)
	var alb := texture(set_name + "_albedo")
	if alb:
		m.albedo_texture = alb
	var nrm := texture(set_name + "_normal")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 1.0
	var rgh := texture(set_name + "_rough")
	if rgh:
		m.roughness_texture = rgh
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = clampf(rough_mul, 0.0, 1.0)
	m.uv1_scale = Vector3(scale, scale, scale)
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if extra.get("clearcoat", 0.0) > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = float(extra["clearcoat"])
		m.clearcoat_roughness = 0.15
	return m

## Prosedürel geometri malzemesi (triplanar)
static func proc(name: String, tint_override: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key := "proc:" + name + ":" + tint_override.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var d: Array = PROC.get(name, PROC["concrete"])
	var tint: Color = d[2] if tint_override.a == 0.0 else tint_override
	var m := _build(d[0], d[1], tint, d[3], d[4], true)
	_mat_cache[key] = m
	return m

## GLB'den gelen malzeme adına göre PBR malzeme (UV tabanlı)
static func for_name(name: String, base: Material) -> Material:
	if not BY_NAME.has(name):
		return null
	if _mat_cache.has("glb:" + name):
		return _mat_cache["glb:" + name]
	var d: Array = BY_NAME[name]
	var m := _build(d[0], d[1], d[2], d[3], d[4], false, d[5])
	# Orijinal malzemenin emission/alpha ayarlarını koru
	if base is BaseMaterial3D:
		var b := base as BaseMaterial3D
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			m.transparency = b.transparency
			m.albedo_color.a = b.albedo_color.a
	_mat_cache["glb:" + name] = m
	return m

## Bir GLB örneğindeki tüm yüzey malzemelerini kütüphaneyle değiştirir; camları iyileştirir.
static func apply_to(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var base := mesh.surface_get_material(s)
			if base == null:
				continue
			var rn := base.resource_name
			var rep := for_name(rn, base)
			if rep:
				mi.set_surface_override_material(s, rep)
			elif base is BaseMaterial3D:
				_tune_imported(base as BaseMaterial3D, rn)
	if node is MeshInstance3D:
		pass

static var _tuned: Dictionary = {}

## Dokusuz GLB malzemelerine küçük iyileştirmeler (cam yansıması, emissive gücü)
static func _tune_imported(b: BaseMaterial3D, rn: String) -> void:
	if _tuned.has(rn):
		return
	_tuned[rn] = true
	if rn.contains("Glass"):
		b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		b.roughness = 0.05
		b.metallic = 0.0
		b.specular = 0.12 if rn.contains("Cab") else 0.3
		b.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.refraction_enabled = false
	if rn.contains("Light") or rn.contains("light"):
		b.emission_enabled = true
		if rn == "Env_LightWarm":
			b.emission_energy_multiplier = 0.9
		elif rn == "Env_Light":
			b.emission_energy_multiplier = 2.2
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
