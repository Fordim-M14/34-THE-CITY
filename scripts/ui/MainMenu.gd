extends Node3D
## MainMenu — ana menü: Kariyere devam / Yeni kariyer / Serbest sürüş / Görevler /
## Ayarlar / Çıkış. Arka planda dönen T-400 kabini (3B) gösterilir.

var ui: CanvasLayer
var root: Control
var _panel: Control
var _train_visual: TrainVisual
var _cam: Camera3D
var _angle := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.paused = false
	get_tree().paused = false
	_build_background()
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.theme()
	ui.add_child(root)
	_show_main()

func _build_background() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.6, 0.7)
	e.ambient_light_energy = 0.35
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	_train_visual = TrainVisual.new()
	add_child(_train_visual)
	var cars := _train_visual.build(1, TrainController.CAR_LENGTH)
	cars[0].position = Vector3(0, 0, 0)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.09, 0.1)
	fm.roughness = 0.3
	fm.metallic = 0.2
	pm.material = fm
	floor_mi.mesh = pm
	add_child(floor_mi)
	for p in [Vector3(6, 6, -8), Vector3(-6, 5, 4), Vector3(0, 7, 12)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_energy = 3.0
		l.omni_range = 25.0
		l.light_color = Color(0.9, 0.95, 1.0)
		add_child(l)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	_train_visual.set_headlights(true)

func _process(delta: float) -> void:
	_angle += delta * 0.12
	var r := 16.0
	var eye := Vector3(sin(_angle) * r, 3.0 + sin(_angle * 0.5) * 0.5, -11.0 + cos(_angle) * r)
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, 2.0, -9.0) - eye, Vector3.UP), eye)

func _clear_panel() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_panel)

# ---------------------------------------------------------------------------
# Ana ekran

func _show_main() -> void:
	_clear_panel()
	var vb := VBoxContainer.new()
	vb.position = Vector2(80, 80)
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	vb.add_child(UITheme.label("ARS · ANADOLU RAYLI SİSTEMLER İŞLETMESİ", 16, UITheme.ACCENT))
	vb.add_child(UITheme.title("M4 VARDİYA", 64))
	vb.add_child(UITheme.label("İstanbul metro makinist simülasyonu · v0.4.1", 16, UITheme.MUTED))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 20)
	vb.add_child(sp)
	var sv := SaveGame.load_save()
	if not sv.is_empty():
		vb.add_child(UITheme.button("Kaldığın yerden devam et  ▸  " + SaveGame.describe(sv), func() -> void:
			var d := SaveGame.load_save()
			if d.is_empty():
				_show_main()
				return
			GameState.apply_mission(d["mission"])
			SaveGame.resume_data = d
			get_tree().change_scene_to_file("res://scenes/main/Main.tscn")))
	if Career.has_profile:
		var p := Career.profile
		vb.add_child(UITheme.label("%s · %s (Seviye %d) · %d XP · %d ₺ (sanal)" % [str(p["name"]), Career.rank_name(), Career.level(), int(p["xp"]), int(p["money"])], 18, UITheme.ACCENT2))
		vb.add_child(UITheme.button("Kariyere devam et  ▸", _show_mission_select))
	else:
		vb.add_child(UITheme.label("Kayıtlı kariyer yok", 16, UITheme.MUTED))
	vb.add_child(UITheme.button("Yeni kariyer", _show_new_career))
	var free_btn := UITheme.button("Serbest sürüş" + ("" if Career.is_unlocked("free") else "   (Seviye 3'te açılır)"), _show_free_drive)
	free_btn.disabled = not Career.is_unlocked("free")
	vb.add_child(free_btn)
	var tasks_btn := UITheme.button("Görevler, başarımlar ve istatistikler", _show_tasks)
	tasks_btn.disabled = not Career.has_profile
	vb.add_child(tasks_btn)
	vb.add_child(UITheme.button("Ayarlar", _show_settings))
	vb.add_child(UITheme.button("Oyundan çık", func() -> void: get_tree().quit()))
	var foot := UITheme.label("Kurgusal işletme. Resmî Metro İstanbul ürünü değildir. İstanbul M4 hattından esinlenilmiştir.", 13, UITheme.MUTED)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(80, -40)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.add_child(foot)

# ---------------------------------------------------------------------------
# Yeni kariyer

