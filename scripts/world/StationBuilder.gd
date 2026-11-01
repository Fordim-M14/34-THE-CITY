class_name StationBuilder
extends Node3D
## StationBuilder v3 — PBR dokular + Blender propları ile istasyon holü.
## Stiller: airport (geniş, cam paneller, aydınlık), modern (gri fayans, hat rengi bant),
## classic (bej fayans, kahverengi bant, tonoz), deep (beton kaplama tonoz, loş), trench (açık
## kesim, sundurma, gün ışığı). Öğeler: peron (döşeme + hissedilebilir yüzey + kenar), kolonlar,
## gömme armatürler (gerçek ışık), banklar, çöp kutuları, otomat, yangın dolabı, kameralar, PIS
## ekranları, yön tabelaları, isim panoları, saat, yürüyen merdiven + çıkış koridoru, merdiven,
## asansör, reklam panoları, yansıma probu.

const OPP_TRACK_X := -8.0        # karşı yön hattı (peronun ters tarafı)
var track_wall_x: float = -2.95   # karşı peronun arka duvarı (build() hesaplar)
const PLATFORM_EDGE_X := 1.65
const PLATFORM_Y := 1.1

const STYLES := {
	"airport": {"wall_tint": Color(0.93, 0.94, 0.96), "accent": Color(0.16, 0.72, 0.68), "tile_scale": 0.35, "ceiling": "flat",
		"height": 6.6, "platform_w": 8.0, "light": Color(0.95, 0.97, 1.0), "light_energy": 2.4, "columns": "round", "glass_wall": true, "floor_tint": Color(0.8, 0.8, 0.8)},
	"modern": {"wall_tint": Color(0.72, 0.74, 0.77), "accent": Color(0.83, 0.2, 0.48), "tile_scale": 0.5, "ceiling": "flat",
		"height": 5.8, "platform_w": 6.0, "light": Color(0.9, 0.94, 1.0), "light_energy": 2.0, "columns": "square", "glass_wall": false, "floor_tint": Color(0.68, 0.68, 0.68)},
	"classic": {"wall_tint": Color(0.88, 0.80, 0.64), "accent": Color(0.5, 0.25, 0.15), "tile_scale": 0.6, "ceiling": "vault",
		"height": 6.0, "platform_w": 6.0, "light": Color(1.0, 0.9, 0.75), "light_energy": 1.8, "columns": "square", "glass_wall": false, "floor_tint": Color(0.72, 0.68, 0.6)},
	"deep": {"wall_tint": Color(0.62, 0.64, 0.68), "accent": Color(0.2, 0.45, 0.8), "tile_scale": 0.45, "ceiling": "vault",
		"height": 6.4, "platform_w": 6.0, "light": Color(0.85, 0.9, 1.0), "light_energy": 1.6, "columns": "round", "glass_wall": false, "floor_tint": Color(0.6, 0.6, 0.62)},
	"trench": {"wall_tint": Color(0.7, 0.68, 0.64), "accent": Color(0.2, 0.6, 0.35), "tile_scale": 0.5, "ceiling": "canopy",
		"height": 5.4, "platform_w": 6.0, "light": Color(1.0, 0.95, 0.9), "light_energy": 1.0, "columns": "square", "glass_wall": false, "floor_tint": Color(0.7, 0.7, 0.68)},
}

var world: TrackBuilder
var data: Dictionary
var side_sign: float = 1.0
var style: Dictionary
var length: float = 0.0
var hall_h: float = 5.8
var platform_w: float = 6.0
var exit_positions: Array[Vector3] = []
var platform_area: Dictionary = {}
var mat_wall: StandardMaterial3D
var mat_floor: StandardMaterial3D
var mat_accent: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_poster_a: StandardMaterial3D
var mat_poster_b: StandardMaterial3D
var mat_lamp: StandardMaterial3D
var mat_ceiling: StandardMaterial3D
var mat_dark: StandardMaterial3D
var _clocks: Array[Label3D] = []
var bench_seats: Array = []   # [{pos: Vector3 (yerel), yaw: float}] — oyuncu peronundaki bank oturma yerleri
var _pis_labels: Array[Label3D] = []

func build(p_world: TrackBuilder, p_data: Dictionary) -> void:
	world = p_world
	data = p_data
	side_sign = 1.0 if str(data.get("door_side", "right")) == "right" else -1.0
	style = STYLES.get(str(data.get("style", "modern")), STYLES["modern"]).duplicate()
	if data.has("accent"):
		style["accent"] = Color.html(str(data["accent"]))
	hall_h = float(style["height"])
	platform_w = float(style["platform_w"])
	track_wall_x = OPP_TRACK_X - PLATFORM_EDGE_X - platform_w - 0.3
	var start: float = float(data["platform_start"])
	length = float(data["platform_end"]) - start
	global_transform = world.get_track_transform(start)
	_make_materials()
	_build_shell()
	_build_platform()
	_build_opposite_platform()
	_build_lights()
	_build_signs()
	_build_furniture()
	_build_exits()
	_build_stop_board(float(data["stop_pos"]) - start)
	_build_extras()
	_build_reflection_probe()
	platform_area = {
		"x_min": _sx(PLATFORM_EDGE_X + 1.0), "x_max": _sx(PLATFORM_EDGE_X + platform_w - 0.8),
		"z_min": -length + 5.0, "z_max": -5.0, "y": PLATFORM_Y,
	}

