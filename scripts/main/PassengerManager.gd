class_name PassengerManager
extends Node
## PassengerManager — yapay zekâ yolcular:
##   • Peronda bekleyen yolcular (saat/istasyon popülerliğine göre sayı)
##   • Tren gelince kapılara yönelme, kapılar açılınca iniş/biniş kuyruğu
##   • İnen yolcular çıkışa (yürüyen merdiven/asansör) yürür ve kaybolur
##   • Kapı kapanırken kapı eşiğindeki yolcu → sıkışma, kapı yeniden açılır
##   • Doluluk → trenin yük faktörü (hızlanmayı etkiler) ve duraklama süresi
##   • Performans: yalnızca trene 700 m'den yakın istasyonlarda yolcu üretilir;
##     uzaktakiler düşük frekansta güncellenir. Trene binenler sayısal olarak taşınır.

const CAPACITY := 920          # 4 araç × 230 (ezik doluluk)
const SPAWN_RANGE := 700.0
const DESPAWN_RANGE := 500.0
const WALK_SPEED := 1.35

enum PState { WAITING, TO_DOOR, BOARDING, ALIGHTING, LEAVING, SEATED }

var train: TrainController
var route: RouteData
var world: TrackBuilder
var mission: MissionManager
var rng := RandomNumberGenerator.new()
var enabled: bool = true
var onboard: int = 0
var passengers: Array = []           # her biri Dictionary {node, state, target, speed, station, phase, door}
var _spawned_stations: Dictionary = {}   # station id -> true
var _boarding_station: Dictionary = {}
var _frame := 29
var _door_positions: Array[Vector3] = []
var _door_side: String = "right"
var _alight_timer := 0.0
var _alight_queue: int = 0

func setup(p_train: TrainController, p_route: RouteData, p_world: TrackBuilder, p_mission: MissionManager, seed: int) -> void:
	train = p_train
	route = p_route
	world = p_world
	mission = p_mission
	rng.seed = seed
	_make_assets()
	mission.arrived_at_station.connect(_on_arrived)
	mission.doors_opened_at_station.connect(_on_doors_opened)
	mission.departed_station.connect(_on_departed)
	train.doors.obstruction_check = Callable(self, "door_obstruction")
	# Başlangıç doluluğu
	var dens := GameState.current_density()
	onboard = int(clamp(rng.randf_range(60, 160) * dens, 0, CAPACITY)) if enabled else 0
	_update_load()
	if enabled:
		_spawn_station(route.get_start_station())
		# Tren içi görünür yolcular (başlangıç doluluğu)
		for i in _target_visible_onboard():
			_add_onboard_passenger()

const PASSENGER_GLB := "res://assets/models/passenger.glb"
## v0.4.1: MakeHuman (CC0) tabanlı gerçekçi karakter varyantları; yoksa eski prosedürel modele düşer
const MH_VARIANTS := ["m_young", "m_old", "m_heavy", "f_young", "f_old", "f_slim"]
var _pscene: PackedScene
var _mh_scenes: Array = []
var skin_colors := [Color(0.87, 0.68, 0.56), Color(0.76, 0.58, 0.45), Color(0.95, 0.82, 0.72), Color(0.55, 0.4, 0.3), Color(0.68, 0.5, 0.38)]
var hair_colors := [Color(0.08, 0.06, 0.05), Color(0.25, 0.15, 0.08), Color(0.5, 0.35, 0.2), Color(0.7, 0.6, 0.45), Color(0.35, 0.35, 0.37), Color(0.12, 0.08, 0.07)]
var shirt_colors := [Color(0.2, 0.25, 0.4), Color(0.1, 0.1, 0.12), Color(0.55, 0.15, 0.2), Color(0.3, 0.45, 0.3), Color(0.85, 0.85, 0.87),
	Color(0.5, 0.35, 0.2), Color(0.15, 0.4, 0.6), Color(0.65, 0.6, 0.5), Color(0.75, 0.3, 0.1), Color(0.3, 0.3, 0.32), Color(0.9, 0.75, 0.3)]
