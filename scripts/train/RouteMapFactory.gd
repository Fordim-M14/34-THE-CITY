class_name RouteMapFactory
extends RefCounted
## RouteMapFactory — kapı üstü hat haritası ve reklam panosu dokuları (Image API ile; headless
## güvenli). Metinler Label3D ile üstüne eklenir (add_route_labels / add_ad_labels).

const AD_COUNT := 4
const ADS := [
	["ARS KART", "Tek kartla tüm hat · arskart.ars", Color(0.1, 0.45, 0.55), Color(0.05, 0.2, 0.28)],
	["BOĞAZ'IN ALTINDAN", "Havalimanı — Kadıköy 46 dakika", Color(0.55, 0.25, 0.1), Color(0.3, 0.12, 0.05)],
	["SESSİZ YOLCULUK", "Kulaklık kullanın · yüksek sesle konuşmayın", Color(0.2, 0.3, 0.45), Color(0.1, 0.14, 0.24)],
	["BAGAJINIZI GÖZETİNİZ", "Şüpheli eşyayı personele bildirin", Color(0.5, 0.45, 0.1), Color(0.28, 0.24, 0.05)],
]

static var _route_tex: ImageTexture
static var _ad_tex: Dictionary = {}

static func route_map_texture() -> ImageTexture:
	if _route_tex:
		return _route_tex
	var w := 1024
	var h := 112
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.96, 0.96, 0.95))
	var route: RouteData = GameState.route_forward if GameState.route_forward else GameState.route
	var n: int = route.stations.size() if route else 6
	var x0 := 70
	var x1 := w - 70
	var y := 62
	# Hat çizgisi (ARS turkuaz)
	img.fill_rect(Rect2i(x0, y - 5, x1 - x0, 10), Color(0.08, 0.52, 0.5))
	for i in n:
		var cx := int(lerpf(x0, x1, float(i) / maxf(1, n - 1)))
		_circle(img, cx, y, 12, Color(0.08, 0.52, 0.5))
		_circle(img, cx, y, 8, Color(1, 1, 1))
	# Uç istasyon kareleri
	img.fill_rect(Rect2i(x0 - 14, y - 14, 28, 28), Color(0.08, 0.52, 0.5))
	img.fill_rect(Rect2i(x1 - 14, y - 14, 28, 28), Color(0.08, 0.52, 0.5))
	img.fill_rect(Rect2i(x0 - 9, y - 9, 18, 18), Color(1, 1, 1))
	img.fill_rect(Rect2i(x1 - 9, y - 9, 18, 18), Color(1, 1, 1))
	# Üst şerit
	img.fill_rect(Rect2i(0, 0, w, 14), Color(0.08, 0.52, 0.5))
	_route_tex = ImageTexture.create_from_image(img)
	return _route_tex

static func _circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(cx + dx, cy + dy, col)

static func ad_texture(i: int) -> ImageTexture:
	i = i % AD_COUNT
	if _ad_tex.has(i):
		return _ad_tex[i]
	var w := 512
	var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var a: Color = ADS[i][2]
	var b: Color = ADS[i][3]
	for x in w:
		var t := float(x) / w
		var c := a.lerp(b, t)
		for yy in h:
			img.set_pixel(x, yy, c)
	# Sol logo bloğu
	img.fill_rect(Rect2i(8, 8, 64, h - 16), Color(1, 1, 1, 0.9))
	img.fill_rect(Rect2i(16, 16, 48, h - 32), a)
	var t := ImageTexture.create_from_image(img)
	_ad_tex[i] = t
	return t

## Hat haritası üstüne istasyon adları (Label3D). plane: 1.3 x 0.14 m, yerel +Y normal.
static func add_route_labels(plane: MeshInstance3D, current_index: int = -1) -> void:
	var route: RouteData = GameState.route_forward if GameState.route_forward else GameState.route
	if route == null:
		return
	var n: int = route.stations.size()
	var x0 := -0.65 + 1.3 * 70.0 / 1024.0
	var x1 := 0.65 - 1.3 * 70.0 / 1024.0
	for i in n:
		var st: Dictionary = route.stations[i]
		var l := Label3D.new()
		l.text = str(st.get("short", st.get("name", "")))
		l.font_size = 16
		l.pixel_size = 0.0011
		l.modulate = Color(0.12, 0.12, 0.14) if i != current_index else Color(0.85, 0.1, 0.1)
		l.rotation_degrees = Vector3(-90, 0, 0)
		var cx := lerpf(x0, x1, float(i) / maxf(1, n - 1))
		# Metni yukarı/aşağı sırayla yerleştir (çakışmasın)
		var zy := -0.038 if i % 2 == 0 else 0.042
		l.position = Vector3(cx, 0.002, zy)
		plane.add_child(l)
	var title := Label3D.new()
	title.text = "HAT 4 · HAVALİMANI — KADIKÖY"
	title.font_size = 14
	title.pixel_size = 0.0009
	title.modulate = Color(1, 1, 1)
	title.rotation_degrees = Vector3(-90, 0, 0)
	title.position = Vector3(0, 0.002, -0.062)
	plane.add_child(title)

static func add_ad_labels(plane: MeshInstance3D, i: int) -> void:
	i = i % AD_COUNT
	var head := Label3D.new()
	head.text = ADS[i][0]
	head.font_size = 30
	head.pixel_size = 0.0014
	head.modulate = Color(1, 1, 1)
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0.08, 0.002, -0.03)
	plane.add_child(head)
	var sub := Label3D.new()
	sub.text = ADS[i][1]
	sub.font_size = 16
	sub.pixel_size = 0.001
	sub.modulate = Color(0.92, 0.92, 0.9)
	sub.rotation_degrees = Vector3(-90, 0, 0)
	sub.position = Vector3(0.08, 0.002, 0.03)
	plane.add_child(sub)