func _make_materials() -> void:
	mat_wall = MaterialLib.proc("tiles", style["wall_tint"])
	mat_wall.uv1_scale = Vector3.ONE * float(style["tile_scale"])
	mat_floor = MaterialLib.proc("platform_paving", style["floor_tint"])
	mat_accent = world._mat(style["accent"], 0.45, 0.15)
	mat_glass = world._mat(Color(0.7, 0.82, 0.9, 0.22), 0.03, 0.1)
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var seed_v := 20 + int(data.get("index", 0))
	mat_poster_a = StandardMaterial3D.new()
	mat_poster_a.albedo_texture = TextureFactory.poster(256, 100 + seed_v)
	mat_poster_a.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_poster_b = StandardMaterial3D.new()
	mat_poster_b.albedo_texture = TextureFactory.poster(256, 200 + seed_v)
	mat_poster_b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_lamp = world._mat(style["light"], 0.4, 0.0, style["light"], 3.0)
	mat_ceiling = MaterialLib.proc("ceiling_panels") if str(style["ceiling"]) == "flat" else MaterialLib.proc("lining", Color(0.75, 0.75, 0.77))
	mat_dark = world.mat_column

func _box(size: Vector3, pos: Vector3, mat: Material, p_name: String = "", shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	if p_name != "":
		mi.name = p_name
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _prop(name: String, pos: Vector3, rot_y: float = 0.0) -> Node3D:
	var p := MeshUtil.instance_prop(name)
	if p == null:
		return null
	p.position = pos
	p.rotation.y = rot_y
	add_child(p)
	return p

func _label(text: String, pos: Vector3, size: int, color: Color, rot_y: float = 0.0, outline: int = 0) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = size
	lbl.pixel_size = 0.005
	lbl.modulate = color
	lbl.outline_size = outline
	lbl.position = pos
	lbl.rotation.y = rot_y
	add_child(lbl)
	return lbl

func _sx(x: float) -> float:
	return x * side_sign

func far_x() -> float:
	return PLATFORM_EDGE_X + platform_w + 0.3

func _facing_track() -> float:
	return -PI * 0.5 * side_sign

# ---------------------------------------------------------------------------

func _build_shell() -> void:
	var zc := -length * 0.5
	var fx := far_x()
	var total_w := fx - track_wall_x
	var center_x := (fx + track_wall_x) * 0.5
	var is_open := str(style["ceiling"]) == "canopy"
	_box(Vector3(total_w, 0.3, length), Vector3(_sx(center_x), -0.85, zc), world.mat_concrete_dark, "Floor")
	# Hat tarafı duvar (fayans) + üst bant
	_box(Vector3(0.3, hall_h + 0.7, length), Vector3(_sx(track_wall_x - 0.15), (hall_h - 0.7) * 0.5, zc), mat_wall, "TrackWall")
	_box(Vector3(0.06, 0.4, length), Vector3(_sx(track_wall_x + 0.03), PLATFORM_Y + 1.6, zc), mat_accent)
	# Peron arka duvarı
	_box(Vector3(0.3, hall_h + 0.7, length), Vector3(_sx(fx + 0.15), (hall_h - 0.7) * 0.5, zc), mat_wall, "BackWall")
	_box(Vector3(0.05, 0.4, length), Vector3(_sx(fx - 0.03), PLATFORM_Y + 1.6, zc), mat_accent)
	# Süpürgelik
	_box(Vector3(0.06, 0.12, length), Vector3(_sx(fx - 0.03), PLATFORM_Y + 0.06, zc), mat_dark)
	if bool(style["glass_wall"]):
		# Cam panel cephesi (arka duvar önünde)
		var z := -4.0
		while z > -length + 3.0:
			_box(Vector3(0.03, hall_h - PLATFORM_Y - 0.6, 3.6), Vector3(_sx(fx - 0.25), PLATFORM_Y + (hall_h - PLATFORM_Y - 0.6) * 0.5 + 0.2, z - 1.9), mat_glass, "", false)
			_box(Vector3(0.08, hall_h - PLATFORM_Y - 0.4, 0.1), Vector3(_sx(fx - 0.25), PLATFORM_Y + (hall_h - PLATFORM_Y - 0.4) * 0.5 + 0.1, z), world.mat_metal)
			z -= 4.0
	if is_open:
		_box(Vector3(platform_w + 1.2, 0.18, length), Vector3(_sx(PLATFORM_EDGE_X + platform_w * 0.5 + 0.3), hall_h, zc), world.mat_concrete_dark, "Canopy")
		_box(Vector3(platform_w + 1.2, 0.04, length), Vector3(_sx(PLATFORM_EDGE_X + platform_w * 0.5 + 0.3), hall_h - 0.11, zc), mat_ceiling, "CanopyUnder", false)
		var z := -5.0
		while z > -length + 3.0:
			var c := _prop("column", Vector3(_sx(PLATFORM_EDGE_X + 1.3), PLATFORM_Y, z))
			if c:
				c.scale = Vector3(0.5, (hall_h - PLATFORM_Y) / 4.3, 0.5)
			z -= 10.0
		# Hat tarafı alçak duvar (açık kesim istinat duvarı istasyonda devam eder)
	else:
		match str(style["ceiling"]):
			"vault":
				_build_vault(total_w, center_x, zc)
			_:
				_build_flat_ceiling(total_w, center_x)
				# Tavan ızgara profilleri
				var z := -2.0
				while z > -length + 1.0:
					_box(Vector3(total_w, 0.03, 0.05), Vector3(_sx(center_x), hall_h - 0.04, z), mat_dark, "", false)
					z -= 2.0
				var x := track_wall_x + 1.0
				while x < fx - 0.5:
					_box(Vector3(0.05, 0.03, length), Vector3(_sx(x), hall_h - 0.04, zc), mat_dark, "", false)
					x += 2.0
		# Portal duvarları (iki hat için iki tünel ağzı)
		for z in [0.0, -length]:
			var portal_w := fx - 2.95
			_box(Vector3(portal_w, hall_h + 0.7, 0.4), Vector3(_sx(2.95 + portal_w * 0.5), (hall_h - 0.7) * 0.5, z), mat_wall)
			for tx in [0.0, OPP_TRACK_X]:
				_box(Vector3(5.9, hall_h - 4.95 + 0.3, 0.4), Vector3(_sx(tx), 4.95 + (hall_h - 4.95 + 0.3) * 0.5, z), mat_wall)
				_box(Vector3(6.2, 0.25, 0.5), Vector3(_sx(tx), 5.0, z), world.mat_concrete_dark)
			# Hatlar arası orta ayak
			_box(Vector3(2.1, hall_h + 0.7, 0.4), Vector3(_sx(OPP_TRACK_X * 0.5), (hall_h - 0.7) * 0.5, z), mat_wall)
			# Karşı peron tarafı
			var lw := (OPP_TRACK_X - 2.95) - track_wall_x
			_box(Vector3(lw, hall_h + 0.7, 0.4), Vector3(_sx(track_wall_x + lw * 0.5), (hall_h - 0.7) * 0.5, z), mat_wall)
	# Kameralar
	var zc2 := -12.0
	while zc2 > -length + 8.0:
		_prop("cctv", Vector3(_sx(PLATFORM_EDGE_X + 0.6), hall_h - 0.1, zc2), PI if side_sign > 0 else 0.0)
		zc2 -= 30.0

## Düz tavan: yürüyen merdiven açıklığı bırakılarak dört parça
func _build_flat_ceiling(total_w: float, center_x: float) -> void:
	var ex := _sx(PLATFORM_EDGE_X + platform_w - 1.6)
	var hole_z0 := -length + 12.0 - 10.8   # açıklık (z aralığı)
	var hole_z1 := -length + 12.0 - 0.6
	var hole_x0 := ex - 1.7
	var hole_x1 := ex + 1.7
	var x_lo := _sx(track_wall_x) if side_sign > 0 else _sx(far_x())
	var x_hi := _sx(far_x()) if side_sign > 0 else _sx(track_wall_x)
	if x_lo > x_hi:
		var t := x_lo
		x_lo = x_hi
		x_hi = t
	var pieces := [
		[x_lo, x_hi, -length, hole_z0], [x_lo, x_hi, hole_z1, 0.0],
		[x_lo, hole_x0, hole_z0, hole_z1], [hole_x1, x_hi, hole_z0, hole_z1],
	]
	for pc in pieces:
		var w: float = pc[1] - pc[0]
		var d: float = pc[3] - pc[2]
		if w <= 0.05 or d <= 0.05:
			continue
		var cx: float = (pc[0] + pc[1]) * 0.5
		var cz: float = (pc[2] + pc[3]) * 0.5
		_box(Vector3(w, 0.3, d), Vector3(cx, hall_h + 0.15, cz), world.mat_concrete_dark)
		_box(Vector3(w, 0.03, d), Vector3(cx, hall_h - 0.015, cz), mat_ceiling, "", false)
	# Açıklık kenar çerçevesi
	_box(Vector3(hole_x1 - hole_x0 + 0.2, 0.35, 0.1), Vector3(ex, hall_h + 0.15, hole_z0), mat_dark)
	_box(Vector3(hole_x1 - hole_x0 + 0.2, 0.35, 0.1), Vector3(ex, hall_h + 0.15, hole_z1), mat_dark)

func _build_vault(total_w: float, center_x: float, zc: float) -> void:
	# Tonoz: 7 panel yay (kaplama dokusu), kenarlarda düz parçalar
	var n := 7
	var r := total_w * 0.52
	for i in n:
		var a0 := PI * i / n
		var a1 := PI * (i + 1) / n
		var am := (a0 + a1) * 0.5
		var seg_w := r * (a1 - a0) * 1.05
		var mi := _box(Vector3(seg_w, 0.25, length), Vector3.ZERO, mat_ceiling, "", false)
		var kv := 0.55 if total_w < 15.0 else 0.3
		mi.position = Vector3(_sx(center_x + cos(am) * r * 0.95 * side_sign), hall_h - 1.6 + sin(am) * r * kv, zc)
		mi.rotation.z = -(am - PI * 0.5) * side_sign * 0.7
	# Tonoz altı sıva bandı
	_box(Vector3(total_w, 0.1, length), Vector3(_sx(center_x), hall_h - 1.65, zc), world.mat_concrete_dark, "", false)

func _build_platform() -> void:
	var zc := -length * 0.5
	var px := PLATFORM_EDGE_X + platform_w * 0.5
	var body := _box(Vector3(platform_w, PLATFORM_Y + 0.7, length), Vector3(_sx(px), (PLATFORM_Y - 0.7) * 0.5, zc), mat_floor, "Platform")
	# Peron ön yüzü (koyu beton)
	_box(Vector3(0.05, PLATFORM_Y + 0.6, length), Vector3(_sx(PLATFORM_EDGE_X - 0.02), (PLATFORM_Y - 0.7) * 0.5, zc), world.mat_concrete_dark)
	# Kenar: koyu şerit + sarı çizgi + hissedilebilir yüzey
	_box(Vector3(0.45, 0.03, length), Vector3(_sx(PLATFORM_EDGE_X + 0.22), PLATFORM_Y + 0.015, zc), MaterialLib.proc("rubber", Color(0.2, 0.2, 0.22)), "", false)
	_box(Vector3(0.1, 0.035, length), Vector3(_sx(PLATFORM_EDGE_X + 0.5), PLATFORM_Y + 0.017, zc), world.mat_yellow, "", false)
	_box(Vector3(0.45, 0.03, length), Vector3(_sx(PLATFORM_EDGE_X + 0.8), PLATFORM_Y + 0.015, zc), MaterialLib.proc("tactile"), "", false)
	# Kolonlar
	var z := -6.0
	while z > -length + 4.0:
		if str(style["columns"]) == "round":
			var c := _prop("column", Vector3(_sx(PLATFORM_EDGE_X + 3.4), PLATFORM_Y, z))
			if c:
				c.scale = Vector3(1.0, (hall_h - PLATFORM_Y) / 4.3, 1.0)
		else:
			_box(Vector3(0.7, hall_h - PLATFORM_Y, 0.7), Vector3(_sx(PLATFORM_EDGE_X + 3.4), PLATFORM_Y + (hall_h - PLATFORM_Y) * 0.5, z), mat_wall)
			_box(Vector3(0.74, 0.3, 0.74), Vector3(_sx(PLATFORM_EDGE_X + 3.4), PLATFORM_Y + 0.15, z), mat_dark)
		# Kolon tabelası
		var board := _box(Vector3(0.04, 0.3, 0.6), Vector3(_sx(PLATFORM_EDGE_X + 3.4 - 0.37 * side_sign), PLATFORM_Y + 2.0, z), world.mat_sign)
		_label(str(data["short"]).to_upper(), Vector3(_sx(PLATFORM_EDGE_X + 3.4 - 0.4 * side_sign), PLATFORM_Y + 2.0, z), 26, Color(0.95, 0.95, 0.95), _facing_track())
		z -= 12.0

## Karşı yön peronu: döşeme, kenar şeritleri, hatlar arası kolon sırası, isim panoları, banklar
func _build_opposite_platform() -> void:
	var zc := -length * 0.5
	var edge := OPP_TRACK_X - PLATFORM_EDGE_X          # karşı peron kenarı (x)
	var far := track_wall_x + 0.3
	var pw := edge - far
	var px := (edge + far) * 0.5
	_box(Vector3(pw, PLATFORM_Y + 0.7, length), Vector3(_sx(px), (PLATFORM_Y - 0.7) * 0.5, zc), mat_floor, "PlatformOpp")
	_box(Vector3(0.05, PLATFORM_Y + 0.6, length), Vector3(_sx(edge + 0.02), (PLATFORM_Y - 0.7) * 0.5, zc), world.mat_concrete_dark)
	_box(Vector3(0.45, 0.03, length), Vector3(_sx(edge - 0.22), PLATFORM_Y + 0.015, zc), MaterialLib.proc("rubber", Color(0.2, 0.2, 0.22)), "", false)
	_box(Vector3(0.1, 0.035, length), Vector3(_sx(edge - 0.5), PLATFORM_Y + 0.017, zc), world.mat_yellow, "", false)
	_box(Vector3(0.45, 0.03, length), Vector3(_sx(edge - 0.8), PLATFORM_Y + 0.015, zc), MaterialLib.proc("tactile"), "", false)
	# Hatlar arası kolon sırası (tavanı taşır) + karşı peron kolonları
	var z := -6.0
	while z > -length + 4.0:
		_box(Vector3(0.6, hall_h + 0.9, 0.6), Vector3(_sx(OPP_TRACK_X * 0.5), (hall_h - 0.9) * 0.5, z), mat_wall)
		_box(Vector3(0.7, hall_h - PLATFORM_Y, 0.7), Vector3(_sx(edge - 3.4), PLATFORM_Y + (hall_h - PLATFORM_Y) * 0.5, z), mat_wall)
		_box(Vector3(0.74, 0.3, 0.74), Vector3(_sx(edge - 3.4), PLATFORM_Y + 0.15, z), mat_dark)
		z -= 12.0
	# Hatlar arası alçak ayırıcı duvar (kablolar/ekipman), ray seviyesinde
	_box(Vector3(0.3, 1.0, length), Vector3(_sx(OPP_TRACK_X * 0.5), 0.5, zc), world.mat_concrete_dark)
	# İsim panoları (karşı peron arka duvarı) + banklar
	var name_up := str(data["name"]).to_upper()
	var zz := -14.0
	while zz > -length + 10.0:
		_box(Vector3(0.1, 1.0, 7.2), Vector3(_sx(far + 0.07), PLATFORM_Y + 2.5, zz), world.mat_sign)
		_box(Vector3(0.11, 0.14, 7.2), Vector3(_sx(far + 0.07), PLATFORM_Y + 3.03, zz), mat_accent)
		_label(name_up, Vector3(_sx(far + 0.14), PLATFORM_Y + 2.58, zz), 76, Color(0.98, 0.98, 1.0), -_facing_track())
		_prop("bench", Vector3(_sx(far + 0.9), PLATFORM_Y, zz - 9.0), 0.0 if side_sign > 0 else PI)
		zz -= 24.0
	_box(Vector3(0.06, 0.4, length), Vector3(_sx(far + 0.03), PLATFORM_Y + 1.6, zc), mat_accent)

func _build_lights() -> void:
	var is_open := str(style["ceiling"]) == "canopy"
	var dens := Settings.light_density()
	var z := -3.0
	var i := 0
	while z > -length + 2.0:
		# Peron üstü armatür (prop) + ışık
		for lx in [PLATFORM_EDGE_X + 2.0, -0.9, OPP_TRACK_X - 0.9, OPP_TRACK_X - PLATFORM_EDGE_X - 2.0]:
			if lx < 0.0 and is_open:
				continue
			if lx < OPP_TRACK_X and i % 2 == 1:
				continue
			var p := _prop("ceiling_light", Vector3(_sx(lx), hall_h - 0.03, z))
			if p == null:
				_box(Vector3(0.25, 0.08, 1.2), Vector3(_sx(lx), hall_h - 0.1, z), mat_lamp, "", false)
			var make_light := true
			if dens < 0.6:
				make_light = i % 2 == 0 and lx > 0.0
			elif dens < 0.9:
				make_light = i % 2 == 0 or lx > 0.0
			if make_light:
				var light := OmniLight3D.new()
				light.light_color = style["light"]
				light.light_energy = float(style["light_energy"])
				light.omni_range = 11.0
				light.omni_attenuation = 1.2
				light.shadow_enabled = Settings.station_light_shadows() and lx > 0.0 and i % 2 == 0
				light.light_volumetric_fog_energy = 0.2
				light.position = Vector3(_sx(lx), hall_h - 0.35, z)
				add_child(light)
		z -= 6.0
		i += 1

func _build_signs() -> void:
	var fx := far_x()
	var name_up := str(data["name"]).to_upper()
	var z := -14.0
	var k := 0
	while z > -length + 10.0:
		# Büyük istasyon adı panosu (aydınlatmalı)
		_box(Vector3(0.1, 1.0, 7.2), Vector3(_sx(fx - 0.07), PLATFORM_Y + 2.5, z), world.mat_sign)
		_box(Vector3(0.11, 0.14, 7.2), Vector3(_sx(fx - 0.07), PLATFORM_Y + 3.03, z), mat_accent)
		_label(name_up, Vector3(_sx(fx - 0.14), PLATFORM_Y + 2.58, z), 76, Color(0.98, 0.98, 1.0), _facing_track())
		_label("ARS · HAT 4 · %s" % str(world.route.direction_label).to_upper(), Vector3(_sx(fx - 0.14), PLATFORM_Y + 2.16, z), 30, Color(0.6, 0.92, 0.88), _facing_track())
		# Reklam panoları (ışıklı çerçeve)
		var pz := z - 7.5
		if pz > -length + 6.0:
			var pm := mat_poster_a if k % 2 == 0 else mat_poster_b
			_box(Vector3(0.12, 1.85, 2.65), Vector3(_sx(fx - 0.06), PLATFORM_Y + 2.1, pz), world.mat_metal)
			_box(Vector3(0.06, 1.65, 2.45), Vector3(_sx(fx - 0.13), PLATFORM_Y + 2.1, pz), pm, "", false)
		z -= 24.0
		k += 1
	# Yön tabelaları (asılı, prop)
	var dir_text := "→  %s" % str(world.route.direction_label)
	var zz := -20.0
	while zz > -length + 15.0:
		var sf := _prop("sign_frame", Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.05, zz))
		if sf:
			_label(dir_text, Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.05, zz + 0.045), 32, Color(0.98, 0.98, 1.0), 0.0)
			_label(dir_text, Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.05, zz - 0.045), 32, Color(0.98, 0.98, 1.0), PI)
		zz -= 40.0
	# PIS ekranları (asılı, prop) — Godot metin
	var pz2 := -30.0
	while pz2 > -length + 12.0:
		var pis := _prop("pis_screen", Vector3(_sx(PLATFORM_EDGE_X + 1.3), hall_h - 1.6, pz2))
		if pis:
			for s in [1.0, -1.0]:
				var l := _label("", Vector3(_sx(PLATFORM_EDGE_X + 1.3), hall_h - 1.6, pz2 + 0.07 * s), 20, Color(1.0, 0.6, 0.15), 0.0 if s > 0 else PI)
				l.name = "PIS_%d_%s" % [int(-pz2), "A" if s > 0 else "B"]
				_pis_labels.append(l)
		pz2 -= 40.0
	# Aktarma bilgisi
	if data.has("transfer"):
		_box(Vector3(0.06, 0.55, 4.2), Vector3(_sx(fx - 0.06), PLATFORM_Y + 3.4, -length * 0.5), mat_accent)
		_label(str(data["transfer"]).to_upper(), Vector3(_sx(fx - 0.13), PLATFORM_Y + 3.4, -length * 0.5), 34, Color(1, 1, 1), _facing_track())
	# Saatler (iki yüzlü)
	var cz := -length * 0.5 + 10.0
	_box(Vector3(0.7, 0.34, 0.08), Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.7, cz), mat_dark)
	var c1 := _label("00:00", Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.7, cz + 0.045), 34, Color(1.0, 0.55, 0.1), 0.0)
	var c2 := _label("00:00", Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.7, cz - 0.045), 34, Color(1.0, 0.55, 0.1), PI)
	_clocks = [c1, c2]