var pants_colors := [Color(0.12, 0.14, 0.22), Color(0.1, 0.1, 0.11), Color(0.35, 0.33, 0.3), Color(0.2, 0.2, 0.25), Color(0.45, 0.42, 0.38)]
var jacket_colors := [Color(0.12, 0.12, 0.14), Color(0.25, 0.2, 0.15), Color(0.1, 0.15, 0.25), Color(0.4, 0.4, 0.42), Color(0.3, 0.1, 0.1), Color(0.5, 0.45, 0.35)]
var bag_colors := [Color(0.1, 0.1, 0.11), Color(0.2, 0.25, 0.35), Color(0.35, 0.2, 0.12), Color(0.15, 0.3, 0.2)]
var _mat_cache: Dictionary = {}

func _make_assets() -> void:
	_pscene = load(PASSENGER_GLB) if ResourceLoader.exists(PASSENGER_GLB) else null
	for v in MH_VARIANTS:
		var path := "res://assets/models/passenger_%s.glb" % v
		if ResourceLoader.exists(path):
			_mh_scenes.append(load(path))

func load_factor() -> float:
	return clampf(float(onboard) / CAPACITY, 0.0, 1.0)

func _update_load() -> void:
	train.load_factor = load_factor()

func _colored(base_name: String, color: Color) -> StandardMaterial3D:
	var key := base_name + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9 if base_name != "Skin" else 0.6
	if base_name == "Shirt" or base_name == "Pants" or base_name == "Jacket":
		var tex := MaterialLib.texture("seat_fabric_normal")
		if tex:
			m.normal_enabled = true
			m.normal_texture = tex
			m.normal_scale = 0.4
			m.uv1_scale = Vector3(3, 3, 3)
	_mat_cache[key] = m
	return m

