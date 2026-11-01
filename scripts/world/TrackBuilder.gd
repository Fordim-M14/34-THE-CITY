class_name TrackBuilder
extends Node3D
## TrackBuilder v3 — hat inşası (PBR + Blender propları):
##   • Tünel: tunnel_segment.glb (kaplama halkaları, yürüyüş yolu, korkuluk, kablo tavaları,
##     yangın borusu, lamba yuvaları) MultiMesh ile 10 m'lik segmentler; her segmentte gerçek
##     OmniLight (kaliteye göre yoğunluk); acil çıkış nişleri (~400 m), havalandırma (~900 m)
##   • Açık kesim: istinat duvarı (kaba beton), korkuluk, çakıl zemin, gökyüzü
##   • Raylar (fırçalanmış metal), traversler (beton), ray bağlantı plakaları, balast
##   • Katener (rijit havai hat), hız levhaları, km işaretleri, istasyonlar, sinyaller, tampon
## Geometri 100 m'lik chunk'lara bölünür; görüş mesafesi ayara bağlıdır.

const SEGMENT_LEN := 10.0
const CHUNK_LEN := 100.0
const SLEEPER_SPACING := 0.65
const RAIL_SEG := 10.0

var curve: Curve3D
var track_length: float = 0.0
var signals_by_id: Dictionary = {}
var route: RouteData
var _chunks: Dictionary = {}
var _vis_timer := 0.0
var _tunnel_lights: Array[OmniLight3D] = []

# Malzemeler (prosedürel geometri)
var mat_concrete: StandardMaterial3D
var mat_concrete_dark: StandardMaterial3D
var mat_lining: StandardMaterial3D
var mat_rail: StandardMaterial3D
var mat_sleeper: StandardMaterial3D
var mat_ballast: StandardMaterial3D
var mat_platform: StandardMaterial3D
var mat_yellow: StandardMaterial3D
var mat_lamp_warm: StandardMaterial3D
var mat_lamp_cool: StandardMaterial3D
var mat_column: StandardMaterial3D
var mat_sign: StandardMaterial3D
var mat_buffer: StandardMaterial3D
var mat_cable: StandardMaterial3D
var mat_catenary: StandardMaterial3D
var mat_wall_open: StandardMaterial3D
var mat_ground: StandardMaterial3D
var mat_fence: StandardMaterial3D
var mat_white: StandardMaterial3D
var mat_metal: StandardMaterial3D

## Karşı yön hattı: peronun ters tarafında, 8 m yanal mesafede ikinci tünel/ray (v0.4)
const OPP_OFFSET := 8.0
var opp_x: float = -8.0

func build(p_route: RouteData) -> void:
	route = p_route
	curve = route.curve
	track_length = route.track_length
	var side := 1.0
	if route.stations.size() > 0:
		side = 1.0 if str(route.stations[0].get("door_side", "right")) == "right" else -1.0
	opp_x = -OPP_OFFSET * side
	_make_materials()
	_build_track_geometry()
	_build_tunnel_props()
	_build_speed_signs()
	_build_km_markers()
	_build_stations()
	_build_signals()
	_build_buffer_stop()

# ---------------------------------------------------------------------------

func get_track_transform(offset: float) -> Transform3D:
	var o: float = clampf(offset, 0.0, track_length - 0.6)
	var p0: Vector3 = curve.sample_baked(o, true)
	var p1: Vector3 = curve.sample_baked(o + 0.5, true)
	var fwd: Vector3 = (p1 - p0)
	if fwd.length_squared() < 1e-6:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), p0)

func chunk_node(offset: float) -> Node3D:
	var key := int(floor(offset / CHUNK_LEN))
	if not _chunks.has(key):
		var n := Node3D.new()
		n.name = "Chunk_%03d" % key
		add_child(n)
		_chunks[key] = n
	return _chunks[key]

