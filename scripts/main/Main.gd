extends Node3D
## Main — dünya, tren, görev/trafik/arıza/yolcu yöneticileri ve arayüzü birleştirir.

@onready var world: TrackBuilder = $World
@onready var train: TrainController = $Train
@onready var hud = $HUD
@onready var brief = $MissionBrief
@onready var score_screen = $ScoreScreen
@onready var pause_menu = $PauseMenu
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var route: RouteData
var mission: MissionManager
var traffic: TrafficManager
var faults: FaultManager
var passengers: PassengerManager
var cabin: CabinInteraction
var mmi: MMIScreen
var cctv: CCTVSystem
var walker: PlayerWalker
var pis: PISSystem
var ambience: AmbienceManager
var _finished := false

func _ready() -> void:
	route = GameState.route
	GameState.reset_mission()
	GameState.paused = false
	var m := GameState.mission
	var seed: int = int(m.get("seed", 0))
	if seed == 0:
		seed = int(Time.get_unix_time_from_system()) % 1000000
		m["seed"] = seed

	world.build(route)
	train.setup(world, route, float(route.get_start_station()["stop_pos"]))
	train.controls_enabled = false

	mission = MissionManager.new()
	mission.name = "Mission"
	add_child(mission)
	mission.setup(train, route, world)

	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	traffic.enabled = bool(m.get("traffic_enabled", true))
	add_child(traffic)
	traffic.setup(train, route, world, mission, seed + 1)

	faults = FaultManager.new()
	faults.name = "Faults"
	faults.enabled = bool(m.get("faults_enabled", true))
	add_child(faults)
	faults.setup(train, route, mission, seed + 2)

	passengers = PassengerManager.new()
	passengers.name = "Passengers"
	passengers.enabled = bool(m.get("passengers_enabled", true))
	add_child(passengers)
	passengers.setup(train, route, world, mission, seed + 3)

	mmi = MMIScreen.new()
	mmi.name = "MMI"
	add_child(mmi)
	mmi.setup(train, route, mission, traffic, faults, passengers)
	train.visual.attach_mmi(mmi)
	faults.set_mmi(mmi)
	faults.fault_message.connect(func(t: String) -> void: hud.push_center_message(t, false))

	cabin = CabinInteraction.new()
	cabin.name = "CabinInteraction"
	add_child(cabin)
	cabin.setup(train, hud)

	cctv = CCTVSystem.new()
	cctv.name = "CCTV"
	add_child(cctv)
	cctv.setup(train)

	walker = PlayerWalker.new()
	walker.name = "Walker"
	train.cars[0].add_child(walker)
	walker.setup(train, hud)
	walker.mode_changed.connect(func(w: bool) -> void: cabin.enabled = not w)

	ambience = AmbienceManager.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(train, route, world, passengers, walker)

	AudioManager.attach(train, mission, route, faults)

	pis = PISSystem.new()
	pis.name = "PIS"
	add_child(pis)
	pis.setup(train, route, mission, traffic, world)

	hud.bind(train, route, mission, traffic, faults, passengers)
	mission.hint_changed.connect(func(t: String) -> void: hud.set_hint(t))
	mission.mission_finished.connect(_on_mission_finished)
	traffic.message.connect(_on_center_message)
	brief.accepted.connect(_on_brief_accepted)
	pause_menu.resumed.connect(_on_resumed)

	_setup_environment()
	Settings.settings_applied.connect(_on_settings_applied)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not SaveGame.resume_data.is_empty():
		# Kayıttan devam: brifing atlanır, durum geri yüklenir
		var d: Dictionary = SaveGame.resume_data
		SaveGame.resume_data = {}
		brief.visible = false
		SaveGame.apply_to_main(self, d)
		hud.push_center_message("Kaldığınız yerden devam ediyorsunuz", false)
		if not GameState.auto_test_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		brief.show_brief(route, traffic)
		Scoring.log_event("Vardiya başladı — %s (%s)" % [str(route.get_start_station()["name"]), GameState.clock_text()])
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _finished and GameState.phase != GameState.Phase.BRIEFING:
			SaveGame.save_from_main(self)
		get_tree().quit()