## Animasyonlu, rastgele görünümlü yolcu (vücut tipi ölçekle, kıyafet renkleri malzemeyle)
func _make_passenger(world_pos: Vector3, station_id: String) -> Dictionary:
	var n: Node3D
	var ap: AnimationPlayer = null
	var has_phone := false
	var scene: PackedScene = _pscene
	var mh := false
	if not _mh_scenes.is_empty():
		scene = _mh_scenes[rng.randi_range(0, _mh_scenes.size() - 1)]
		mh = true
	if scene:
		n = scene.instantiate()
		ap = n.find_child("AnimationPlayer", true, false)
		# Kişiye özel renkler (tüm parçalarda tutarlı)
		var cols := {
			"Skin": skin_colors[rng.randi_range(0, skin_colors.size() - 1)],
			"Hair": hair_colors[rng.randi_range(0, hair_colors.size() - 1)],
			"Shirt": shirt_colors[rng.randi_range(0, shirt_colors.size() - 1)],
			"Pants": pants_colors[rng.randi_range(0, pants_colors.size() - 1)],
			"Shoes": Color(0.08, 0.08, 0.09) if rng.randf() < 0.7 else Color(0.5, 0.35, 0.25),
			"Jacket": jacket_colors[rng.randi_range(0, jacket_colors.size() - 1)],
			"Bag": bag_colors[rng.randi_range(0, bag_colors.size() - 1)],
		}
		# Varyantlar: uzun saç %35, ceket %45, sırt çantası %22, el çantası %18, telefon (animasyona bağlı)
		var long_hair := rng.randf() < 0.35
		var jacket := rng.randf() < 0.45
		var backpack := rng.randf() < 0.22
		var handbag := (not backpack) and rng.randf() < 0.18
		has_phone = rng.randf() < 0.4
		if mh:
			cols["Skin"] = skin_colors[rng.randi_range(0, skin_colors.size() - 1)].lerp(Color(1, 0.9, 0.85), rng.randf_range(0.0, 0.25))
			long_hair = long_hair and str(n.scene_file_path).contains("_f_") or (rng.randf() < 0.1)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var nm := str(mi.name)
			if nm.begins_with("HairLong"):
				mi.visible = long_hair
			elif nm.begins_with("HairCap"):
				mi.visible = true if mh else not long_hair
				# Bazı erkeklerde kısa saç yok (kel) — %12
				if mh and not long_hair and rng.randf() < 0.12 and str(n.scene_file_path).contains("_m_"):
					mi.visible = false
			elif nm.begins_with("Backpack"):
				mi.visible = backpack
			elif nm.begins_with("Handbag"):
				mi.visible = handbag
			elif nm.begins_with("Phone"):
				mi.visible = false
			elif nm.begins_with("Jacket"):
				mi.visible = jacket
			if mi.mesh:
				for si in mi.mesh.get_surface_count():
					var base: Material = mi.mesh.surface_get_material(si)
					var rn: String = base.resource_name if base else ""
					if rn == "Phone" or rn == "Eyes" or rn == "Iris" or rn == "Lips":
						continue
					if cols.has(rn):
						mi.set_surface_override_material(si, _colored(rn, cols[rn]))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (nm == "PassengerBody" or nm == "Shirt" or nm == "Pants") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		n = Node3D.new()
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.19
		cm.height = 1.6
		body.mesh = cm
		body.position = Vector3(0, 0.85, 0)
		n.add_child(body)
	var h := rng.randf_range(0.94, 1.06) if mh else rng.randf_range(0.9, 1.08)
	var w := rng.randf_range(0.96, 1.06) if mh else rng.randf_range(0.9, 1.18)
	n.scale = Vector3(w, h, w)
	n.position = world_pos
	n.rotation.y = rng.randf_range(0, TAU)
	world.add_child(n)
	if ap:
		for an in ["idle", "walk", "sit", "sit_phone", "stand_phone", "stand_hold"]:
			if ap.has_animation(an):
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
		ap.seek(rng.randf_range(0.0, 2.5), true)
		ap.speed_scale = rng.randf_range(0.9, 1.1)
	var p := {"node": n, "ap": ap, "anim": "idle", "state": PState.WAITING, "target": world_pos, "speed": WALK_SPEED * rng.randf_range(0.85, 1.2),
		"station": station_id, "phase": rng.randf_range(0, TAU), "door": -1, "idle_t": rng.randf_range(2.0, 8.0), "height": h, "phone": has_phone}
	# Peronda bekleyenlerin bir kısmı telefona bakar
	if has_phone and rng.randf() < 0.7:
		_set_anim(p, "stand_phone")
	return p

func _set_anim(p: Dictionary, anim: String) -> void:
	if p["anim"] == anim:
		return
	p["anim"] = anim
	var ap: AnimationPlayer = p["ap"]
	if ap:
		if not ap.has_animation(anim):
			anim = "idle"
		ap.play(anim, 0.2)
		ap.speed_scale = (float(p["speed"]) / WALK_SPEED) if anim == "walk" else rng.randf_range(0.9, 1.1)
	var n: Node3D = p["node"]
	var ph := n.find_child("Phone", true, false)
	if ph:
		ph.visible = anim.ends_with("_phone")

