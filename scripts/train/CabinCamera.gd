extends Camera3D
## CabinCamera v3 — makinist göz kamerası.
##  • Göz noktası GLB'deki Cam_Eye'dan gelir; koltuk yüksekliği/ileri-geri ayarı (Settings)
##  • Fare ile serbest bakış (yumuşatılmış), FOV ayarı (65–100), sağ tık/Z ile yakınlaştırma
##  • İvmeye bağlı hafif gövde sallanması ve hıza bağlı mikro titreşim (kapatılabilir)
##  • Bakış sınırları kabin geometrisine göre (yaw ±115°, pitch -55°..+40°) — kamera kabin
##    dışına çıkmaz

@export var sensitivity: float = 0.0022
@export var yaw_limit_deg: float = 115.0
@export var pitch_min_deg: float = -55.0
@export var pitch_max_deg: float = 40.0

var look_enabled: bool = true
var _yaw := 0.0
var _pitch := 0.0
var _yaw_s := 0.0
var _pitch_s := 0.0
var _zoom := false
var _sway := Vector3.ZERO
var _prev_speed := 0.0
var _shake_t := 0.0
var _prev_accel := 0.0
var _jolt := 0.0
var _joint_t := 0.0
var _joint := 0.0
var _curve_roll := 0.0
var train: TrainController

func _ready() -> void:
	current = true
	fov = Settings.fov
	_apply_seat()
	Settings.settings_applied.connect(_on_settings)

func _on_settings() -> void:
	if not _zoom:
		fov = Settings.fov
	_apply_seat()

func _apply_seat() -> void:
	position = Vector3(0.0, Settings.seat_height, -Settings.seat_forward)

func _unhandled_input(event: InputEvent) -> void:
	if not look_enabled:
		return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or GameState.auto_test_mode):
		var sens := sensitivity * Settings.mouse_sensitivity * (0.5 if _zoom else 1.0)
		_yaw -= event.relative.x * sens
		_pitch -= event.relative.y * sens
		_yaw = clampf(_yaw, deg_to_rad(-yaw_limit_deg), deg_to_rad(yaw_limit_deg))
		_pitch = clampf(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	if event.is_action_pressed("zoom"):
		_zoom = true
	elif event.is_action_released("zoom"):
		_zoom = false
	if event.is_action_pressed("recenter_view"):
		recenter()

func _process(delta: float) -> void:
	# Yumuşatılmış bakış
	var k := clampf(delta * 14.0, 0.0, 1.0)
	_yaw_s = lerp_angle(_yaw_s, _yaw, k)
	_pitch_s = lerpf(_pitch_s, _pitch, k)
	# Zoom
	var target_fov := Settings.fov * (0.45 if _zoom else 1.0)
	fov = lerpf(fov, target_fov, clampf(delta * 10.0, 0.0, 1.0))
	# Sallanma / titreşim
	var sway_pitch := 0.0
	var sway_roll := 0.0
	var offset := Vector3.ZERO
	if train and Settings.camera_sway > 0.0 and Settings.camera_shake:
		var accel := (train.speed - _prev_speed) / maxf(delta, 0.0001)
		_prev_speed = train.speed
		# Kalkış/fren hissi: ivme → gövde öne/arkaya yatar (yumuşak); ani değişimde kısa sarsıntı
		var target := Vector3(clampf(-accel * 0.6, -1.0, 1.0), 0.0, 0.0)
		_sway = _sway.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
		sway_pitch = _sway.x * deg_to_rad(1.2) * Settings.camera_sway
		var jerk := absf(accel - _prev_accel) / maxf(delta, 0.0001)
		_prev_accel = accel
		if jerk > 1.5 and train.speed > 0.2:
			_jolt = minf(_jolt + jerk * 0.004, 0.03)
		_jolt = lerpf(_jolt, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		var v := train.speed_kmh()
		# Ray titreşimi: hızla artan frekans/genlik; ray ek yerleri (her 25 m) ekstra tık
		_shake_t += delta * (8.0 + v * 0.3)
		var amp := clampf(v / 80.0, 0.0, 1.0) * 0.004 * Settings.camera_sway
		var hi := clampf((v - 55.0) / 25.0, 0.0, 1.0) * 0.0025 * Settings.camera_sway   # yüksek hız ek titreşimi
		_joint_t += train.speed * delta
		if _joint_t > 25.0:
			_joint_t -= 25.0
			_joint = 0.006 * clampf(v / 60.0, 0.3, 1.0) * Settings.camera_sway
		_joint = lerpf(_joint, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		offset = Vector3(sin(_shake_t * 1.7) * amp * 0.6 + sin(_shake_t * 5.3) * hi, sin(_shake_t) * amp + sin(_shake_t * 7.1) * hi - _joint - _jolt, 0.0)
		# Viraj: hat eğriliğine göre hafif yatış (yanal ivme)
		var curv := 0.0
		if train.world:
			var a := train.world.get_track_transform(train.offset).basis.z
			var b := train.world.get_track_transform(train.offset + 15.0).basis.z
			curv = atan2(a.cross(b).y, a.dot(b))
		var lat := clampf(curv * train.speed * train.speed / 15.0, -1.0, 1.0)
		_curve_roll = lerpf(_curve_roll, lat * deg_to_rad(1.5) * Settings.camera_sway, clampf(delta * 2.0, 0.0, 1.0))
		sway_roll = sin(_shake_t * 0.37) * deg_to_rad(0.25) * clampf(v / 60.0, 0.0, 1.0) * Settings.camera_sway + _curve_roll
	rotation = Vector3(_pitch_s + sway_pitch, _yaw_s, sway_roll)
	position = Vector3(0.0, Settings.seat_height, -Settings.seat_forward) + offset

func recenter() -> void:
	_yaw = 0.0
	_pitch = 0.0

## Test/otomasyon: bakış yönünü doğrudan ayarla (derece)
func set_look(yaw_deg: float, pitch_deg: float) -> void:
	_yaw = deg_to_rad(yaw_deg)
	_pitch = deg_to_rad(pitch_deg)
	_yaw_s = _yaw
	_pitch_s = _pitch