func _setup_environment() -> void:
	var e := env.environment
	var night := GameState.is_night()
	# Güneş (açık kesimler)
	sun.shadow_enabled = Settings.sun_shadows()
	sun.directional_shadow_max_distance = Settings.shadow_distance()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if Settings.shadow_quality >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	var has_open := false
	for seg in route.segments:
		if str(seg.get("type", "tunnel")) == "open":
			has_open = true
	sun.visible = has_open
	sun.light_energy = 0.12 if night else 1.5
	sun.light_color = Color(0.6, 0.65, 0.9) if night else Color(1.0, 0.95, 0.86)
	sun.light_volumetric_fog_energy = 0.3
	var sky_mat: ProceduralSkyMaterial = e.sky.sky_material
	e.background_mode = Environment.BG_SKY if has_open else Environment.BG_COLOR
	e.background_color = Color(0.004, 0.005, 0.007)
	if night:
		sky_mat.sky_top_color = Color(0.02, 0.03, 0.08)
		sky_mat.sky_horizon_color = Color(0.1, 0.1, 0.16)
		sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
		sky_mat.ground_horizon_color = Color(0.08, 0.08, 0.1)
	# Ortam ışığı: tünel loş, gökyüzü katkısı düşük
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.22 if night else 0.3
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED   # yansımalar: istasyon probları + SSR
	# Tonemap ve renk
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.tonemap_white = 1.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.04
	# SSAO / SSIL / SSR
	e.ssao_enabled = Settings.ssao_enabled
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.0
	e.ssao_power = 1.5
	e.ssao_detail = 0.5
	e.ssil_enabled = Settings.quality >= 3
	e.ssr_enabled = Settings.reflection_quality > 0
	e.ssr_max_steps = 48 if Settings.reflection_quality >= 2 else 24
	e.ssr_fade_in = 0.15
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.3
	# Parlama
	e.glow_enabled = Settings.glow_enabled
	e.glow_intensity = 0.3
	e.glow_strength = 0.9
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.6
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Sis
	e.fog_enabled = Settings.fog_enabled
	e.fog_light_color = Color(0.05, 0.055, 0.065)
	e.fog_light_energy = 0.5
	e.fog_density = 0.0035
	e.fog_aerial_perspective = 0.3
	e.volumetric_fog_enabled = Settings.volumetric_fog
	e.volumetric_fog_density = 0.0022
	e.volumetric_fog_albedo = Color(0.55, 0.57, 0.6)
	e.volumetric_fog_emission_energy = 0.0
	e.volumetric_fog_length = 80.0
	e.volumetric_fog_detail_spread = 2.0
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_gi_inject = 0.0
	# SDFGI (Ultra)
	e.sdfgi_enabled = Settings.sdfgi_enabled
	e.sdfgi_cascades = 4
	e.sdfgi_min_cell_size = 0.25
	e.sdfgi_bounce_feedback = 0.5
	e.sdfgi_energy = 1.0
	if train and train.visual:
		train.visual.apply_quality()

func _on_settings_applied() -> void:
	_setup_environment()

func _on_brief_accepted() -> void:
	mission.begin()
	if not GameState.auto_test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	traffic.announce_tsr()

func _process(delta: float) -> void:
	world.update_visibility(train.offset, delta)
	# İstasyon saatleri
	if Engine.get_process_frames() % 60 == 0:
		var t := GameState.clock_text()
		for s in route.stations:
			var node := world.get_station_node(str(s["id"]))
			if node:
				node.set_clock(t)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameState.phase == GameState.Phase.BRIEFING or _finished:
			return
		if GameState.paused:
			pause_menu.resume()
		else:
			pause_menu.open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif GameState.phase != GameState.Phase.BRIEFING and not _finished and not GameState.paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("restart"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		GameState.paused = false
		get_tree().paused = false
		get_tree().reload_current_scene()
	if event.is_action_pressed("acknowledge") and GameState.phase != GameState.Phase.BRIEFING:
		traffic.acknowledge()
		faults.acknowledge()

func _on_resumed() -> void:
	if not _finished and GameState.phase != GameState.Phase.BRIEFING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_center_message(text: String, requires_ack: bool) -> void:
	hud.push_center_message(text, requires_ack)
	AudioManager.play_message_tone()

func _on_mission_finished(reason: String) -> void:
	_finished = true
	SaveGame.clear()
	var result := Career.complete_mission(route, reason)
	score_screen.show_results(route, reason, result)
	if not GameState.auto_test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