func set_clock(text: String) -> void:
	for c in _clocks:
		c.text = text

func set_pis(text: String) -> void:
	for l in _pis_labels:
		l.text = text
		# Ekrana sığdır (ekran 1,0 m genişlik): en uzun satıra göre eşit ölçekle
		var f: Font = l.font if l.font else ThemeDB.fallback_font
		var w := 0.0
		for line in text.split("\n"):
			w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size)
		var k := 1.0 if w <= 0.94 or w <= 0.0 else 0.94 / w
		l.scale = Vector3(k, k, 1.0)

func _build_furniture() -> void:
	var fx := far_x()
	var z := -10.0
	var k := 0
	while z > -length + 8.0:
		var bx := _sx(PLATFORM_EDGE_X + platform_w - 0.9)
		_prop("bench", Vector3(bx, PLATFORM_Y, z), PI if side_sign > 0 else 0.0)
		# Bank oturma yerleri (3 kişilik, rayla yüz yüze); yaw: modelin +Z'si raya baksın
		for dz in [-0.55, 0.0, 0.55]:
			bench_seats.append({"pos": Vector3(bx - _sx(0.22), PLATFORM_Y + 0.45, z + dz), "yaw": _facing_track()})
		_prop("trash_bin", Vector3(bx, PLATFORM_Y, z - 1.6))
		if k == 1:
			_prop("vending", Vector3(_sx(fx - 0.6), PLATFORM_Y, z + 3.5), PI * 0.5 * side_sign)
		z -= 22.0
		k += 1
	_prop("fire_cabinet", Vector3(_sx(fx - 0.2), PLATFORM_Y + 0.6, -length + 9.0), PI * 0.5 * side_sign)

