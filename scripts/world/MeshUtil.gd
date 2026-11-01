class_name MeshUtil
extends RefCounted
## MeshUtil — GLB sahnelerini tek ArrayMesh'e birleştirme (MultiMesh örnekleme için),
## prop örnekleme yardımcıları.

static var _scene_cache: Dictionary = {}
static var _merged_cache: Dictionary = {}

static func load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_scene_cache[path] = ps
	return ps

## Bir prop GLB'sini örnekler, malzemeleri kütüphaneden uygular.
static func instance_prop(name: String) -> Node3D:
	var ps := load_scene("res://assets/models/props/%s.glb" % name)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	MaterialLib.apply_to(n)
	return n

## GLB sahnesindeki tüm MeshInstance3D'leri (kök dönüşümlerine göre) tek ArrayMesh'te birleştirir.
## Malzemeler kütüphaneyle değiştirilir; aynı malzemeye sahip yüzeyler birleştirilir.
static func merged_mesh(prop_name: String) -> ArrayMesh:
	if _merged_cache.has(prop_name):
		return _merged_cache[prop_name]
	var ps := load_scene("res://assets/models/props/%s.glb" % prop_name)
	if ps == null:
		return null
	var root: Node3D = ps.instantiate()
	MaterialLib.apply_to(root)
	# Malzeme → SurfaceTool
	var tools: Dictionary = {}
	var order: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var xf: Transform3D = _relative_transform(mi, root)
		for s in mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mesh.surface_get_material(s)
			var key := str(m.get_instance_id()) if m else "none"
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = {"st": st, "mat": m}
				order.append(key)
			var st2: SurfaceTool = tools[key]["st"]
			st2.append_from(mesh, s, xf)
	var out := ArrayMesh.new()
	for key in order:
		var st: SurfaceTool = tools[key]["st"]
		st.generate_tangents()
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, tools[key]["mat"])
	root.free()
	_merged_cache[prop_name] = out
	return out

static func _relative_transform(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