func update_visibility(train_offset: float, delta: float) -> void:
	_vis_timer -= delta
	if _vis_timer > 0.0:
		return
	_vis_timer = 0.4
	var rng_v := Settings.visible_range()
	for key in _chunks:
		var center: float = (key + 0.5) * CHUNK_LEN
		var vis: bool = absf(center - train_offset) < rng_v
		var n: Node3D = _chunks[key]
		if n.visible != vis:
			n.visible = vis

func _mat(color: Color, roughness: float = 0.9, metallic: float = 0.0, emission: Color = Color.BLACK, emission_energy: float = 0.0, two_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _make_materials() -> void:
	mat_concrete = MaterialLib.proc("concrete")
	mat_concrete_dark = MaterialLib.proc("concrete_dark")
	mat_lining = MaterialLib.proc("lining")
	mat_rail = MaterialLib.proc("metal", Color(0.62, 0.62, 0.64))
	mat_rail.roughness = 0.35
	mat_sleeper = MaterialLib.proc("concrete_dark", Color(0.5, 0.49, 0.47))
	mat_ballast = MaterialLib.proc("ballast")
	mat_platform = MaterialLib.proc("platform_paving")
	mat_yellow = _mat(Color(0.95, 0.78, 0.15), 0.6, 0.0, Color(0.95, 0.78, 0.15), 0.25)
	mat_lamp_warm = _mat(Color(1.0, 0.85, 0.6), 0.5, 0.0, Color(1.0, 0.8, 0.5), 3.0)
	mat_lamp_cool = _mat(Color(0.9, 0.95, 1.0), 0.5, 0.0, Color(0.85, 0.92, 1.0), 3.5)
	mat_column = _mat(Color(0.18, 0.20, 0.23), 0.5, 0.3)
	mat_sign = _mat(Color(0.10, 0.22, 0.26), 0.5)
	mat_buffer = _mat(Color(0.75, 0.12, 0.1), 0.6, 0.2, Color(0.9, 0.1, 0.1), 0.6)
	mat_cable = _mat(Color(0.12, 0.12, 0.13), 0.75, 0.2)
	mat_catenary = MaterialLib.proc("metal", Color(0.65, 0.5, 0.35))
	mat_wall_open = MaterialLib.proc("concrete", Color(0.7, 0.68, 0.64))
	mat_ground = MaterialLib.proc("ground")
	mat_fence = _mat(Color(0.35, 0.37, 0.4), 0.5, 0.7)
	mat_white = _mat(Color(0.92, 0.92, 0.9), 0.5)
	mat_metal = MaterialLib.proc("metal")

# ---------------------------------------------------------------------------
# Hat geometrisi

func _build_track_geometry() -> void:
	var tunnel_mesh: Mesh = MeshUtil.merged_mesh("tunnel_segment")
	if tunnel_mesh == null:
		tunnel_mesh = _make_fallback_tunnel(SEGMENT_LEN)
	var open_floor := BoxMesh.new()
	open_floor.size = Vector3(14.0, 0.3, SEGMENT_LEN + 0.05)
	open_floor.material = mat_ground
	var open_wall := BoxMesh.new()
	open_wall.size = Vector3(0.6, 7.2, SEGMENT_LEN + 0.05)
	open_wall.material = mat_wall_open
	var open_wall_cap := BoxMesh.new()
	open_wall_cap.size = Vector3(0.8, 0.2, SEGMENT_LEN + 0.05)
	open_wall_cap.material = mat_concrete
	var fence := BoxMesh.new()
	fence.size = Vector3(0.05, 1.1, SEGMENT_LEN + 0.05)
	fence.material = mat_fence
	var ballast := BoxMesh.new()
	ballast.size = Vector3(3.8, 0.3, SEGMENT_LEN + 0.05)
	ballast.material = mat_ballast
	var rail_mesh := _make_rail_mesh(RAIL_SEG)
	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(2.5, 0.16, 0.26)
	sleeper_mesh.material = mat_sleeper
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.22, 0.03, 0.18)
	plate_mesh.material = mat_metal
	# 3. ray (sağ tarafta, kapaklı) + izolatörler
	var third_rail := BoxMesh.new()
	third_rail.size = Vector3(0.09, 0.09, SEGMENT_LEN + 0.05)
	third_rail.material = mat_rail
	var third_cover := BoxMesh.new()
	third_cover.size = Vector3(0.26, 0.04, SEGMENT_LEN + 0.05)
	third_cover.material = mat_cable
	var insulator := BoxMesh.new()
	insulator.size = Vector3(0.12, 0.2, 0.12)
	insulator.material = mat_white

	var tunnel_xf: Array = []
	var tunnel2_xf: Array = []
	var ballast2_xf: Array = []
	var third2_xf: Array = []
	var cover2_xf: Array = []
	var open_floor_xf: Array = []
	var open_wall_xf: Array = []
	var open_cap_xf: Array = []
	var fence_xf: Array = []
	var ballast_xf: Array = []
	var rail_xf: Array = []
	var sleeper_xf: Array = []
	var plate_xf: Array = []
	var third_xf: Array = []
	var cover_xf: Array = []
	var ins_xf: Array = []

	var off := 0.0
	while off < track_length - 1.0:
		var xf := get_track_transform(off)
		var mid: float = off + SEGMENT_LEN * 0.5
		var in_station := not route.get_station_at(mid).is_empty()
		var seg_type := route.get_segment_type(mid)
		if not in_station:
			if seg_type == "open":
				open_floor_xf.append([off, xf.translated_local(Vector3(0.0, -0.85, -SEGMENT_LEN * 0.5))])
				for sx in [-5.6, 5.6]:
					open_wall_xf.append([off, xf.translated_local(Vector3(sx, 2.9, -SEGMENT_LEN * 0.5))])
					open_cap_xf.append([off, xf.translated_local(Vector3(sx, 6.6, -SEGMENT_LEN * 0.5))])
					fence_xf.append([off, xf.translated_local(Vector3(sx, 7.25, -SEGMENT_LEN * 0.5))])
			else:
				tunnel_xf.append([off, xf])
				tunnel2_xf.append([off, xf.translated_local(Vector3(opp_x, 0.0, 0.0))])
		ballast_xf.append([off, xf.translated_local(Vector3(0.0, -0.55, -SEGMENT_LEN * 0.5))])
		ballast2_xf.append([off, xf.translated_local(Vector3(opp_x, -0.55, -SEGMENT_LEN * 0.5))])
		third2_xf.append([off, xf.translated_local(Vector3(opp_x - signf(opp_x) * 1.38, 0.12, -SEGMENT_LEN * 0.5))])
		cover2_xf.append([off, xf.translated_local(Vector3(opp_x - signf(opp_x) * 1.38, 0.2, -SEGMENT_LEN * 0.5))])
		# 3. ray (ray üstünden 0.15 m yukarıda, sağda)
		third_xf.append([off, xf.translated_local(Vector3(1.38, 0.12, -SEGMENT_LEN * 0.5))])
		cover_xf.append([off, xf.translated_local(Vector3(1.38, 0.2, -SEGMENT_LEN * 0.5))])
		for iz in [1.5, 5.0, 8.5]:
			ins_xf.append([off, xf.translated_local(Vector3(1.38, -0.05, -iz))])
		off += SEGMENT_LEN
	off = 0.0
	while off < track_length - 1.0:
		var xf := get_track_transform(off)
		rail_xf.append([off, xf.translated_local(Vector3(-0.72, 0.0, -RAIL_SEG * 0.5))])
		rail_xf.append([off, xf.translated_local(Vector3(0.72, 0.0, -RAIL_SEG * 0.5))])
		rail_xf.append([off, xf.translated_local(Vector3(opp_x - 0.72, 0.0, -RAIL_SEG * 0.5))])
		rail_xf.append([off, xf.translated_local(Vector3(opp_x + 0.72, 0.0, -RAIL_SEG * 0.5))])
		off += RAIL_SEG
	off = 0.0
	while off < track_length - 1.0:
		var xf := get_track_transform(off)
		sleeper_xf.append([off, xf.translated_local(Vector3(0.0, -0.23, 0.0))])
		sleeper_xf.append([off, xf.translated_local(Vector3(opp_x, -0.23, 0.0))])
		for sx in [-0.72, 0.72]:
			plate_xf.append([off, xf.translated_local(Vector3(sx, -0.14, 0.0))])
			plate_xf.append([off, xf.translated_local(Vector3(opp_x + sx, -0.14, 0.0))])
		off += SLEEPER_SPACING

	_add_multimesh("Tunnel", tunnel_mesh, tunnel_xf)
	_add_multimesh("Tunnel2", tunnel_mesh, tunnel2_xf)
	_add_multimesh("Ballast2", ballast, ballast2_xf)
	_add_multimesh("ThirdRail2", third_rail, third2_xf)
	_add_multimesh("ThirdRailCover2", third_cover, cover2_xf)
	_add_multimesh("OpenFloor", open_floor, open_floor_xf)
	_add_multimesh("OpenWall", open_wall, open_wall_xf)
	_add_multimesh("OpenCap", open_wall_cap, open_cap_xf)
	_add_multimesh("Fence", fence, fence_xf)
	_add_multimesh("Ballast", ballast, ballast_xf)
	_add_multimesh("Rails", rail_mesh, rail_xf)
	_add_multimesh("Sleepers", sleeper_mesh, sleeper_xf)
	_add_multimesh("Plates", plate_mesh, plate_xf)
	_add_multimesh("ThirdRail", third_rail, third_xf)
	_add_multimesh("ThirdRailCover", third_cover, cover_xf)
	_add_multimesh("Insulators", insulator, ins_xf)
	# Tünel lambaları (segment başına 2 yuva; kaliteye göre ışık yoğunluğu); karşı tünelde seyrek
	_build_tunnel_lights(tunnel_xf)
	var t2_sparse: Array = []
	for i in tunnel2_xf.size():
		if i % 2 == 0:
			t2_sparse.append(tunnel2_xf[i])
	_build_tunnel_lights(t2_sparse)