func _build_exits() -> void:
	var fx := far_x()
	var ex := _sx(PLATFORM_EDGE_X + platform_w - 1.6)
	var esc_z := -length + 12.0
	# Yürüyen merdiven: perondan geriye (-z yönünde) yükselir → tavan açıklığı + üst koridor
	var esc := _prop("escalator", Vector3(ex, PLATFORM_Y, esc_z), 0.0)
	# Üst çıkış koridoru (ışıklı, fayans): tavan açıklığının üstünde, geriye doğru
	var cor_z := esc_z - 9.5
	_box(Vector3(3.6, 3.2, 0.1), Vector3(ex, hall_h + 1.6, cor_z - 3.0), mat_wall)       # arka duvar
	for sx in [-1.75, 1.75]:
		_box(Vector3(0.1, 3.2, 6.5), Vector3(ex + sx, hall_h + 1.6, cor_z), mat_wall)      # yan duvarlar
	_box(Vector3(3.6, 0.1, 6.5), Vector3(ex, hall_h + 3.2, cor_z), world.mat_concrete_dark) # üst tavan
	_box(Vector3(0.8, 0.06, 3.0), Vector3(ex, hall_h + 3.1, cor_z), mat_lamp, "", false)
	var cl := OmniLight3D.new()
	cl.light_color = style["light"]
	cl.light_energy = 1.5
	cl.omni_range = 7.0
	cl.position = Vector3(ex, hall_h + 2.5, cor_z)
	add_child(cl)
	# ÇIKIŞ tabelası
	_box(Vector3(1.3, 0.42, 0.06), Vector3(ex, PLATFORM_Y + 2.7, esc_z + 1.8), world._mat(Color(0.08, 0.45, 0.2), 0.5, 0.0, Color(0.2, 0.9, 0.3), 0.9))
	_label("ÇIKIŞ  ↑", Vector3(ex, PLATFORM_Y + 2.7, esc_z + 1.84), 32, Color(1, 1, 1), 0.0)
	# Sabit merdiven (yanında)
	var stair_x := ex - _sx(2.6)
	for i in 14:
		_box(Vector3(1.6, 0.17, 0.32), Vector3(stair_x, PLATFORM_Y + 0.085 + i * 0.17, esc_z - i * 0.3), mat_floor)
	for sx in [-0.85, 0.85]:
		_box(Vector3(0.04, 0.9, 4.4), Vector3(stair_x + sx, PLATFORM_Y + 1.6, esc_z - 2.0), world.mat_metal).rotation.x = deg_to_rad(29.5)
	# Asansör (diğer uç)
	var el_z := -14.0
	_prop("elevator", Vector3(_sx(fx - 1.3), PLATFORM_Y, el_z), PI * 0.5 * side_sign)
	exit_positions = [Vector3(ex, PLATFORM_Y, esc_z + 1.5), Vector3(_sx(fx - 1.3) - _sx(1.4), PLATFORM_Y, el_z)]

