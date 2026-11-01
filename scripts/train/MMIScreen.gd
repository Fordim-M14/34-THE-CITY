class_name MMIScreen
extends Node
## MMIScreen — kabindeki dijital makinist bilgi ekranı (SubViewport dokusu).
## Sayfalar: SÜRÜŞ · ARIZALAR · MERKEZ MESAJLARI · SEFER/YOLCU. Tab veya ekrana tıklayarak gezilir.
## Arıza sisteminden "blackout" alırsa ekran kararır.

const W := 512
const H := 356
const PAGES := ["SÜRÜŞ", "ARIZA", "MERKEZ", "SEFER"]

var train: TrainController
var route: RouteData
var mission: MissionManager
var traffic: TrafficManager
var faults: FaultManager
var passengers: PassengerManager
var page: int = 0
var blackout: bool = false
var flicker: bool = false

var _vp: SubViewport
var _root: Control
var _bg: ColorRect
var _title: Label
var _body: RichTextLabel
var _tabs: Label
var _timer := 0.0
var _blink := 0.0
var _tex: ImageTexture
var _copy_pending := false

func setup(p_train: TrainController, p_route: RouteData, p_mission: MissionManager, p_traffic: TrafficManager, p_faults: FaultManager, p_passengers: PassengerManager) -> void:
	train = p_train
	route = p_route
	mission = p_mission
	traffic = p_traffic
	faults = p_faults
	passengers = p_passengers
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root = Control.new()
	_root.size = Vector2(W, H)
	_vp.add_child(_root)
	_bg = ColorRect.new()
	_bg.size = Vector2(W, H)
	_bg.color = Color(0.02, 0.06, 0.08)
	_root.add_child(_bg)
	var header := ColorRect.new()
	header.size = Vector2(W, 34)
	header.color = Color(0.05, 0.25, 0.28)
	_root.add_child(header)
	_title = Label.new()
	_title.position = Vector2(10, 4)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.9, 1.0, 1.0))
	_root.add_child(_title)
	_tabs = Label.new()
	_tabs.position = Vector2(10, H - 26)
	_tabs.add_theme_font_size_override("font_size", 16)
	_tabs.add_theme_color_override("font_color", Color(0.5, 0.8, 0.8))
	_root.add_child(_tabs)
	_body = RichTextLabel.new()
	_body.position = Vector2(10, 40)
	_body.size = Vector2(W - 20, H - 70)
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_font_size_override("bold_font_size", 20)
	_body.add_theme_font_size_override("mono_font_size", 20)
	_body.add_theme_color_override("default_color", Color(0.85, 0.95, 0.95))
	_root.add_child(_body)

## Ekran dokusu: SubViewport görüntüsü düşük frekansta ImageTexture'a kopyalanır
## (ViewportTexture'ın Compatibility renderer'da 3B malzemede boş görünme sorununa karşı).
func get_texture() -> ImageTexture:
	if _tex == null:
		var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.02, 0.06, 0.08))
		_tex = ImageTexture.create_from_image(img)
		RenderingServer.frame_post_draw.connect(_copy_frame)
	return _tex

func _copy_frame() -> void:
	if not _copy_pending or _vp == null:
		return
	_copy_pending = false
	var img := _vp.get_texture().get_image()
	if img and img.get_size() == Vector2i(W, H):
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		_tex.update(img)

func next_page() -> void:
	page = (page + 1) % PAGES.size()
	_refresh()

func set_page(p: int) -> void:
	page = clampi(p, 0, PAGES.size() - 1)
	_refresh()

func _process(delta: float) -> void:
	_timer -= delta
	_blink += delta
	if Input.is_action_just_pressed("mmi_next") and not GameState.paused and GameState.phase != GameState.Phase.BRIEFING:
		next_page()
	if _timer <= 0.0:
		_timer = 0.15
		_refresh()
		_copy_pending = true

