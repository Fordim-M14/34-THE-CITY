extends Node
## Settings v3 — kullanıcı ayarları (autoload). Grafik ön ayarları (Düşük/Orta/Yüksek/Ultra)
## ve tek tek seçenekler; ses; kamera (FOV, koltuk, sallanma); fare; tuş atamaları.
## user://settings.cfg'ye kaydedilir. Değişiklikler settings_applied ile sahneye duyurulur.

signal settings_applied

const PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const QUALITY_NAMES := ["Düşük", "Orta", "Yüksek", "Ultra"]
const AA_NAMES := ["Kapalı", "FXAA", "MSAA 2x", "MSAA 4x", "TAA", "MSAA 4x + FXAA"]
const SHADOW_NAMES := ["Kapalı", "Düşük", "Orta", "Yüksek"]
const TEXTURE_NAMES := ["Düşük", "Orta", "Yüksek"]
const REFLECTION_NAMES := ["Kapalı", "Düşük (SSR)", "Yüksek (SSR)"]
const VIEW_NAMES := ["Kısa", "Orta", "Uzun"]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]

# Video
var resolution_index: int = 2
var fullscreen: bool = false
var vsync: bool = true
var fps_limit_index: int = 0
var quality: int = 2                 # ön ayar (uygulandığında tek tek seçenekleri yazar)
var render_scale: float = 1.0
var aa_mode: int = 3
var shadow_quality: int = 2
var texture_quality: int = 2
var reflection_quality: int = 1
var view_distance: int = 1
var fog_enabled: bool = true
var ssao_enabled: bool = true
var volumetric_fog: bool = true
var glow_enabled: bool = true
var sdfgi_enabled: bool = false
# Ses
var master_volume: float = 0.9
var sfx_volume: float = 0.9
var announce_volume: float = 1.0
# Kamera / giriş
var mouse_sensitivity: float = 1.0
var fov: float = 75.0
var seat_height: float = 0.0        # -0.12 .. +0.15 m
var seat_forward: float = 0.0       # 0 .. 0.35 m
var camera_sway: float = 0.6        # 0 .. 1 (gövde sallanması)
var camera_shake: bool = true       # ray titreşimi / kalkış-fren hissi / viraj
var control_mode: int = 0           # 0 gerçekçi, 1 kolay (W hızlan, S fren, E kapılar)
var bindings: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply()

# ---------------------------------------------------------------------------

const PRESET_NAMES := ["Düşük", "Orta", "Yüksek", "Ultra"]
var show_fps: bool = false

const PRESETS := [
	{"render_scale": 0.75, "aa_mode": 1, "shadow_quality": 0, "texture_quality": 0, "reflection_quality": 0, "view_distance": 0,
		"fog_enabled": true, "ssao_enabled": false, "volumetric_fog": false, "glow_enabled": false, "sdfgi_enabled": false},
	{"render_scale": 1.0, "aa_mode": 2, "shadow_quality": 1, "texture_quality": 1, "reflection_quality": 0, "view_distance": 1,
		"fog_enabled": true, "ssao_enabled": true, "volumetric_fog": false, "glow_enabled": true, "sdfgi_enabled": false},
	{"render_scale": 1.0, "aa_mode": 3, "shadow_quality": 2, "texture_quality": 2, "reflection_quality": 1, "view_distance": 1,
		"fog_enabled": true, "ssao_enabled": true, "volumetric_fog": true, "glow_enabled": true, "sdfgi_enabled": false},
	{"render_scale": 1.0, "aa_mode": 5, "shadow_quality": 3, "texture_quality": 2, "reflection_quality": 2, "view_distance": 2,
		"fog_enabled": true, "ssao_enabled": true, "volumetric_fog": true, "glow_enabled": true, "sdfgi_enabled": true},
]

