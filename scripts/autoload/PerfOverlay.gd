extends CanvasLayer
## PerfOverlay — FPS sayacı (F3 ya da Ayarlar → Görüntü → "FPS sayacı"): anlık FPS, 2 sn ortalama,
## kare süresi (ms), grafik ön ayarı, çözünürlük (pencere × render ölçeği), renderer, çizim çağrısı.

var _label: Label
var _times: Array[float] = []
var _acc := 0.0
var _frames := 0
var _avg := 0.0
var _box: PanelContainer

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = PanelContainer.new()
	_box.position = Vector2(8, 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.72)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_box.add_theme_stylebox_override("panel", sb)
	add_child(_box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.85))
	_box.add_child(_label)
	visible = Settings.show_fps
	Settings.settings_applied.connect(func() -> void: visible = Settings.show_fps)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		Settings.show_fps = not Settings.show_fps
		visible = Settings.show_fps
		Settings.save_settings()

func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	_frames += 1
	if _acc >= 2.0:
		_avg = _frames / _acc
		_acc = 0.0
		_frames = 0
	if Engine.get_process_frames() % 10 != 0:
		return
	var fps := Engine.get_frames_per_second()
	var ms := delta * 1000.0
	var win := DisplayServer.window_get_size()
	var preset: String = str(Settings.PRESET_NAMES[Settings.quality]) if Settings.quality < Settings.PRESET_NAMES.size() else str(Settings.quality)
	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	var drawcalls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_label.text = "FPS %d  (ort. %.0f)   kare %.1f ms\n%s · %dx%d × %.2f · %s\nçizim %d · üçgen %dk · %s" % [
		fps, _avg if _avg > 0.0 else fps, ms, preset, win.x, win.y, Settings.render_scale, method.replace("forward_plus", "Forward+").replace("gl_compatibility", "Compat"),
		drawcalls, prims / 1000, RenderingServer.get_video_adapter_name().left(28)]