func _spawn_station(st: Dictionary) -> void:
	var sid := str(st["id"])
	if _spawned_stations.has(sid):
		return
	_spawned_stations[sid] = true
	var node := world.get_station_node(sid)
	if node == null:
		return
	# Son istasyonda bekleyen olmaz (tren boşalır), başlangıçta az olur (çoğu bindi)
	var dens := GameState.current_density()
	var base := 24.0 * float(st.get("popularity", 1.0)) * dens
	var count := int(rng.randf_range(base * 0.7, base * 1.4))
	if st.get("is_end", false):
		count = int(count * 0.3)
	if st.get("is_start", false):
		count = int(count * 0.6)
	count = clampi(count, 4, 64)
	var free_benches: Array = node.bench_seats.duplicate()
	free_benches.shuffle()
	for i in count:
		var local := node.random_platform_point(rng)
		# %30'u bankta oturur (boş yer varsa)
		if free_benches.size() > 0 and rng.randf() < 0.3:
			var b: Dictionary = free_benches.pop_back()
			var p := _make_passenger(node.global_transform * b["pos"], sid)
			var n: Node3D = p["node"]
			n.rotation.y = node.rotation.y + float(b["yaw"])
			n.position.y = (node.global_transform * b["pos"]).y - (0.93 if str(n.scene_file_path).contains("passenger_") else 0.86)
			p["state"] = PState.SEATED
			p["target"] = n.global_position
			_set_anim(p, "sit_phone" if bool(p["phone"]) and rng.randf() < 0.6 else "sit")
			passengers.append(p)
			continue
		var p := _make_passenger(node.global_transform * local, sid)
		# %35'i peronda dolaşır (sık hedef değiştirir), kalanı bekler
		p["pacer"] = rng.randf() < 0.35
		passengers.append(p)

func _despawn_station(sid: String) -> void:
	for p in passengers.duplicate():
		if p["station"] == sid:
			p["node"].queue_free()
			passengers.erase(p)
	_spawned_stations.erase(sid)

# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not enabled or GameState.paused:
		return
	_frame += 1
	# Yakın istasyonlarda yolcu üret / uzaktakileri kaldır
	if _frame % 30 == 0:
		for st in route.stations:
			var d := absf(float(st["stop_pos"]) - train.offset)
			var sid := str(st["id"])
			if d < SPAWN_RANGE and not _spawned_stations.has(sid):
				_spawn_station(st)
			elif d > SPAWN_RANGE + DESPAWN_RANGE and _spawned_stations.has(sid) and (_boarding_station.is_empty() or str(_boarding_station["id"]) != sid):
				_despawn_station(sid)
	# İnen yolcu üretimi (kapılardan sırayla)
	if _alight_queue > 0 and not _door_positions.is_empty():
		_alight_timer -= delta
		if _alight_timer <= 0.0:
			_alight_timer = 0.35
			_alight_queue -= 1
			_spawn_alighting()
	_sync_onboard(delta)
	# Yolcu güncelleme (uzaktakiler seyrek)
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else (train.camera.global_position if train.camera else Vector3.ZERO)
	for p in passengers.duplicate():
		var n: Node3D = p["node"]
		var dist := n.global_position.distance_to(cam_pos)
		if dist > 120.0 and _frame % 4 != 0:
			continue
		var dt := delta * (4.0 if dist > 120.0 else 1.0)
		_update_passenger(p, dt)
		# Animasyon LOD: 45 m'den uzakta iskelet güncellemesi durur
		var ap: AnimationPlayer = p["ap"]
		if ap and _frame % 15 == 0:
			ap.active = dist < 45.0
	if _frame % 30 == 0:
		for d in onboard_nodes:
			var ap2: AnimationPlayer = d["ap"]
			var n2: Node3D = d["node"]
			if ap2:
				ap2.active = n2.global_position.distance_to(cam_pos) < 40.0