## Ray profili (baş + gövde + taban), -Z yönünde uzanır; metal malzeme (ray üstü parlak)
func _make_rail_mesh(length: float) -> ArrayMesh:
	var prof: Array[Vector2] = [
		Vector2(-0.035, 0.0), Vector2(0.035, 0.0), Vector2(0.035, -0.04), Vector2(0.012, -0.05),
		Vector2(0.012, -0.12), Vector2(0.07, -0.145), Vector2(0.07, -0.16), Vector2(-0.07, -0.16),
		Vector2(-0.07, -0.145), Vector2(-0.012, -0.12), Vector2(-0.012, -0.05), Vector2(-0.035, -0.04),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := prof.size()
	for i in n:
		var a := prof[i]
		var b := prof[(i + 1) % n]
		var e := b - a
		var nrm2 := Vector2(e.y, -e.x).normalized()
		var nrm := Vector3(nrm2.x, nrm2.y, 0)
		var v0 := Vector3(a.x, a.y, 0)
		var v1 := Vector3(b.x, b.y, 0)
		var v2 := Vector3(b.x, b.y, -length)
		var v3 := Vector3(a.x, a.y, -length)
		for v in [v0, v2, v1, v0, v3, v2]:
			st.set_normal(nrm)
			st.set_uv(Vector2(v.x * 4.0, v.z * 0.5))
			st.add_vertex(v)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat_rail)
	return mesh

