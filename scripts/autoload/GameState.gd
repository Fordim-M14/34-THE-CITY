extends Node
## GameState — oyun fazı, aktif görev, rota verisi, oyun içi saat ve input tanımları (autoload).

signal phase_changed(phase: int)
signal clock_changed(seconds_of_day: float)

enum Phase { BRIEFING, PREPARING, DRIVING, ARRIVED, FINISHED }

const ROUTES_DIR := "res://data/routes/"
const DEFAULT_ROUTE := "hat4"

var phase: int = Phase.BRIEFING
var route: RouteData                     # aktif yön için rota
var route_forward: RouteData             # ham (ileri) rota
var mission: Dictionary = {}             # aktif görev tanımı
var mission_time: float = 0.0            # ilk kalkıştan itibaren geçen süre (s)
var clock_s: float = 8 * 3600.0          # günün saniyesi (oyun içi saat)
var departure_cleared: bool = false
var auto_test_mode: bool = false
var paused: bool = false
var walking: bool = false                # yürüme modu (PlayerWalker ayarlar)

func _ready() -> void:
	_setup_input_map()
	route_forward = RouteData.load_route(ROUTES_DIR + DEFAULT_ROUTE + ".json")
	if mission.is_empty():
		mission = default_mission()
	apply_mission(mission)

func available_routes() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ROUTES_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".json") and not f.begins_with("hat4_sgh"):
				out.append(f.trim_suffix(".json"))
	return out

func default_mission() -> Dictionary:
	return {
		"route_id": DEFAULT_ROUTE,
		"direction": "forward",
		"mode": "career",              # career | free
		"service_number": "4107",
		"start_time_s": 8 * 3600 + 12 * 60,
		"faults_enabled": true,
		"traffic_enabled": true,
		"passengers_enabled": true,
		"seed": 0,
	}

## Görevi uygular: rota yönü, saat, faz sıfırlama. Sahne değişimi çağıranın işi.
func apply_mission(m: Dictionary) -> void:
	mission = m
	var rid := str(m.get("route_id", DEFAULT_ROUTE))
	if route_forward == null or route_forward.route_id != rid:
		route_forward = RouteData.load_route(ROUTES_DIR + rid + ".json")
	if str(m.get("direction", "forward")) == "reverse":
		route = route_forward.reversed()
	else:
		route = route_forward
	clock_s = float(m.get("start_time_s", 8 * 3600))
	reset_mission()

func start_mission(m: Dictionary) -> void:
	apply_mission(m)
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func set_phase(p: int) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)

func reset_mission() -> void:
	mission_time = 0.0
	departure_cleared = false
	Scoring.reset()
	set_phase(Phase.BRIEFING)

func _process(delta: float) -> void:
	if paused:
		return
	if phase == Phase.DRIVING or phase == Phase.ARRIVED:
		mission_time += delta
	if phase != Phase.BRIEFING and phase != Phase.FINISHED:
		clock_s = fmod(clock_s + delta, 86400.0)

func clock_text() -> String:
	var h := int(clock_s / 3600.0) % 24
	var m := int(fmod(clock_s, 3600.0) / 60.0)
	return "%02d:%02d" % [h, m]

## Saate göre yolcu yoğunluğu çarpanı (0.25 gece … 1.4 zirve).
func density_for_hour(h: float) -> float:
	if h >= 7.0 and h < 9.5:
		return 1.4
	if h >= 16.5 and h < 19.5:
		return 1.3
	if h >= 9.5 and h < 16.5:
		return 0.75
	if h >= 19.5 and h < 22.5:
		return 0.55
	return 0.25

func current_density() -> float:
	return density_for_hour(clock_s / 3600.0)

func is_night() -> bool:
	var h := clock_s / 3600.0
	return h < 6.0 or h >= 19.5

func is_free_mode() -> bool:
	return str(mission.get("mode", "career")) == "free"

# --- Input -----------------------------------------------------------------

const DEFAULT_BINDINGS := {
	"throttle_up": [KEY_W, KEY_UP],
	"throttle_down": [KEY_S, KEY_DOWN],
	"lever_neutral": [KEY_N],
	"emergency_brake": [KEY_SPACE],
	"doors_left": [KEY_Q],
	"doors_right": [KEY_E],
	"reverser": [KEY_R],
	"acknowledge": [KEY_F],
	"headlights": [KEY_L],
	"cabin_light": [KEY_K],
	"horn": [KEY_H],
	"confirm": [KEY_ENTER, KEY_KP_ENTER],
	"restart": [KEY_F5],
	"pause": [KEY_ESCAPE],
	"mmi_next": [KEY_TAB],
	"zoom": [KEY_Z],
	"recenter_view": [KEY_C],
	"stand_up": [KEY_X],
}

const BINDING_LABELS := {
	"throttle_up": "Kol ileri (çekiş)", "throttle_down": "Kol geri (fren)", "lever_neutral": "Kol nötr",
	"emergency_brake": "Acil fren", "doors_left": "Sol kapılar", "doors_right": "Sağ kapılar",
	"reverser": "Yön kolu", "acknowledge": "Onay / Merkez", "headlights": "Farlar", "cabin_light": "Kabin ışığı",
	"horn": "Korna", "confirm": "Onayla", "restart": "Yeniden başlat", "pause": "Duraklat", "mmi_next": "MMI sayfa",
	"zoom": "Yakınlaştır (basılı)", "recenter_view": "Bakışı ortala", "stand_up": "Koltuktan kalk / otur",
}

func _setup_input_map() -> void:
	for action in DEFAULT_BINDINGS:
		_set_action_keys(action, DEFAULT_BINDINGS[action])
	# Shift+R: acil fren sıfırlama (yeniden atanabilir değil, sabit)
	if not InputMap.has_action("emergency_reset"):
		InputMap.add_action("emergency_reset")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		ev.shift_pressed = true
		InputMap.action_add_event("emergency_reset", ev)
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("interact", mb)
	# Yakınlaştırma için sağ fare tuşu da geçerli
	var zm := InputEventMouseButton.new()
	zm.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("zoom", zm)
	if not InputMap.has_action("toggle_mouse"):
		InputMap.add_action("toggle_mouse")
		var ev2 := InputEventKey.new()
		ev2.physical_keycode = KEY_M
		InputMap.action_add_event("toggle_mouse", ev2)

func _set_action_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

## Ayarlar menüsü: tek bir tuş ataması değiştirir (ilk tuş), ikincil tuş korunur.
func rebind_action(action: String, keycode: int) -> void:
	if not DEFAULT_BINDINGS.has(action):
		return
	_set_action_keys(action, [keycode])
	if action == "zoom":
		var zm := InputEventMouseButton.new()
		zm.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("zoom", zm)

func binding_text(action: String) -> String:
	var evs := InputMap.action_get_events(action)
	var names: Array[String] = []
	for e in evs:
		if e is InputEventKey:
			var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			var n := OS.get_keycode_string(kc)
			if e.shift_pressed:
				n = "Shift+" + n
			names.append(n)
	return " / ".join(names)