func _update_passenger(p: Dictionary, dt: float) -> void:
	var n: Node3D = p["node"]
	match p["state"]:
		PState.SEATED:
			pass   # bankta oturur; kapılar açılınca TO_DOOR'a geçer
		PState.WAITING:
			p["idle_t"] = float(p["idle_t"]) - dt
			if float(p["idle_t"]) <= 0.0:
				# Yer değiştirme: dolaşanlar sık ve uzağa, bekleyenler seyrek ve yakına
				var pacer: bool = bool(p.get("pacer", false))
				p["idle_t"] = rng.randf_range(3.0, 7.0) if pacer else rng.randf_range(6.0, 16.0)
				var node := world.get_station_node(p["station"])
				if node:
					if pacer:
						p["target"] = node.global_transform * node.random_platform_point(rng)
					else:
						var cur := node.to_local(n.global_position)
						var np := node.random_platform_point(rng)
						np = Vector3(np.x, np.y, clampf(cur.z + rng.randf_range(-3.0, 3.0), float(node.platform_area["z_min"]), float(node.platform_area["z_max"])))
						p["target"] = node.global_transform * np
			_walk_towards(p, dt, 0.6 if not bool(p.get("pacer", false)) else 0.85)
		PState.TO_DOOR, PState.BOARDING:
			# Kapıya yönelme gecikmesi (herkes aynı anda fırlamaz)
			if float(p.get("wait", 0.0)) > 0.0:
				p["wait"] = float(p["wait"]) - dt
				return
			var arrived := _walk_towards(p, dt, 1.0)
			if arrived:
				if p["state"] == PState.TO_DOOR:
					p["state"] = PState.BOARDING
					# Kapıdan içeri: hedef kapının 1.2 m içi
					var door_pos: Vector3 = p["target"]
					var inward := _inward_dir()
					p["target"] = door_pos + inward * 1.3
					p["target"].y = n.global_position.y
				else:
					# Bindi
					onboard = mini(onboard + 1, CAPACITY)
					Scoring.stats["passengers_boarded"] = int(Scoring.stats["passengers_boarded"]) + 1
					_update_load()
					passengers.erase(p)
					n.queue_free()
		PState.ALIGHTING:
			var arrived := _walk_towards(p, dt, 1.0)
			if arrived:
				p["state"] = PState.LEAVING
				var node := world.get_station_node(p["station"])
				if node and node.exit_positions.size() > 0:
					var ex: Vector3 = node.exit_positions[rng.randi_range(0, node.exit_positions.size() - 1)]
					p["target"] = node.global_transform * ex
				else:
					p["target"] = n.global_position
		PState.LEAVING:
			var arrived := _walk_towards(p, dt, 1.0)
			if arrived:
				passengers.erase(p)
				n.queue_free()

func _inward_dir() -> Vector3:
	# Kapıdan trenin içine doğru yön (peron tarafının tersi), trenin yerel X ekseni
	var xf := world.get_track_transform(train.offset - 10.0)
	var right := xf.basis.x
	return -right if _door_side == "right" else right

## Hedefe yürür; vardıysa true. Yürüme/bekleme animasyonu AnimationPlayer ile; kayma yok
## (hız animasyon hızıyla eşlenir), yumuşak dönüş.
func _walk_towards(p: Dictionary, dt: float, speed_mul: float) -> bool:
	var n: Node3D = p["node"]
	var target: Vector3 = p["target"]
	var to := target - n.global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.08:
		_set_anim(p, "stand_phone" if (bool(p.get("phone", false)) and p["state"] == PState.WAITING) else "idle")
		return true
	var step := float(p["speed"]) * speed_mul * dt
	var dir := to / d
	n.global_position += dir * minf(step, d)
	var yaw := atan2(dir.x, dir.z)
	n.rotation.y = lerp_angle(n.rotation.y, yaw, minf(1.0, dt * 8.0))
	_set_anim(p, "walk")
	var ap: AnimationPlayer = p["ap"]
	if ap:
		# Adım uzunluğu ~0.75 m/döngü: kaymayı önlemek için animasyon hızı = hız / 1.35
		ap.speed_scale = (float(p["speed"]) * speed_mul) / (WALK_SPEED * float(p["height"]))
	n.position.y = target.y
	return false

# ---------------------------------------------------------------------------
# Görev olayları

func _on_arrived(st: Dictionary, _err: float) -> void:
	_boarding_station = st
	_spawn_station(st)
	_door_side = str(st.get("door_side", "right"))

