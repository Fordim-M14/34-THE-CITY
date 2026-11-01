class_name UITheme
extends RefCounted
## UITheme — menüler için kod ile üretilen ortak tema (koyu zemin, turkuaz vurgu).

const ACCENT := Color(0.16, 0.72, 0.68)
const ACCENT2 := Color(0.95, 0.78, 0.15)
const BG := Color(0.05, 0.07, 0.09, 0.96)
const TEXT := Color(0.92, 0.95, 0.97)
const MUTED := Color(0.55, 0.62, 0.68)

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.09, 0.13, 0.16)
	btn.border_width_left = 3
	btn.border_color = ACCENT
	btn.set_corner_radius_all(4)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	var btn_h := btn.duplicate()
	btn_h.bg_color = Color(0.12, 0.22, 0.25)
	var btn_p := btn.duplicate()
	btn_p.bg_color = Color(0.16, 0.5, 0.48)
	var btn_d := btn.duplicate()
	btn_d.bg_color = Color(0.08, 0.09, 0.1)
	btn_d.border_color = Color(0.25, 0.27, 0.3)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("focus", "Button", btn_h)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font_size("font_size", "Button", 20)
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_width_left = 6
	panel.border_color = ACCENT
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 32
	panel.content_margin_right = 32
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 18)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.15, 0.2, 0.24)
	slider_bg.set_corner_radius_all(3)
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = ACCENT
	slider_fill.set_corner_radius_all(3)
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	var ob := btn.duplicate()
	t.set_stylebox("normal", "OptionButton", ob)
	t.set_stylebox("hover", "OptionButton", btn_h)
	t.set_stylebox("pressed", "OptionButton", btn_p)
	t.set_stylebox("focus", "OptionButton", btn_h)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_font_size("font_size", "OptionButton", 18)
	var cb := btn.duplicate()
	t.set_stylebox("normal", "CheckButton", cb)
	t.set_stylebox("hover", "CheckButton", btn_h)
	t.set_stylebox("pressed", "CheckButton", btn_p)
	t.set_color("font_color", "CheckButton", TEXT)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.08, 0.1, 0.12)
	le.border_width_bottom = 2
	le.border_color = ACCENT
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font_size("font_size", "LineEdit", 20)
	_theme = t
	return t

static func title(text: String, size: int = 36, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, cb: Callable, min_w: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func dim(parent: Node, alpha: float = 0.6) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, alpha)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(d)
	return d

static func card(parent: Node, min_w: float = 760.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(min_w, 0)
	pc.theme = theme()
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	return vb