func _refresh() -> void:
	if blackout:
		_bg.color = Color(0.0, 0.0, 0.0)
		_title.text = ""
		_tabs.text = ""
		_body.text = ""
		return
	if flicker and fmod(_blink, 0.5) < 0.08:
		_bg.color = Color(0.0, 0.0, 0.0)
		_body.visible = false
		return
	_body.visible = true
	_bg.color = Color(0.02, 0.06, 0.08)
	var tabtxt := ""
	for i in PAGES.size():
		tabtxt += ("[%s]" % PAGES[i]) if i == page else (" %s " % PAGES[i])
		tabtxt += "   "
	_tabs.text = tabtxt + "        " + GameState.clock_text()
	match page:
		0: _page_drive()
		1: _page_faults()
		2: _page_messages()
		3: _page_service()

func _c(text: String, color: String) -> String:
	return "[color=%s]%s[/color]" % [color, text]

func _page_drive() -> void:
	_title.text = "SÜRÜŞ  ·  %s  ·  Sefer %s" % [route.line_name, str(GameState.mission.get("service_number", ""))]
	var v := train.speed_kmh()
	var lim := train.current_limit_kmh()
	var lines: Array[String] = []
	var vcol := "#ffffff"
	if v > lim + 3.0:
		vcol = "#ff4040"
	elif v > lim - 3.0:
		vcol = "#ffc040"
	lines.append("[b]HIZ[/b]  %s km/s     [b]LİMİT[/b]  %s" % [_c("%3d" % int(round(v)), vcol), _c(str(int(lim)), "#80ffd0")])
	var up := route.get_upcoming_limit(train.offset, 500.0)
	if not up.is_empty():
		lines.append("  ▼ %d m sonra %d km/s" % [int(up["distance"]), int(up["limit_kmh"])])
	if train.temp_speed_restriction_kmh > 0.0:
		lines.append(_c("  GEÇİCİ KISIT %d km/s" % int(train.temp_speed_restriction_kmh), "#ffc040"))
	var tgt := mission.target_station()
	if not tgt.is_empty():
		var d: float = float(tgt["stop_pos"]) - train.offset
		lines.append("[b]HEDEF[/b]  %s   %s" % [str(tgt["name"]), ("%+.1f m" % (-d)) if absf(d) < 80.0 else ("%d m" % int(d))])
		lines.append("  Peron: %s   Plan: %s" % ["SAĞ" if tgt.get("door_side") == "right" else "SOL", _fmt_t(mission.planned_arrival_s(tgt))])
	var sg := route.get_next_signal(train.offset)
	if not sg.is_empty():
		var sig: TrackSignal = train.world.signals_by_id.get(str(sg["id"]))
		var asp := sig.aspect if sig else "?"
		var col: String = {"red": "#ff4040", "yellow": "#ffc040", "green": "#40ff80"}.get(asp, "#ffffff")
		lines.append("[b]SİNYAL[/b]  %s  %d m  %s  (%s)" % [str(sg["id"]), int(float(sg["pos"]) - train.offset), _c({"red": "KIRMIZI", "yellow": "SARI", "green": "YEŞİL"}.get(asp, asp), col), traffic.signal_reason(sig) if sig else ""])
	lines.append("[b]KAPI[/b]  Sol %s · Sağ %s     [b]YÖN[/b] %s" % [train.doors.state_text("left"), train.doors.state_text("right"), {1: "İLERİ", 0: "NÖTR", -1: "GERİ"}[train.reverser]])
	lines.append("[b]KOL[/b]  %s     [b]SÜRE[/b] %s" % [_lever_text(), _fmt_t(GameState.mission_time)])
	if train.emergency_active():
		lines.append(_c("ACİL FREN: " + " + ".join(train.active_reason_names()), "#ff4040"))
		var chk: Dictionary = train.can_reset_emergency()
		lines.append(_c("  " + str(chk["message"]), "#ffc040"))
	elif train.atp_warning:
		lines.append(_c("ATP: HIZ SINIRI AŞILDI", "#ffc040"))
	var active := faults.active_faults() if faults else []
	if not active.is_empty():
		lines.append(_c("ARIZA: %s  (ARIZA sayfası)" % str(active[0]["title"]), "#ff9040"))
	_body.text = "\n".join(lines)