func _on_doors_opened(st: Dictionary, side: String, correct: bool) -> void:
	if not correct or str(st["id"]) != str(_boarding_station.get("id", "")):
		return
	_door_positions = train.door_world_positions(side)
	_door_side = side
	# İnecekler
	var frac := rng.randf_range(0.18, 0.45) * float(st.get("popularity", 1.0))
	if st.get("is_end", false):
		frac = 1.0
	var alight := int(onboard * clampf(frac, 0.0, 1.0))
	alight = mini(alight, 40)   # görsel sınır; kalanı sayısal
	var numeric_alight := int(onboard * clampf(frac, 0.0, 1.0)) - alight
	onboard -= numeric_alight
	Scoring.stats["passengers_alighted"] = int(Scoring.stats["passengers_alighted"]) + numeric_alight
	_alight_queue = alight
	_alight_timer = 0.5
	# Bekleyenler kapılara yönelir (en yakın kapı, hafif gecikmeyle)
	var sid := str(st["id"])
	var boarding := 0
	for p in passengers:
		if p["station"] == sid and (p["state"] == PState.WAITING or p["state"] == PState.SEATED):
			var n: Node3D = p["node"]
			if p["state"] == PState.SEATED:
				n.position.y = StationBuilder.PLATFORM_Y
				var st_node := world.get_station_node(sid)
				if st_node:
					n.global_position.y = (st_node.global_transform * Vector3(0, StationBuilder.PLATFORM_Y, 0)).y
			var best := -1
			var best_d := INF
			for i in _door_positions.size():
				var dd := n.global_position.distance_to(_door_positions[i])
				if dd < best_d:
					best_d = dd
					best = i
			if best >= 0:
				p["state"] = PState.TO_DOOR
				p["door"] = best
				p["wait"] = rng.randf_range(0.0, 7.0)
				# Kapı önünde kuyruk noktası (perona doğru 0.9 m)
				var out := -_inward_dir()
				p["target"] = _door_positions[best] + out * 0.9
				p["target"].y = n.global_position.y
				boarding += 1
	mission.extra_dwell_from_passengers = clampf(boarding * 0.6 + alight * 0.35, 0.0, 30.0)
	mission.dwell_timer = route.dwell_seconds + mission.extra_dwell_from_passengers
	if st.get("is_end", false):
		Scoring.log_event("Son istasyon: tüm yolcular iniyor")

func _spawn_alighting() -> void:
	var i := rng.randi_range(0, _door_positions.size() - 1)
	var door := _door_positions[i]
	var out := -_inward_dir()
	var sid := str(_boarding_station.get("id", ""))
	var feet_y := door.y - TrainVisual.DOOR_H * 0.5
	var spawn := door + _inward_dir() * 0.8
	spawn.y = feet_y
	var p := _make_passenger(spawn, sid)
	p["state"] = PState.ALIGHTING
	p["target"] = door + out * rng.randf_range(1.5, 3.0) + world.get_track_transform(train.offset - 10.0).basis.z * rng.randf_range(-1.5, 1.5)
	p["target"].y = feet_y
	onboard = maxi(onboard - 1, 0)
	Scoring.stats["passengers_alighted"] = int(Scoring.stats["passengers_alighted"]) + 1
	_update_load()
	passengers.append(p)

## Kapı eşiğinde yolcu var mı? (TrainDoors.request_close çağırır) → kapı indeksi ya da -1
func door_obstruction(side: String) -> int:
	if _door_positions.is_empty() or side != _door_side:
		return -1
	for p in passengers:
		if p["state"] == PState.BOARDING or p["state"] == PState.ALIGHTING:
			var n: Node3D = p["node"]
			for i in _door_positions.size():
				var dp := _door_positions[i]
				var dd := Vector2(n.global_position.x - dp.x, n.global_position.z - dp.z).length()
				if dd < 0.55:
					return i
	return -1