func _make_fallback_tunnel(length: float) -> ArrayMesh:
	var profile: Array[Vector2] = [
		Vector2(-2.9, -0.7), Vector2(2.9, -0.7), Vector2(2.9, 2.6), Vector2(2.4, 3.9),
		Vector2(1.3, 4.9), Vector2(-1.3, 4.9), Vector2(-2.4, 3.9), Vector2(-2.9, 2.6),
		Vector2(-2.9, 0.8), Vector2(-2.2, 0.8), Vector2(-2.2, -0.7),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var edge := b - a
		var nrm2 := Vector2(-edge.y, edge.x).normalized()
		if nrm2.dot(Vector2(0, 2) - (a + b) * 0.5) < 0.0:
			nrm2 = -nrm2
		var nrm := Vector3(nrm2.x, nrm2.y, 0.0)
		var v0 := Vector3(a.x, a.y, 0.0)
		var v1 := Vector3(b.x, b.y, 0.0)
		var v2 := Vector3(b.x, b.y, -length)
		var v3 := Vector3(a.x, a.y, -length)
		for v in [v0, v1, v2, v0, v2, v3]:
			st.set_normal(nrm)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat_lining)
	return mesh

func _add_multimesh(p_name: String, mesh: Mesh, items: Array) -> void:
	var chunks: Dictionary = {}
	for it in items:
		var key := int(floor(float(it[0]) / CHUNK_LEN))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(it[1])
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [p_name, key]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if p_name in ["Tunnel", "Rails", "Sleepers", "OpenWall"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk_node((key + 0.5) * CHUNK_LEN).add_child(mmi)

func _build_tunnel_lights(tunnel_xf: Array) -> void:
	var dens := Settings.light_density()
	var i := 0
	for it in tunnel_xf:
		var off: float = it[0]
		var xf: Transform3D = it[1]
		# Segmentte iki lamba yuvası (y=2.5, 7.5) — yoğunluğa göre seç
		var slots := [2.5, 7.5]
		for k in slots.size():
			var idx := i * 2 + k
			var keep := true
			if dens < 0.6:
				keep = idx % 3 == 0
			elif dens < 0.9:
				keep = idx % 2 == 0
			if not keep:
				continue
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.86, 0.68)
			light.light_energy = 1.3
			light.omni_range = 15.0
			light.omni_attenuation = 1.1
			light.shadow_enabled = false
			light.light_volumetric_fog_energy = 0.25
			light.transform = xf.translated_local(Vector3(2.1, 3.55, -slots[k]))
			chunk_node(off).add_child(light)
			_tunnel_lights.append(light)
		i += 1