## Stil ve istasyona özgü ek detaylar (istasyonlar birbirinin kopyası olmasın)
func _build_extras() -> void:
	var fx := far_x()
	var st := str(data.get("style", "modern"))
	var zc := -length * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(data["id"]))
	match st:
		"airport":
			# Uçuş bilgi totemi + saksılar + cam korkuluklu bekleme alanı
			var tz := zc + 6.0
			_box(Vector3(0.12, 2.2, 1.6), Vector3(_sx(PLATFORM_EDGE_X + 4.6), PLATFORM_Y + 1.1, tz), mat_dark, "FlightTotem")
			_box(Vector3(0.05, 1.3, 1.4), Vector3(_sx(PLATFORM_EDGE_X + 4.6 - 0.09 * side_sign), PLATFORM_Y + 1.45, tz), world._mat(Color(0.02, 0.03, 0.05), 0.3, 0.0, Color(0.1, 0.2, 0.35), 0.8), "", false)
			_label("UÇUŞ BİLGİ · FLIGHT INFO\nTK 2142  ANKARA   10:35  KAPI 204\nPC 1204  İZMİR    10:50  KAPI 211\nTK 1960  BERLİN   11:05  KAPI 302", Vector3(_sx(PLATFORM_EDGE_X + 4.6 - 0.13 * side_sign), PLATFORM_Y + 1.45, tz), 18, Color(1.0, 0.7, 0.2), _facing_track())
			for k in 4:
				var pz := -10.0 - k * 26.0
				if pz < -length + 6.0:
					break
				_prop_or_box("planter", Vector3(_sx(fx - 1.2), PLATFORM_Y, pz), Vector3(0.6, 0.5, 0.6), MaterialLib.proc("concrete_dark"))
				var leaf := _box(Vector3(0.9, 0.9, 0.9), Vector3(_sx(fx - 1.2), PLATFORM_Y + 0.95, pz), world._mat(Color(0.18, 0.42, 0.2), 0.9), "", true)
				leaf.scale = Vector3(1, 0.7, 1)
		"modern":
			# Dijital reklam totemleri (ışıklı) + bilet otomatı yanında bilgi panosu
			for k in 3:
				var pz := -18.0 - k * 30.0
				if pz < -length + 8.0:
					break
				_box(Vector3(0.14, 2.0, 0.9), Vector3(_sx(PLATFORM_EDGE_X + 4.4), PLATFORM_Y + 1.0, pz), mat_dark)
				var pm := mat_poster_a if (k + rng.randi_range(0, 1)) % 2 == 0 else mat_poster_b
				_box(Vector3(0.06, 1.7, 0.75), Vector3(_sx(PLATFORM_EDGE_X + 4.4 - 0.1 * side_sign), PLATFORM_Y + 1.1, pz), pm, "", false)
			_box(Vector3(0.08, 1.2, 2.2), Vector3(_sx(fx - 0.1), PLATFORM_Y + 1.8, -length + 20.0), world.mat_sign)
			_label("HAT 4 ÇALIŞMA SAATLERİ\n06:00 – 00:00 · Sefer aralığı 4 dk", Vector3(_sx(fx - 0.15), PLATFORM_Y + 1.8, -length + 20.0), 22, Color(0.95, 0.95, 1.0), _facing_track())
		"classic":
			# Duvar nişleri (tonozlu), mozaik pano, ikinci koyu bant
			_box(Vector3(0.05, 0.25, length), Vector3(_sx(fx - 0.03), PLATFORM_Y + 1.25, zc), world._mat(Color(0.35, 0.2, 0.12), 0.7))
			for k in 5:
				var pz := -12.0 - k * 22.0
				if pz < -length + 6.0:
					break
				_box(Vector3(0.25, 1.6, 1.2), Vector3(_sx(fx + 0.05), PLATFORM_Y + 1.9, pz), world._mat(Color(0.55, 0.45, 0.3), 0.8))
				_box(Vector3(0.08, 1.3, 1.0), Vector3(_sx(fx - 0.07), PLATFORM_Y + 1.9, pz), world._mat(Color(0.75, 0.3, 0.15) if k % 2 == 0 else Color(0.2, 0.35, 0.5), 0.6, 0.0), "", false)
		"deep":
			# Açık kablo tavaları (hat duvarı), acil telefon kutuları, büyük havalandırma ızgaraları
			_box(Vector3(0.3, 0.12, length), Vector3(_sx(fx + 0.1), hall_h - 1.2, zc), world.mat_metal)
			_box(Vector3(0.3, 0.12, length), Vector3(_sx(fx + 0.1), hall_h - 1.6, zc), world.mat_metal)
			for k in 3:
				var pz := -16.0 - k * 36.0
				if pz < -length + 8.0:
					break
				_box(Vector3(0.12, 0.45, 0.3), Vector3(_sx(fx - 0.06), PLATFORM_Y + 1.5, pz), world._mat(Color(0.85, 0.65, 0.1), 0.5))
				_label("ACİL\nTELEFON", Vector3(_sx(fx - 0.13), PLATFORM_Y + 1.5, pz), 14, Color(0.1, 0.1, 0.1), _facing_track())
				_box(Vector3(0.1, 1.0, 1.6), Vector3(_sx(fx - 0.05), hall_h - 2.4, pz - 6.0), world.mat_metal)
		_:
			pass
	# Her istasyon: farklı reklam/poster dizilimi (tohuma bağlı), yangın söndürücü noktası, acil çıkış işareti ek
	var ez := -length + 30.0
	_box(Vector3(0.6, 0.25, 0.05), Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.3, ez), world._mat(Color(0.08, 0.45, 0.2), 0.5, 0.0, Color(0.2, 0.9, 0.3), 0.9))
	_label("ÇIKIŞ ←", Vector3(_sx(PLATFORM_EDGE_X + 2.0), hall_h - 1.3, ez + 0.035), 18, Color(1, 1, 1), 0.0)