func _show_new_career() -> void:
	_clear_panel()
	UITheme.dim(_panel, 0.5)
	var vb := UITheme.card(_panel, 640)
	vb.add_child(UITheme.title("Yeni kariyer", 32))
	vb.add_child(UITheme.label("Makinist adı:", 16, UITheme.MUTED))
	var le := LineEdit.new()
	le.placeholder_text = "Örn. Ali Yılmaz"
	le.max_length = 24
	vb.add_child(le)
	if Career.has_profile:
		vb.add_child(UITheme.label("Uyarı: mevcut kariyer (%s) silinecek." % str(Career.profile["name"]), 15, Color(1, 0.5, 0.4)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	hb.add_child(UITheme.button("Başla", func() -> void:
		var n := le.text.strip_edges()
		if n == "":
			n = "Makinist"
		Career.new_profile(n)
		_show_mission_select()
	, 200))
	hb.add_child(UITheme.button("Geri", _show_main, 200))
	le.grab_focus()

# ---------------------------------------------------------------------------
# Sefer seçimi

var _sel_direction := "forward"
var _sel_time := 0
var _sel_faults := true
var _sel_traffic := true
var _sel_passengers := true

func _show_mission_select(free_mode: bool = false) -> void:
	_clear_panel()
	UITheme.dim(_panel, 0.5)
	var vb := UITheme.card(_panel, 820)
	vb.add_child(UITheme.title("Serbest sürüş" if free_mode else "Vardiya seçimi", 32))
	var route := GameState.route_forward
	vb.add_child(UITheme.label("%s · %s" % [route.line_name, route.train_model], 16, UITheme.ACCENT))
	# Yön
	var hb1 := HBoxContainer.new()
	hb1.add_theme_constant_override("separation", 10)
	vb.add_child(hb1)
	hb1.add_child(UITheme.label("Yön:", 18))
	var dir_opt := OptionButton.new()
	dir_opt.add_item("%s → %s (gidiş)" % [str(route.stations[0]["name"]), route.terminus])
	dir_opt.add_item("%s → %s (dönüş)%s" % [route.terminus, str(route.stations[0]["name"]), "" if (free_mode or Career.is_unlocked("reverse")) else "  — Seviye 2"])
	dir_opt.set_item_disabled(1, not (free_mode or Career.is_unlocked("reverse")))
	dir_opt.selected = 0
	hb1.add_child(dir_opt)
	# Saat
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 10)
	vb.add_child(hb2)
	hb2.add_child(UITheme.label("Vardiya saati:", 18))
	var time_opt := OptionButton.new()
	var times := [["06:10 — Sabah erken", 6 * 3600 + 10 * 60, "none"], ["08:05 — Zirve saat", 8 * 3600 + 5 * 60, "rush"],
		["11:30 — Gündüz", 11 * 3600 + 30 * 60, "none"], ["17:40 — Akşam zirvesi", 17 * 3600 + 40 * 60, "rush"],
		["21:15 — Akşam", 21 * 3600 + 15 * 60, "night"], ["23:40 — Gece son sefer", 23 * 3600 + 40 * 60, "night"]]
	for i in times.size():
		var t: Array = times[i]
		var locked: bool = (str(t[2]) != "none") and not free_mode and not Career.is_unlocked(str(t[2]))
		time_opt.add_item(str(t[0]) + ("   — Seviye %d" % (4 if t[2] == "rush" else 3) if locked else ""))
		time_opt.set_item_disabled(i, locked)
	time_opt.selected = 2
	hb2.add_child(time_opt)
	# Seçenekler
	var hb3 := HBoxContainer.new()
	hb3.add_theme_constant_override("separation", 10)
	vb.add_child(hb3)
	var cb_f := CheckButton.new()
	cb_f.text = "Arızalar"
	cb_f.button_pressed = true
	var cb_t := CheckButton.new()
	cb_t.text = "Hat trafiği"
	cb_t.button_pressed = true
	var cb_p := CheckButton.new()
	cb_p.text = "Yolcular"
	cb_p.button_pressed = true
	hb3.add_child(cb_f)
	hb3.add_child(cb_t)
	hb3.add_child(cb_p)
	if not free_mode:
		vb.add_child(UITheme.label("Kariyer modunda tarife ve puanlama kariyere işlenir. Arızalar kapatılırsa ödüller %20 azalır.", 14, UITheme.MUTED))
	# Tarife özeti
	var sched := ""
	for s in route.stations:
		sched += "%s %s   " % [str(s["short"]), "%d:%02d" % [int(s["schedule_s"]) / 60, int(s["schedule_s"]) % 60]]
	vb.add_child(UITheme.label("Tarife (dk:sn): " + sched, 14, UITheme.MUTED))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	hb.add_child(UITheme.button("Vardiyaya başla  ▸", func() -> void:
		var m := GameState.default_mission()
		m["direction"] = "reverse" if dir_opt.selected == 1 else "forward"
		m["start_time_s"] = int(times[time_opt.selected][1])
		m["mode"] = "free" if free_mode else "career"
		m["faults_enabled"] = cb_f.button_pressed
		m["traffic_enabled"] = cb_t.button_pressed
		m["passengers_enabled"] = cb_p.button_pressed
		m["service_number"] = Career.next_service_number() if Career.has_profile else "4107"
		if Career.has_profile:
			Career.save_profile()
		GameState.start_mission(m)
	, 260))
	hb.add_child(UITheme.button("Geri", _show_main, 200))

func _show_free_drive() -> void:
	_show_mission_select(true)

# ---------------------------------------------------------------------------
# Görevler / başarımlar / istatistik

func _show_tasks() -> void:
	_clear_panel()
	UITheme.dim(_panel, 0.5)
	var vb := UITheme.card(_panel, 900)
	var p := Career.profile
	vb.add_child(UITheme.title("%s — %s" % [str(p["name"]), Career.rank_name()], 30))
	vb.add_child(UITheme.label("Seviye %d · %d XP (sonraki seviyeye %d XP) · %d ₺ (sanal)" % [Career.level(), int(p["xp"]), Career.xp_to_next(), int(p["money"])], 16, UITheme.ACCENT2))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	vb.add_child(hb)
	# Sol: görevler
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	hb.add_child(left)
	left.add_child(UITheme.label("GÜNLÜK GÖREVLER", 15, UITheme.ACCENT))
	for t in p["daily"]["tasks"]:
		left.add_child(_task_line(t))
	left.add_child(UITheme.label("HAFTALIK GÖREVLER", 15, UITheme.ACCENT))
	for t in p["weekly"]["tasks"]:
		left.add_child(_task_line(t))
	left.add_child(UITheme.label("KİLİTLER", 15, UITheme.ACCENT))
	for u in Career.unlocks():
		left.add_child(UITheme.label("%s Sv.%d  %s" % ["✓" if u["unlocked"] else "🔒", int(u["level"]), str(u["title"])], 14, UITheme.TEXT if u["unlocked"] else UITheme.MUTED))
	# Sağ: başarımlar + istatistik
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	hb.add_child(right)
	right.add_child(UITheme.label("BAŞARIMLAR (%d/%d)" % [(p["achievements"] as Array).size(), Career.ACHIEVEMENTS.size()], 15, UITheme.ACCENT))
	for id in Career.ACHIEVEMENTS:
		var a: Dictionary = Career.ACHIEVEMENTS[id]
		var got: bool = id in p["achievements"]
		right.add_child(UITheme.label("%s %s — %s" % ["★" if got else "☆", str(a["title"]), str(a["desc"])], 13, UITheme.TEXT if got else UITheme.MUTED))
	right.add_child(UITheme.label("İSTATİSTİKLER", 15, UITheme.ACCENT))
	for l in Career.stats_summary():
		right.add_child(UITheme.label(l, 13))
	var hist: Array = p["history"]
	if hist.size() > 0:
		right.add_child(UITheme.label("SON SEFERLER", 15, UITheme.ACCENT))
		for i in mini(5, hist.size()):
			var h: Dictionary = hist[i]
			right.add_child(UITheme.label("Sefer %s · %s · %d (%s)%s" % [str(h["service"]), "gidiş" if h["direction"] == "forward" else "dönüş", int(h["score"]), str(h["grade"]), "  ✗" if str(h.get("failed", "")) != "" else ""], 13))
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 10)
	vb.add_child(hb2)
	hb2.add_child(UITheme.button("Geri", _show_main, 200))
	hb2.add_child(UITheme.button("Kariyeri sil", func() -> void:
		Career.delete_profile()
		_show_main()
	, 200))

func _task_line(t: Dictionary) -> Label:
	var done: bool = t.get("done", false)
	var txt := "%s %s  (%s/%s)  +%d XP +%d ₺" % ["✓" if done else "□", str(t["title"]), str(int(float(t.get("progress", 0.0)))), str(t["goal"]), int(t["xp"]), int(t["money"])]
	return UITheme.label(txt, 14, UITheme.TEXT if not done else UITheme.ACCENT2)

# ---------------------------------------------------------------------------

func _show_settings() -> void:
	_clear_panel()
	UITheme.dim(_panel, 0.5)
	var sm := SettingsMenu.new()
	sm.closed.connect(_show_main)
	_panel.add_child(sm)
