class_name SettingsMenu
extends Control
## SettingsMenu v3 — sekmeler: Görüntü (ön ayar + tek tek seçenekler), Ses, Kamera, Tuşlar.

signal closed

var _rebinding_action := ""
var _rebind_button: Button
var _bind_buttons: Dictionary = {}
var _status: Label
var _video_controls: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	var vb := UITheme.card(self, 980)
	vb.add_child(UITheme.title("Ayarlar", 32))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(900, 520)
	tabs.add_theme_font_size_override("font_size", 18)
	vb.add_child(tabs)
	tabs.add_child(_video_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_camera_tab())
	tabs.add_child(_keys_tab())
	_status = UITheme.label("", 14, UITheme.ACCENT2)
	vb.add_child(_status)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	hb.add_child(UITheme.button("Kaydet ve kapat", func() -> void:
		Settings.save_settings()
		closed.emit()
	, 240))

func _grid(cols: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 8)
	return g

func _option(grid: GridContainer, text: String, items: Array, selected: int, cb: Callable) -> OptionButton:
	grid.add_child(UITheme.label(text, 16))
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(selected, 0, items.size() - 1)
	ob.item_selected.connect(cb)
	grid.add_child(ob)
	return ob

func _toggle(grid: GridContainer, text: String, value: bool, cb: Callable) -> CheckButton:
	grid.add_child(UITheme.label(text, 16))
	var c := CheckButton.new()
	c.button_pressed = value
	c.text = "Açık" if value else "Kapalı"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "Açık" if on else "Kapalı"
		cb.call(on))
	grid.add_child(c)
	return c

func _slider(grid: GridContainer, text: String, value: float, minv: float, maxv: float, step: float, fmt: String, cb: Callable) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var lbl := UITheme.label(text, 16)
	var val := UITheme.label(fmt % value, 14, UITheme.MUTED)
	val.custom_minimum_size = Vector2(60, 0)
	grid.add_child(lbl)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 24)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % v
		cb.call(v))
	hb.add_child(s)
	hb.add_child(val)
	grid.add_child(hb)
	return s

# ---------------------------------------------------------------------------