func _on_departed(st: Dictionary) -> void:
	# Kapıya yetişemeyenler beklemeye döner
	var sid := str(st["id"])
	for p in passengers:
		if p["station"] == sid and (p["state"] == PState.TO_DOOR or p["state"] == PState.BOARDING):
			p["state"] = PState.WAITING
			p["idle_t"] = 1.0
	_door_positions = []
	_boarding_station = {}

# ---------------------------------------------------------------------------
# Tren içi görünür yolcular (oturan / direğe tutunan / telefona bakan) — yürüme modu ve CCTV için

var onboard_nodes: Array = []      # [{node, ap, seat(Node3D) or null}]
var _onboard_timer := 0.0

func _target_visible_onboard() -> int:
	# Doluluğa göre görünür yolcu: koltuk sayısının %70'ine kadar + ayakta
	var seats: int = train.visual.seat_positions.size()
	return clampi(int(onboard * 0.5), 0, mini(seats + 20, 96))

func _sync_onboard(delta: float) -> void:
	_onboard_timer -= delta
	if _onboard_timer > 0.0:
		return
	_onboard_timer = 0.6
	var target := _target_visible_onboard()
	if onboard_nodes.size() < target:
		_add_onboard_passenger()
	elif onboard_nodes.size() > target:
		var d: Dictionary = onboard_nodes.pop_back()
		d["node"].queue_free()

func _add_onboard_passenger() -> void:
	var seats: Array = train.visual.seat_positions
	var used := {}
	for d in onboard_nodes:
		if d["seat"] != null:
			used[d["seat"]] = true
	var free: Array = []
	for s in seats:
		if not used.has(s["node"]):
			free.append(s)
	var p := _make_passenger(Vector3.ZERO, "")
	var n: Node3D = p["node"]
	world.remove_child(n)
	var ap: AnimationPlayer = p["ap"]
	if free.size() > 0 and rng.randf() < 0.85:
		var s: Dictionary = free[rng.randi_range(0, free.size() - 1)]
		var seat: Node3D = s["node"]
		seat.add_child(n)
		# SeatPos koltuk yüzeyindedir; model orijini ayak tabanı, kalça 0,92 m yukarıda → oturunca
		# kalça koltuk yüzeyine gelsin. Model yerel +Z'ye bakar; koridora dönmesi için 180°.
		n.rotation = Vector3(0, PI, 0)
		var mh_model := str(n.scene_file_path).contains("passenger_")
		n.position = Vector3(0.0, -0.93 if mh_model else -0.86, 0.14 if mh_model else 0.12)
		_set_anim(p, "sit_phone" if bool(p["phone"]) and rng.randf() < 0.6 else "sit")
		onboard_nodes.append({"node": n, "ap": ap, "seat": seat})
	else:
		# Ayakta: rastgele bir vagonun koridorunda, direğe tutunur
		var ci := rng.randi_range(0, train.cars.size() - 1)
		var car: Node3D = train.cars[ci]
		car.add_child(n)
		# Kabin bölgesine (ön araçta z<-7, arka araçta z>7) yolcu konmaz — makinist kabini kapalı alan
		var z0 := -8.5 if ci > 0 else -6.6
		var z1 := 8.5 if ci < train.cars.size() - 1 else 6.6
		n.position = Vector3(rng.randf_range(-0.55, 0.55), TrainVisual.FLOOR_Y + 0.03, rng.randf_range(z0, z1))
		n.rotation.y = rng.randf_range(0, TAU)
		_set_anim(p, "stand_phone" if bool(p["phone"]) else "stand_hold")
		onboard_nodes.append({"node": n, "ap": ap, "seat": null})
	if ap:
		ap.seek(rng.randf_range(0.0, 2.5), true)

func waiting_count(sid: String) -> int:
	var c := 0
	for p in passengers:
		if p["station"] == sid and p["state"] == PState.WAITING:
			c += 1
	return c