func _lever_text() -> String:
	var lv := train.lever
	if absf(lv) < 0.03:
		return "NÖTR"
	if lv > 0.0:
		return "ÇEKİŞ %d%%" % int(round(lv * 100.0))
	return "FREN %d%%" % int(round(-lv * 100.0))

func _fmt_t(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

func _page_faults() -> void:
	_title.text = "ARIZA VE UYARILAR"
	var lines: Array[String] = []
	if faults == null:
		_body.text = "—"
		return
	var active := faults.active_faults()
	if active.is_empty():
		lines.append(_c("Aktif arıza yok. Tüm sistemler normal.", "#40ff80"))
	for f in active:
		lines.append(_c("■ %s" % str(f["title"]), "#ff9040"))
		lines.append("  " + str(f["description"]))
		lines.append(_c("  Prosedür: " + str(f["procedure"]), "#ffe080"))
		if f.get("progress", "") != "":
			lines.append("  Durum: " + str(f["progress"]))
	lines.append("")
	lines.append("Çözülen arıza: %d / %d" % [int(Scoring.stats.get("faults_resolved", 0)), int(Scoring.stats.get("faults", 0))])
	_body.text = "\n".join(lines)

func _page_messages() -> void:
	_title.text = "MERKEZ (OCC) MESAJLARI"
	var lines: Array[String] = []
	if traffic == null or traffic.messages.is_empty():
		lines.append("Mesaj yok.")
	else:
		var start := maxi(0, traffic.messages.size() - 6)
		for i in range(traffic.messages.size() - 1, start - 1, -1):
			var m: Dictionary = traffic.messages[i]
			lines.append("%s  %s" % [_c(str(m["time"]), "#80c0ff"), str(m["text"])])
	if traffic and traffic.pending_ack != "":
		lines.append(_c("► ONAY BEKLİYOR — F / ONAY düğmesi", "#ffc040"))
	var li := traffic.lead_info() if traffic else {}
	if not li.is_empty():
		lines.append("")
		lines.append("Öndeki sefer %s: %s%s, %d km/s, %d m önde" % [str(li["service"]), "istasyonda " if li["state"] == "dwell" else "yolda", (" (" + str(li["station"]) + ")") if li["state"] == "dwell" else "", int(li["speed_kmh"]), int(li["distance"])])
	_body.text = "\n".join(lines)

func _page_service() -> void:
	_title.text = "SEFER  ·  %s → %s" % [str(route.get_start_station()["name"]), route.terminus]
	var lines: Array[String] = []
	for s in route.stations:
		var i: int = int(s["index"])
		var mark := "  "
		if i < mission.stop_index:
			mark = "✓ "
		elif i == mission.stop_index:
			mark = "● "
		var plan := _fmt_t(route.schedule_for(i))
		var done := ""
		for st in Scoring.stats.get("stops", []):
			if str(st["id"]) == str(s["id"]):
				done = "  %+d sn  %+.2f m" % [int(st["delta"]), float(st["err"])]
		lines.append("%s%-26s %s%s" % [mark, str(s["name"]), plan, done])
	if passengers:
		lines.append("")
		lines.append("Doluluk: %d%%  (%d yolcu)   Bindi: %d  İndi: %d" % [int(passengers.load_factor() * 100.0), passengers.onboard, int(Scoring.stats.get("passengers_boarded", 0)), int(Scoring.stats.get("passengers_alighted", 0))])
	var tsr := traffic.tsr_text() if traffic else ""
	if tsr != "":
		lines.append(_c(tsr, "#ffc040"))
	_body.text = "\n".join(lines)