func _video_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "Görüntü"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	var g := _grid(2)
	vb.add_child(g)
	_option(g, "Ekran çözünürlüğü", Settings.RESOLUTIONS.map(func(r): return "%d × %d" % [r.x, r.y]), Settings.resolution_index, func(i: int) -> void:
		Settings.resolution_index = i
		Settings.apply())
	_toggle(g, "Tam ekran", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply())
	_toggle(g, "FPS sayacı (F3)", Settings.show_fps, func(on: bool) -> void:
		Settings.show_fps = on
		Settings.apply())
	_toggle(g, "V-Sync", Settings.vsync, func(on: bool) -> void:
		Settings.vsync = on
		Settings.apply())
	_option(g, "FPS sınırı", Settings.FPS_LIMITS.map(func(f): return "Sınırsız" if f == 0 else str(f)), Settings.fps_limit_index, func(i: int) -> void:
		Settings.fps_limit_index = i
		Settings.apply())
	vb.add_child(UITheme.label("GRAFİK ÖN AYARI — tek tek seçenekleri de değiştirebilirsiniz", 14, UITheme.ACCENT))
	var g2 := _grid(2)
	vb.add_child(g2)
	_option(g2, "Kalite ön ayarı", Settings.QUALITY_NAMES, Settings.quality, func(i: int) -> void:
		Settings.apply_preset(i)
		Settings.apply()
		_refresh_video_controls())
	_video_controls["render_scale"] = _slider(g2, "Render ölçeği", Settings.render_scale, 0.5, 1.5, 0.05, "%.2f", func(v: float) -> void:
		Settings.render_scale = v
		Settings.apply())
	_video_controls["aa_mode"] = _option(g2, "Kenar yumuşatma", Settings.AA_NAMES, Settings.aa_mode, func(i: int) -> void:
		Settings.aa_mode = i
		Settings.apply())
	_video_controls["shadow_quality"] = _option(g2, "Gölge kalitesi", Settings.SHADOW_NAMES, Settings.shadow_quality, func(i: int) -> void:
		Settings.shadow_quality = i
		Settings.apply())
	_video_controls["texture_quality"] = _option(g2, "Doku kalitesi", Settings.TEXTURE_NAMES, Settings.texture_quality, func(i: int) -> void:
		Settings.texture_quality = i
		Settings.apply())
	_video_controls["reflection_quality"] = _option(g2, "Yansıma kalitesi", Settings.REFLECTION_NAMES, Settings.reflection_quality, func(i: int) -> void:
		Settings.reflection_quality = i
		Settings.apply())
	_video_controls["view_distance"] = _option(g2, "Görüş mesafesi", Settings.VIEW_NAMES, Settings.view_distance, func(i: int) -> void:
		Settings.view_distance = i
		Settings.apply())
	_video_controls["fog_enabled"] = _toggle(g2, "Sis (derinlik)", Settings.fog_enabled, func(on: bool) -> void:
		Settings.fog_enabled = on
		Settings.apply())
	_video_controls["volumetric_fog"] = _toggle(g2, "Hacimsel sis", Settings.volumetric_fog, func(on: bool) -> void:
		Settings.volumetric_fog = on
		Settings.apply())
	_video_controls["ssao_enabled"] = _toggle(g2, "SSAO (ortam kapatma)", Settings.ssao_enabled, func(on: bool) -> void:
		Settings.ssao_enabled = on
		Settings.apply())
	_video_controls["glow_enabled"] = _toggle(g2, "Parlama (glow)", Settings.glow_enabled, func(on: bool) -> void:
		Settings.glow_enabled = on
		Settings.apply())
	_video_controls["sdfgi_enabled"] = _toggle(g2, "SDFGI (dinamik GI, ağır)", Settings.sdfgi_enabled, func(on: bool) -> void:
		Settings.sdfgi_enabled = on
		Settings.apply())
	vb.add_child(UITheme.label("Not: Değişiklikler anında uygulanır. Yansıma probları ve ışık yoğunluğu yeni seferde güncellenir.", 13, UITheme.MUTED))
	return sc

func _refresh_video_controls() -> void:
	var c := _video_controls
	if c.has("render_scale"): c["render_scale"].set_value_no_signal(Settings.render_scale)
	if c.has("aa_mode"): c["aa_mode"].selected = Settings.aa_mode
	if c.has("shadow_quality"): c["shadow_quality"].selected = Settings.shadow_quality
	if c.has("texture_quality"): c["texture_quality"].selected = Settings.texture_quality
	if c.has("reflection_quality"): c["reflection_quality"].selected = Settings.reflection_quality
	if c.has("view_distance"): c["view_distance"].selected = Settings.view_distance
	for k in ["fog_enabled", "volumetric_fog", "ssao_enabled", "glow_enabled", "sdfgi_enabled"]:
		if c.has(k):
			var v: bool = Settings.get(k)
			c[k].set_pressed_no_signal(v)
			c[k].text = "Açık" if v else "Kapalı"

func _audio_tab() -> Control:
	var vb := VBoxContainer.new()
	vb.name = "Ses"
	var g := _grid(2)
	vb.add_child(g)
	_slider(g, "Ana ses", Settings.master_volume, 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply())
	_slider(g, "Efektler (motor, fren, kapı)", Settings.sfx_volume, 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.apply())
	_slider(g, "Anonslar", Settings.announce_volume, 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void:
		Settings.announce_volume = v
		Settings.apply())
	return vb