func _prop_or_box(name: String, pos: Vector3, size: Vector3, mat: Material) -> Node3D:
	var p := _prop(name, pos)
	if p:
		return p
	return _box(size, pos + Vector3(0, size.y * 0.5, 0), mat)

func _build_stop_board(local_stop: float) -> void:
	var z := -local_stop
	_box(Vector3(0.06, 2.1, 0.06), Vector3(_sx(PLATFORM_EDGE_X + 1.1), PLATFORM_Y + 1.05, z), world.mat_metal)
	_box(Vector3(0.6, 0.6, 0.05), Vector3(_sx(PLATFORM_EDGE_X + 1.1), PLATFORM_Y + 2.35, z), world.mat_sign)
	_label("DUR\n%d" % int(world.route.raw.get("train_cars", 4)), Vector3(_sx(PLATFORM_EDGE_X + 1.1), PLATFORM_Y + 2.35, z + 0.035), 56, Color(1.0, 0.85, 0.2), 0.0)
	_box(Vector3(1.6, 0.03, 0.1), Vector3(_sx(PLATFORM_EDGE_X + 1.1), PLATFORM_Y + 0.02, z), world.mat_yellow, "", false)

func _build_reflection_probe() -> void:
	if Settings.reflection_quality <= 0:
		return
	var probe := ReflectionProbe.new()
	var fx := far_x()
	var total_w := fx - track_wall_x
	probe.size = Vector3(total_w + 2.0, hall_h + 2.0, length + 4.0)
	probe.position = Vector3(_sx((fx + track_wall_x) * 0.5), hall_h * 0.5, -length * 0.5)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.8
	probe.box_projection = true
	probe.cull_mask = 1
	add_child(probe)

func random_platform_point(rng: RandomNumberGenerator) -> Vector3:
	var x0: float = platform_area["x_min"]
	var x1: float = platform_area["x_max"]
	var z0: float = platform_area["z_min"]
	var z1: float = platform_area["z_max"]
	return Vector3(rng.randf_range(minf(x0, x1), maxf(x0, x1)), PLATFORM_Y, rng.randf_range(z0, z1))
