extends CanvasLayer
## HUD — kabin üstü bilgi katmanı: hız, limit, kol, yön, sinyal (nedeniyle), hedef istasyon,
## kapılar, sefer saati/tarife, acil fren durumu ve sıfırlama talimatı, merkez mesajları,
## nişangâh ve bakılan kontrolün adı, olay mesajları.

@onready var speed_label: Label = $Root/BottomPanel/HBox/SpeedBox/SpeedLabel
@onready var limit_label: Label = $Root/BottomPanel/HBox/SpeedBox/LimitLabel
@onready var lever_value: Label = $Root/BottomPanel/HBox/LeverBox/LeverValue
@onready var lever_bar: ProgressBar = $Root/BottomPanel/HBox/LeverBox/LeverBar
@onready var reverser_label: Label = $Root/BottomPanel/HBox/LeverBox/ReverserLabel
@onready var emergency_label: Label = $Root/BottomPanel/HBox/LeverBox/EmergencyLabel
@onready var next_station_label: Label = $Root/BottomPanel/HBox/RouteBox/NextStationLabel
@onready var distance_label: Label = $Root/BottomPanel/HBox/RouteBox/DistanceLabel
@onready var signal_label: Label = $Root/BottomPanel/HBox/RouteBox/SignalLabel
@onready var stop_label: Label = $Root/BottomPanel/HBox/RouteBox/StopLabel
@onready var doors_left_label: Label = $Root/BottomPanel/HBox/DoorsBox/DoorsLeftLabel
@onready var doors_right_label: Label = $Root/BottomPanel/HBox/DoorsBox/DoorsRightLabel
@onready var platform_side_label: Label = $Root/BottomPanel/HBox/DoorsBox/PlatformSideLabel
@onready var line_label: Label = $Root/TopLeft/LineLabel
@onready var clock_label: Label = $Root/TopLeft/ClockLabel
@onready var warning_label: Label = $Root/Warning
@onready var hint_label: Label = $Root/Hint
@onready var messages: VBoxContainer = $Root/Messages
@onready var crosshair: Label = $Root/Crosshair
@onready var crosshair_label: Label = $Root/CrosshairLabel
@onready var center_msg: PanelContainer = $Root/CenterMsg
@onready var center_msg_label: Label = $Root/CenterMsg/CenterMsgLabel

var train: TrainController
var route: RouteData
var mission: MissionManager
var traffic: TrafficManager
var faults: FaultManager
var passengers: PassengerManager
var _blink: float = 0.0
var _emergency_shown: bool = false
var _msg_style: StyleBoxFlat
var _center_timer := 0.0
var _center_ack := false

const COL_OK := Color(0.95, 0.97, 1.0)
const COL_WARN := Color(1.0, 0.75, 0.2)
const COL_BAD := Color(1.0, 0.3, 0.25)
const COL_GOOD := Color(0.35, 0.95, 0.5)
const COL_ACCENT := Color(0.45, 0.88, 0.84)

func _ready() -> void:
	_msg_style = StyleBoxFlat.new()
	_msg_style.bg_color = Color(0.04, 0.06, 0.08, 0.75)
	_msg_style.set_corner_radius_all(4)
	_msg_style.content_margin_left = 10
	_msg_style.content_margin_right = 10
	_msg_style.content_margin_top = 5
	_msg_style.content_margin_bottom = 5
	Scoring.penalty_added.connect(_on_penalty)
	Scoring.event_logged.connect(_on_event)

func bind(p_train: TrainController, p_route: RouteData, p_mission: MissionManager, p_traffic: TrafficManager, p_faults: FaultManager, p_passengers: PassengerManager) -> void:
	train = p_train
	route = p_route
	mission = p_mission
	traffic = p_traffic
	faults = p_faults
	passengers = p_passengers
	line_label.text = "ARS · %s · SEFER %s · %s%s" % [route.line_name.to_upper(), str(GameState.mission.get("service_number", "")), route.direction_label.to_upper(), "  ·  SERBEST SÜRÜŞ" if GameState.is_free_mode() else ""]
	_refresh_keys_hint()
	Settings.settings_applied.connect(_refresh_keys_hint)