## Acil çıkış nişleri ve havalandırma (tünel kesimlerinde, istasyon dışı)
func _build_tunnel_props() -> void:
	var off := 250.0
	var k := 0
	while off < track_length - 100.0:
		if route.get_station_at(off).is_empty() and route.get_segment_type(off) == "tunnel":
			var xf := get_track_transform(off)
			var prop_name := "vent_fan" if k % 3 == 2 else "emergency_door"
			var p := MeshUtil.instance_prop(prop_name)
			if p:
				p.transform = xf
				chunk_node(off).add_child(p)
				if prop_name == "emergency_door":
					var l := OmniLight3D.new()
					l.light_color = Color(0.6, 1.0, 0.7)
					l.light_energy = 1.2
					l.omni_range = 6.0
					l.position = Vector3(2.6, 2.0, 0.0)
					l.shadow_enabled = false
					p.add_child(l)
		off += 380.0
		k += 1

# ---------------------------------------------------------------------------
# Levhalar

func _build_speed_signs() -> void:
	var prev := -1.0
	for sl in route.speed_limits:
		var from_pos: float = float(sl["from"])
		var lim: float = float(sl["limit_kmh"])
		if from_pos <= 0.0 or lim == prev:
			prev = lim
			continue
		prev = lim
		var xf := get_track_transform(from_pos)
		var holder := Node3D.new()
		holder.transform = xf.translated_local(Vector3(2.35, 0.0, 0.0))
		chunk_node(from_pos).add_child(holder)
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.035
		pm.bottom_radius = 0.035
		pm.height = 2.1
		pm.material = mat_metal
		post.mesh = pm
		post.position = Vector3(0, 1.05, 0)
		holder.add_child(post)
		var board := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.32
		bm.bottom_radius = 0.32
		bm.height = 0.03
		bm.radial_segments = 32
		bm.material = mat_white
		board.mesh = bm
		board.position = Vector3(0, 2.3, 0)
		board.rotation.x = PI * 0.5
		holder.add_child(board)
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 0.28
		rm.outer_radius = 0.33
		rm.material = _mat(Color(0.85, 0.1, 0.1), 0.5)
		ring.mesh = rm
		ring.position = Vector3(0, 2.3, 0.02)
		ring.rotation.x = PI * 0.5
		holder.add_child(ring)
		var lbl := Label3D.new()
		lbl.text = str(int(lim))
		lbl.font_size = 110
		lbl.pixel_size = 0.0035
		lbl.modulate = Color(0.08, 0.08, 0.1)
		lbl.position = Vector3(0, 2.3, 0.03)
		holder.add_child(lbl)

