class_name TextureFactory
extends RefCounted
## TextureFactory — dış dosya gerektirmeyen prosedürel dokular (beton, fayans, balast,
## metal, reklam panosu). Sonuçlar önbelleklenir; malzemeler triplanar UV kullanır
## (BoxMesh'lerde dikişsiz kaplama).

static var _cache: Dictionary = {}

static func _noise(seed: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 4
	return n

static func concrete(size: int = 256, base: Color = Color(0.52, 0.52, 0.54), seed: int = 1) -> ImageTexture:
	var key := "concrete_%d_%s_%d" % [size, base.to_html(), seed]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n1 := _noise(seed, 0.02)
	var n2 := _noise(seed + 7, 0.12)
	for y in size:
		for x in size:
			var v := 0.5 + 0.18 * n1.get_noise_2d(x, y) + 0.08 * n2.get_noise_2d(x, y)
			# Hafif kir lekeleri
			var stain := maxf(0.0, n1.get_noise_2d(x * 0.5 + 300, y * 0.5) - 0.25) * 0.6
			var c := base * (0.75 + 0.5 * v) * (1.0 - stain)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func tiles(size: int = 256, tile_px: int = 64, base: Color = Color(0.85, 0.85, 0.82), grout: Color = Color(0.35, 0.35, 0.36), seed: int = 3, accent: Color = Color.TRANSPARENT, accent_every: int = 0) -> ImageTexture:
	var key := "tiles_%d_%d_%s_%s_%d_%s_%d" % [size, tile_px, base.to_html(), grout.to_html(), seed, accent.to_html(), accent_every]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := _noise(seed, 0.05)
	var tiles_per := int(size / tile_px)
	for y in size:
		for x in size:
			var tx := x % tile_px
			var ty := y % tile_px
			var ix := int(x / tile_px)
			var iy := int(y / tile_px)
			var is_grout := tx < 2 or ty < 2
			var c: Color
			if is_grout:
				c = grout
			else:
				var shade := 0.92 + 0.08 * n.get_noise_2d(ix * 17 + tx * 0.3, iy * 23 + ty * 0.3)
				c = base * shade
				if accent_every > 0 and ((ix + iy * tiles_per) % accent_every == 0):
					c = accent * shade
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func ballast(size: int = 256, seed: int = 5) -> ImageTexture:
	var key := "ballast_%d_%d" % [size, seed]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n1 := _noise(seed, 0.25)
	var n2 := _noise(seed + 1, 0.6)
	for y in size:
		for x in size:
			var v := 0.45 + 0.25 * n1.get_noise_2d(x, y) + 0.2 * n2.get_noise_2d(x, y)
			v = clampf(v, 0.15, 0.8)
			img.set_pixel(x, y, Color(v * 0.95, v * 0.9, v * 0.85))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func brushed_metal(size: int = 128, base: Color = Color(0.6, 0.62, 0.65), seed: int = 9) -> ImageTexture:
	var key := "metal_%d_%s" % [size, base.to_html()]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var n := _noise(seed, 0.9)
	for y in size:
		for x in size:
			var v := 0.9 + 0.1 * n.get_noise_2d(x * 0.05, y * 4.0)
			img.set_pixel(x, y, base * v)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Reklam panosu benzeri soyut afiş (kurgusal; marka içermez)
static func poster(size: int = 256, seed: int = 11) -> ImageTexture:
	var key := "poster_%d_%d" % [size, seed]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var palette := [
		Color(0.95, 0.55, 0.15), Color(0.15, 0.55, 0.75), Color(0.85, 0.2, 0.45),
		Color(0.25, 0.7, 0.45), Color(0.95, 0.85, 0.3), Color(0.35, 0.3, 0.7),
	]
	var bg: Color = palette[rng.randi_range(0, palette.size() - 1)]
	img.fill(bg)
	for i in rng.randi_range(3, 6):
		var c: Color = palette[rng.randi_range(0, palette.size() - 1)]
		var rx := rng.randi_range(0, size - 40)
		var ry := rng.randi_range(0, size - 40)
		var rw := rng.randi_range(30, size / 2)
		var rh := rng.randi_range(30, size / 2)
		img.fill_rect(Rect2i(rx, ry, mini(rw, size - rx), mini(rh, size - ry)), c)
	# "Metin" çizgileri
	var ty := size - 60
	for i in 3:
		img.fill_rect(Rect2i(20, ty + i * 14, rng.randi_range(60, size - 40), 7), Color(1, 1, 1, 1))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Hazır malzeme oluşturucu: triplanar kaplama
static func material(tex: Texture2D, scale: float = 0.5, roughness: float = 0.9, metallic: float = 0.0, tint: Color = Color.WHITE, two_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