func _refresh_keys_hint() -> void:
	var keys := get_node_or_null("Root/Help") as Label
	if keys == null:
		for l in find_children("*", "Label", true, false):
			if str(l.text).begins_with("W/S kol") or str(l.text).begins_with("W hızlan"):
				keys = l
				break
	if keys == null:
		return
	if Settings.control_mode == 1:
		keys.text = "W hızlan · S fren · E kapılar · Space ACİL · Shift+R reset · F onay · L far · H korna · X kalk/otur · Tab MMI · Esc menü"
	else:
		keys.text = "W/S kol · N nötr · Space ACİL · Shift+R reset · Q/E kapı · R yön · F onay · L far · K ışık · H korna · X kalk/otur · Tab MMI · M fare · Esc menü"

func set_hint(text: String) -> void:
	hint_label.text = text

func set_stop_text(text: String) -> void:
	stop_label.text = text

func set_crosshair_label(text: String) -> void:
	crosshair_label.text = text
	crosshair.modulate = Color(1, 0.9, 0.5) if text != "" else Color(1, 1, 1, 0.6)

func push_center_message(text: String, requires_ack: bool) -> void:
	center_msg_label.text = text + ("\n[F] ile onaylayın" if requires_ack else "")
	center_msg.visible = true
	_center_timer = 12.0 if not requires_ack else 999.0
	_center_ack = requires_ack
	if train:
		train.visual.set_lamp("message", true)