func _build_km_markers() -> void:
	var off := 100.0
	while off < track_length - 50.0:
		if route.get_station_at(off).is_empty():
			var xf := get_track_transform(off)
			var board := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.22, 0.5)
			bm.material = mat_white
			board.mesh = bm
			board.transform = xf.translated_local(Vector3(-2.85, 1.7, 0.0))
			chunk_node(off).add_child(board)
			var lbl := Label3D.new()
			lbl.text = "%d+%03d" % [int(off / 1000.0), int(fmod(off, 1000.0))]
			lbl.font_size = 40
			lbl.pixel_size = 0.0035
			lbl.modulate = Color(0.1, 0.1, 0.1)
			lbl.transform = xf.translated_local(Vector3(-2.82, 1.7, 0.0))
			lbl.rotation.y += PI * 0.5
			chunk_node(off).add_child(lbl)
		off += 100.0

# ---------------------------------------------------------------------------

func _build_stations() -> void:
	for s in route.stations:
		var sb := StationBuilder.new()
		sb.name = "Station_" + str(s["id"])
		chunk_node(float(s["stop_pos"])).add_child(sb)
		sb.build(self, s)

func get_station_node(id: String) -> StationBuilder:
	for key in _chunks:
		var n: Node3D = _chunks[key]
		var c := n.get_node_or_null("Station_" + id)
		if c:
			return c
	return null

func _build_signals() -> void:
	for sg in route.signals:
		var sig := TrackSignal.new()
		sig.name = "Signal_" + str(sg["id"])
		sig.signal_id = str(sg["id"])
		sig.signal_type = str(sg.get("type", "block"))
		sig.track_pos = float(sg["pos"])
		sig.station_id = str(sg.get("station", ""))
		chunk_node(sig.track_pos).add_child(sig)
		sig.global_transform = get_track_transform(sig.track_pos).translated_local(Vector3(2.2, 0.0, 0.0))
		sig.build()
		sig.set_aspect(str(sg.get("aspect", "green")))
		signals_by_id[sig.signal_id] = sig

func _build_buffer_stop() -> void:
	var xf := get_track_transform(route.buffer_end)
	var holder := Node3D.new()
	holder.transform = xf
	add_child(holder)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.5, 0.4)
	bm.material = mat_buffer
	mi.mesh = bm
	mi.position = Vector3(0, 0.95, 0)
	holder.add_child(mi)
	for sx in [-0.9, 0.9]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.25, 1.2, 1.6)
		lm.material = mat_metal
		leg.mesh = lm
		leg.position = Vector3(sx, 0.4, -0.5)
		leg.rotation.x = deg_to_rad(-30)
		holder.add_child(leg)
	var lbl := Label3D.new()
	lbl.text = "HAT SONU"
	lbl.font_size = 96
	lbl.pixel_size = 0.004
	lbl.position = Vector3(0.0, 2.2, 0.3)
	holder.add_child(lbl)