func _camera_tab() -> Control:
	var vb := VBoxContainer.new()
	vb.name = "Kamera"
	var g := _grid(2)
	vb.add_child(g)
	_slider(g, "Görüş açısı (FOV)", Settings.fov, 65.0, 100.0, 1.0, "%.0f°", func(v: float) -> void:
		Settings.fov = v
		Settings.apply())
	_slider(g, "Koltuk yüksekliği (m)", Settings.seat_height, -0.12, 0.15, 0.01, "%+.2f", func(v: float) -> void:
		Settings.seat_height = v
		Settings.apply())
	_slider(g, "Koltuk ileri (m)", Settings.seat_forward, 0.0, 0.35, 0.01, "%.2f", func(v: float) -> void:
		Settings.seat_forward = v
		Settings.apply())
	_slider(g, "Kamera sallanması", Settings.camera_sway, 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void:
		Settings.camera_sway = v
		Settings.apply())
	_slider(g, "Fare hassasiyeti", Settings.mouse_sensitivity, 0.2, 2.5, 0.05, "%.2f", func(v: float) -> void:
		Settings.mouse_sensitivity = v
		Settings.apply())
	_toggle(g, "Kamera titreşimleri (kalkış/fren, ray, viraj, yüksek hız)", Settings.camera_shake, func(on: bool) -> void:
		Settings.camera_shake = on
		Settings.apply())
	vb.add_child(UITheme.label("Yakınlaştırma: sağ fare tuşu veya Z (basılı). Bakışı ortala: C. Koltuktan kalk/otur: X.", 14, UITheme.MUTED))
	return vb

func _keys_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "Tuşlar"
	var vb := VBoxContainer.new()
	sc.add_child(vb)
	var mg := _grid(2)
	vb.add_child(mg)
	_option(mg, "Sürüş kontrol modu", ["Gerçekçi (kol kademeli: W/S kolu hareket ettirir, Q/E kapı tarafı)", "Kolay (W basılı: hızlan, S basılı: fren, E: peron kapıları, hız limiti otomatik)"], Settings.control_mode, func(i: int) -> void:
		Settings.control_mode = i
		Settings.apply())
	vb.add_child(UITheme.label("Değiştirmek için tıklayıp yeni tuşa basın (Esc: iptal)", 14, UITheme.ACCENT))
	var kg := GridContainer.new()
	kg.columns = 4
	kg.add_theme_constant_override("h_separation", 16)
	kg.add_theme_constant_override("v_separation", 6)
	vb.add_child(kg)
	for action in GameState.DEFAULT_BINDINGS:
		kg.add_child(UITheme.label(str(GameState.BINDING_LABELS.get(action, action)), 14))
		var b := Button.new()
		b.text = GameState.binding_text(action)
		b.custom_minimum_size = Vector2(150, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void: _start_rebind(action, b))
		kg.add_child(b)
		_bind_buttons[action] = b
	vb.add_child(UITheme.label("Sabit: Shift+R acil fren sıfırlama · Sol tık kabin etkileşimi · Sağ tık yakınlaştırma · Fare tekerleği kol", 13, UITheme.MUTED))
	vb.add_child(UITheme.button("Varsayılan tuşlar", func() -> void:
		Settings.bindings = {}
		for a in GameState.DEFAULT_BINDINGS:
			GameState._set_action_keys(a, GameState.DEFAULT_BINDINGS[a])
			_bind_buttons[a].text = GameState.binding_text(a)
		GameState.rebind_action("zoom", KEY_Z)
		_status.text = "Tuşlar varsayılana döndü"
	, 220))
	return sc

func _start_rebind(action: String, b: Button) -> void:
	_rebinding_action = action
	_rebind_button = b
	b.text = "Tuşa basın…"
	_status.text = "%s için yeni tuş bekleniyor" % str(GameState.BINDING_LABELS.get(action, action))

func _unhandled_input(event: InputEvent) -> void:
	if _rebinding_action == "":
		return
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			_rebind_button.text = GameState.binding_text(_rebinding_action)
			_status.text = "İptal edildi"
		else:
			var kc: int = event.physical_keycode
			Settings.bindings[_rebinding_action] = kc
			GameState.rebind_action(_rebinding_action, kc)
			_rebind_button.text = GameState.binding_text(_rebinding_action)
			_status.text = "%s → %s" % [str(GameState.BINDING_LABELS.get(_rebinding_action, "")), OS.get_keycode_string(kc)]
		_rebinding_action = ""