func _process(delta: float) -> void:
	if train == null:
		return
	_blink += delta
	var blink_on := fmod(_blink, 0.8) < 0.4
	crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and GameState.phase != GameState.Phase.BRIEFING

	# Hız
	var v := train.speed_kmh()
	var limit := train.current_limit_kmh()
	speed_label.text = str(int(round(v)))
	if v > limit + 3.0:
		speed_label.add_theme_color_override("font_color", COL_BAD if blink_on else COL_WARN)
	elif v > limit - 3.0:
		speed_label.add_theme_color_override("font_color", COL_WARN)
	else:
		speed_label.add_theme_color_override("font_color", COL_OK)
	var up := route.get_upcoming_limit(train.offset, 400.0)
	var ltxt := "Limit %d" % int(limit)
	if train.temp_speed_restriction_kmh > 0.0:
		ltxt += " (geçici)"
	if not up.is_empty():
		ltxt += "  ·  %d m sonra %d" % [int(up["distance"]), int(up["limit_kmh"])]
	limit_label.text = ltxt

	# Kol
	var lv := train.lever
	lever_bar.value = lv * 100.0
	if absf(lv) < 0.03:
		lever_value.text = "NÖTR"
		lever_value.add_theme_color_override("font_color", COL_OK)
	elif lv > 0.0:
		lever_value.text = "ÇEKİŞ %d%%" % int(round(lv * 100.0))
		lever_value.add_theme_color_override("font_color", COL_GOOD)
	else:
		lever_value.text = "FREN %d%%" % int(round(-lv * 100.0))
		lever_value.add_theme_color_override("font_color", COL_WARN)
	var rev_names := {1: "İLERİ", 0: "NÖTR", -1: "GERİ"}
	var flags := ""
	if train.traction_cut:
		flags += "  ⚡KESİK"
	if train.traction_factor < 1.0:
		flags += "  ÇEKİŞ %d%%" % int(train.traction_factor * 100.0)
	if train.brake_factor < 1.0:
		flags += "  FREN %d%%" % int(train.brake_factor * 100.0)
	reverser_label.text = "Yön: %s  (R)%s" % [rev_names[train.reverser], flags]
	if train.emergency_active():
		emergency_label.text = ("● ACİL FREN: " + " + ".join(train.active_reason_names())) if blink_on else "● ACİL FREN"
	else:
		emergency_label.text = ""

	# Rota / hedef istasyon
	var tgt := mission.target_station() if mission else route.get_next_station(train.offset)
	if tgt.is_empty():
		next_station_label.text = "—"
		distance_label.text = ""
	else:
		next_station_label.text = str(tgt["name"])
		var d: float = float(tgt["stop_pos"]) - train.offset
		if absf(d) < 60.0:
			distance_label.text = "Duruş noktasına %+.1f m" % (-d)
			distance_label.add_theme_color_override("font_color", COL_ACCENT)
		else:
			distance_label.text = "Duruş noktasına %d m" % int(d)
			distance_label.add_theme_color_override("font_color", COL_OK)
		platform_side_label.text = "Peron tarafı: %s" % ("SAĞ" if tgt.get("door_side", "right") == "right" else "SOL")
		if mission and not GameState.is_free_mode():
			var plan := mission.planned_arrival_s(tgt)
			var delta_s := GameState.mission_time - plan
			stop_label.text = "Plan %02d:%02d  (%s%d sn)" % [int(plan) / 60, int(plan) % 60, "+" if delta_s >= 0 else "−", int(absf(delta_s))]
			stop_label.add_theme_color_override("font_color", COL_WARN if absf(delta_s) > route.schedule_tolerance else COL_ACCENT)
	var sg := route.get_next_signal(train.offset)
	if sg.is_empty():
		signal_label.text = "Sinyal: —"
	else:
		var sig: TrackSignal = train.world.signals_by_id.get(str(sg["id"]))
		var aspect := sig.aspect if sig else "?"
		var names := {"red": "KIRMIZI", "yellow": "SARI", "green": "YEŞİL"}
		var reason := traffic.signal_reason(sig) if (traffic and sig) else ""
		signal_label.text = "Sinyal %s · %d m · %s%s" % [str(sg["id"]), int(float(sg["pos"]) - train.offset), names.get(aspect, aspect), (" (" + reason + ")") if aspect != "green" else ""]
		match aspect:
			"red": signal_label.add_theme_color_override("font_color", COL_BAD)
			"yellow": signal_label.add_theme_color_override("font_color", COL_WARN)
			_: signal_label.add_theme_color_override("font_color", COL_GOOD)

	# Kapılar
	doors_left_label.text = "SOL   %s" % train.doors.state_text("left")
	doors_right_label.text = "SAĞ   %s" % train.doors.state_text("right")
	doors_left_label.add_theme_color_override("font_color", COL_WARN if train.doors.is_open("left") else COL_OK)
	doors_right_label.add_theme_color_override("font_color", COL_WARN if train.doors.is_open("right") else COL_OK)

	# Saat
	var t := GameState.mission_time
	var load_txt := ""
	if passengers:
		load_txt = "  ·  doluluk %d%%" % int(passengers.load_factor() * 100.0)
	clock_label.text = "Saat %s  ·  sefer süresi %02d:%02d%s" % [GameState.clock_text(), int(t) / 60, int(t) % 60, load_txt]

	# Uyarı / acil fren talimatı
	if train.emergency_active():
		var chk: Dictionary = train.can_reset_emergency()
		var head := "ACİL FREN DEVREDE — " + " + ".join(train.active_reason_names())
		warning_label.text = head if blink_on else ""
		if chk["ok"]:
			hint_label.text = "Acil fren sıfırlanabilir: Shift+R (veya kabindeki ACİL RESET düğmesi)"
		else:
			hint_label.text = str(chk["message"])
		_emergency_shown = true
	elif train.atp_warning:
		warning_label.text = "HIZ SINIRI AŞILDI  (%d / %d)" % [int(v), int(limit)] if blink_on else ""
	else:
		warning_label.text = ""
	if _emergency_shown and not train.emergency_active():
		_emergency_shown = false
		hint_label.text = mission.hint if mission else ""
	# Merkez mesajı
	if center_msg.visible:
		_center_timer -= delta
		if _center_ack and traffic and traffic.pending_ack == "":
			_center_timer = minf(_center_timer, 4.0)
			_center_ack = false
		if _center_timer <= 0.0:
			center_msg.visible = false
			train.visual.set_lamp("message", false)

func _on_penalty(_code: String, points: int, text: String) -> void:
	_push_message("−%d  %s" % [points, text], COL_BAD)

func _on_event(text: String) -> void:
	if text.begins_with("[-"):
		return
	_push_message(text, COL_ACCENT)

func _push_message(text: String, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _msg_style)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)
	messages.add_child(panel)
	while messages.get_child_count() > 6:
		var old := messages.get_child(0)
		messages.remove_child(old)
		old.queue_free()
	var tw := panel.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(panel, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
	)