func apply_preset(p: int) -> void:
	quality = clampi(p, 0, 3)
	var d: Dictionary = PRESETS[quality]
	for k in d:
		set(k, d[k])

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		apply_preset(2)
		return
	resolution_index = int(cfg.get_value("video", "resolution_index", 2))
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	vsync = bool(cfg.get_value("video", "vsync", true))
	fps_limit_index = int(cfg.get_value("video", "fps_limit_index", 0))
	quality = int(cfg.get_value("video", "quality", 2))
	apply_preset(quality)
	render_scale = float(cfg.get_value("video", "render_scale", render_scale))
	aa_mode = int(cfg.get_value("video", "aa_mode", aa_mode))
	shadow_quality = int(cfg.get_value("video", "shadow_quality", shadow_quality))
	texture_quality = int(cfg.get_value("video", "texture_quality", texture_quality))
	reflection_quality = int(cfg.get_value("video", "reflection_quality", reflection_quality))
	view_distance = int(cfg.get_value("video", "view_distance", view_distance))
	fog_enabled = bool(cfg.get_value("video", "fog", fog_enabled))
	ssao_enabled = bool(cfg.get_value("video", "ssao", ssao_enabled))
	volumetric_fog = bool(cfg.get_value("video", "volumetric_fog", volumetric_fog))
	glow_enabled = bool(cfg.get_value("video", "glow", glow_enabled))
	sdfgi_enabled = bool(cfg.get_value("video", "sdfgi", sdfgi_enabled))
	master_volume = float(cfg.get_value("audio", "master", 0.9))
	sfx_volume = float(cfg.get_value("audio", "sfx", 0.9))
	announce_volume = float(cfg.get_value("audio", "announce", 1.0))
	mouse_sensitivity = float(cfg.get_value("input", "mouse_sensitivity", 1.0))
	fov = float(cfg.get_value("camera", "fov", 75.0))
	seat_height = float(cfg.get_value("camera", "seat_height", 0.0))
	seat_forward = float(cfg.get_value("camera", "seat_forward", 0.0))
	camera_sway = float(cfg.get_value("camera", "sway", 0.6))
	camera_shake = bool(cfg.get_value("camera", "shake", true))
	control_mode = int(cfg.get_value("input", "control_mode", 0))
	show_fps = bool(cfg.get_value("video", "show_fps", false))
	bindings = {}
	if cfg.has_section("bindings"):
		for k in cfg.get_section_keys("bindings"):
			bindings[k] = int(cfg.get_value("bindings", k))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "resolution_index", resolution_index)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_limit_index", fps_limit_index)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "aa_mode", aa_mode)
	cfg.set_value("video", "shadow_quality", shadow_quality)
	cfg.set_value("video", "texture_quality", texture_quality)
	cfg.set_value("video", "reflection_quality", reflection_quality)
	cfg.set_value("video", "view_distance", view_distance)
	cfg.set_value("video", "fog", fog_enabled)
	cfg.set_value("video", "ssao", ssao_enabled)
	cfg.set_value("video", "volumetric_fog", volumetric_fog)
	cfg.set_value("video", "glow", glow_enabled)
	cfg.set_value("video", "sdfgi", sdfgi_enabled)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "announce", announce_volume)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("camera", "fov", fov)
	cfg.set_value("camera", "seat_height", seat_height)
	cfg.set_value("camera", "seat_forward", seat_forward)
	cfg.set_value("camera", "sway", camera_sway)
	cfg.set_value("camera", "shake", camera_shake)
	cfg.set_value("input", "control_mode", control_mode)
	cfg.set_value("video", "show_fps", show_fps)
	for k in bindings:
		cfg.set_value("bindings", k, bindings[k])
	cfg.save(PATH)

func apply() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		if fullscreen:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
			if DisplayServer.window_get_size() != res:
				DisplayServer.window_set_size(res)
				var screen := DisplayServer.screen_get_size()
				DisplayServer.window_set_position((screen - res) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_LIMITS[clampi(fps_limit_index, 0, FPS_LIMITS.size() - 1)]
	# Viewport
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if render_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.5)
	vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	match aa_mode:
		1: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		2: vp.msaa_3d = Viewport.MSAA_2X
		3: vp.msaa_3d = Viewport.MSAA_4X
		4: vp.use_taa = true
		5:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.positional_shadow_atlas_size = [0, 2048, 4096, 8192][clampi(shadow_quality, 0, 3)]
	vp.texture_mipmap_bias = [0.5, 0.0, -0.25][clampi(texture_quality, 0, 2)]
	# Ses
	AudioManager.master_volume = master_volume
	AudioManager.sfx_volume = sfx_volume
	AudioManager.announce_volume = announce_volume
	AudioManager.apply_settings()
	# Tuşlar
	for action in bindings:
		GameState.rebind_action(action, bindings[action])
	settings_applied.emit()

# --- Sahnelerin kullandığı türetilmiş değerler ---

func sun_shadows() -> bool:
	return shadow_quality >= 1

func headlight_shadows() -> bool:
	return shadow_quality >= 2

func station_light_shadows() -> bool:
	return shadow_quality >= 3

func interior_lights() -> bool:
	return quality >= 1

func visible_range() -> float:
	return [500.0, 800.0, 1300.0][clampi(view_distance, 0, 2)]

func shadow_distance() -> float:
	return [40.0, 80.0, 140.0, 220.0][clampi(shadow_quality, 0, 3)]

func light_density() -> float:
	return [0.5, 0.75, 1.0, 1.0][clampi(quality, 0, 3)]
