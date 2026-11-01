class_name AmbienceManager
extends Node
## AmbienceManager — mekâna göre değişen 3B ortam sesleri (v0.4.1):
##   • İstasyon peronu: kalabalık uğultusu + ayak sesleri (AudioStreamPlayer3D, peron ortası; ses
##     seviyesi bekleyen yolcu sayısına bağlı) + hol tonu (uzak, düşük)
##   • Vagon içi: konuşma uğultusu (doluluğa göre, her vagonda bir kaynak) + havalandırma uğultusu
##   • Dinleyici bölgesi: kabin / vagon (yürüme) → sürüş seslerinin (motor, ray, fren) karışımı
##     ve alçak geçiren filtre değişir; anonslar vagonda daha yakın/yüksek duyulur.
## Sesler tools/make_ambience.py ile prosedürel üretilmiştir (dış kaynak yok).
## Performans: yalnızca kameraya 120 m içindeki istasyon kaynakları çalar; her 0,5 sn güncellenir.

const DIR := "res://assets/audio/ambience/"

var train: TrainController
var route: RouteData
var world: TrackBuilder
var passengers: PassengerManager
var walker: PlayerWalker
var _station_players: Dictionary = {}     # sid -> {crowd, tone}
var _car_players: Array = []              # [{murmur, hvac}]
var _timer := 0.0
var _zone := "cab"
var _lowpass: AudioEffectLowPassFilter
var _streams: Dictionary = {}

func setup(p_train: TrainController, p_route: RouteData, p_world: TrackBuilder, p_passengers: PassengerManager, p_walker: PlayerWalker) -> void:
	train = p_train
	route = p_route
	world = p_world
	passengers = p_passengers
	walker = p_walker
	for n in ["crowd_platform", "saloon_murmur", "hvac", "footsteps", "station_tone"]:
		var path: String = DIR + n + ".wav"
		if ResourceLoader.exists(path):
			var st: AudioStream = load(path)
			if st is AudioStreamWAV:
				(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
				(st as AudioStreamWAV).loop_end = (st as AudioStreamWAV).data.size() / 2
			_streams[n] = st
	# İstasyon kaynakları
	for st in route.stations:
		var node := world.get_station_node(str(st["id"]))
		if node == null:
			continue
		var center := Vector3(node._sx(StationBuilder.PLATFORM_EDGE_X + node.platform_w * 0.5), StationBuilder.PLATFORM_Y + 1.6, -node.length * 0.5)
		var crowd := _p3d("crowd_platform", center, 45.0, 2.0, -10.0)
		node.add_child(crowd)
		var tone := _p3d("station_tone", center + Vector3(0, 3.0, 0), 80.0, 6.0, -18.0)
		node.add_child(tone)
		var steps := _p3d("footsteps", center + Vector3(0, -1.0, 8.0), 30.0, 1.5, -12.0)
		node.add_child(steps)
		_station_players[str(st["id"])] = {"crowd": crowd, "tone": tone, "steps": steps}
	# Vagon kaynakları
	for car in train.cars:
		var murmur := _p3d("saloon_murmur", Vector3(0, TrainVisual.FLOOR_Y + 1.5, 0), 14.0, 2.5, -14.0)
		car.add_child(murmur)
		var hvac := _p3d("hvac", Vector3(0, TrainVisual.ROOF_Y - 0.5, 0), 16.0, 3.0, -20.0)
		car.add_child(hvac)
		_car_players.append({"murmur": murmur, "hvac": hvac})
	# Dinleyici bölgesi filtresi (SFX busu)
	var bus := AudioServer.get_bus_index("SFX")
	if bus >= 0:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus, _lowpass)
	if walker:
		walker.mode_changed.connect(func(w: bool) -> void: set_zone("saloon" if w else "cab"))
	_update(true)

func _p3d(stream: String, pos: Vector3, max_dist: float, unit: float, vol_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams.get(stream)
	p.position = pos
	p.max_distance = max_dist
	p.unit_size = unit
	p.volume_db = vol_db
	p.bus = "SFX"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_db = 0.0
	p.autoplay = false
	return p

## Dinleyici bölgesi: "cab" (kabin) / "saloon" (vagon içinde yürüme)
func set_zone(z: String) -> void:
	if _zone == z:
		return
	_zone = z
	if _lowpass:
		_lowpass.cutoff_hz = 20000.0 if z == "cab" else 6500.0
	# Sürüş sesleri vagonda daha boğuk ve uzak; anons vagonda daha yüksek
	var k := 1.0 if z == "cab" else 0.55
	AudioManager.zone_gain = k
	AudioManager.p_announce.volume_db = -4.0 if z == "cab" else 0.0
	Scoring.log_event("Ses bölgesi: %s" % ("kabin" if z == "cab" else "vagon"))

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	_update(false)

func _update(force: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var dens := GameState.current_density()
	for sid in _station_players:
		var d: Dictionary = _station_players[sid]
		var crowd: AudioStreamPlayer3D = d["crowd"]
		var near := crowd.global_position.distance_to(cam_pos) < 160.0
		if near:
			var waiting := passengers.waiting_count(sid) if passengers else 0
			var amp := clampf(0.15 + waiting / 30.0, 0.15, 1.0) * clampf(dens, 0.3, 1.4)
			crowd.volume_db = linear_to_db(amp) - 8.0
			for key in ["crowd", "tone", "steps"]:
				var p: AudioStreamPlayer3D = d[key]
				if not p.playing and p.stream:
					p.play(randf() * 5.0)
			(d["steps"] as AudioStreamPlayer3D).volume_db = linear_to_db(clampf(waiting / 20.0, 0.1, 1.0)) - 12.0
		else:
			for key in ["crowd", "tone", "steps"]:
				if (d[key] as AudioStreamPlayer3D).playing:
					(d[key] as AudioStreamPlayer3D).stop()
	# Vagon uğultusu doluluğa göre; kabin dışındayken belirgin
	var load := passengers.load_factor() if passengers else 0.2
	for i in _car_players.size():
		var cp: Dictionary = _car_players[i]
		var m: AudioStreamPlayer3D = cp["murmur"]
		var h: AudioStreamPlayer3D = cp["hvac"]
		if not m.playing and m.stream:
			m.play(randf() * 6.0)
		if not h.playing and h.stream:
			h.play(randf() * 3.0)
		m.volume_db = linear_to_db(clampf(0.1 + load * 1.4, 0.1, 1.0)) - 12.0
		h.volume_db = -20.0 + (4.0 if _zone == "saloon" else 0.0)
