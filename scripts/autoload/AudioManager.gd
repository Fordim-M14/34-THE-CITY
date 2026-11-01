extends Node
## AudioManager — prosedürel ses motoru (autoload). Dış ses dosyası gerektirmeden
## çalışma anında sentezlenen döngüler: çekiş inverteri vınlaması (hızla değişen perde),
## ray/tekerlek gürültüsü, ray eki takırtısı, fren hışırtısı ve gıcırtısı, kapı ikazı ve
## kapı motoru, korna, düğme tıkı, merkez mesaj tonu, ATP uyarısı, acil fren alarmı,
## kabin ortam uğultusu. Türkçe anonslar assets/audio/announce/ altındaki WAV'lardan
## (espeak-ng ile üretilmiş) çalınır. Ortam yankısı (tünel/istasyon/açık) reverb ile.

const MIX_RATE := 22050

var train: TrainController
var mission: MissionManager
var route: RouteData
var faults: FaultManager

var p_motor: AudioStreamPlayer
var p_rail: AudioStreamPlayer
var p_brake: AudioStreamPlayer
var p_squeal: AudioStreamPlayer
var p_ambience: AudioStreamPlayer
var p_alarm: AudioStreamPlayer
var p_atp: AudioStreamPlayer
var p_fx: AudioStreamPlayer
var p_fx2: AudioStreamPlayer
var p_clack: AudioStreamPlayer
var p_announce: AudioStreamPlayer
var p_chime: AudioStreamPlayer

var s_clack: AudioStreamWAV
var s_click: AudioStreamWAV
var s_chime: AudioStreamWAV
var s_door_motor: AudioStreamWAV
var s_horn: AudioStreamWAV
var s_msg: AudioStreamWAV
var s_beep: AudioStreamWAV

var _clack_dist := 0.0
var _reverb: AudioEffectReverb
var _chime_count := 0
var _chime_timer := 0.0
var _announce_queue: Array[String] = []
var _attached := false
var zone_gain := 1.0         # dinleyici bölgesi (kabin 1.0 / vagon 0.55) — AmbienceManager ayarlar
var master_volume := 1.0
var sfx_volume := 1.0
var announce_volume := 1.0
var _env := "tunnel"

func _ready() -> void:
	_setup_buses()
	_make_streams()
	_make_players()

func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "SFX")
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.8
		_reverb.damping = 0.4
		_reverb.wet = 0.3
		_reverb.dry = 0.9
		AudioServer.add_bus_effect(i, _reverb)
	else:
		_reverb = AudioServer.get_bus_effect(AudioServer.get_bus_index("SFX"), 0) as AudioEffectReverb
	if AudioServer.get_bus_index("Announce") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Announce")

func _player(bus: String, vol_db: float = 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = vol_db
	add_child(p)
	return p

func _make_players() -> void:
	p_motor = _player("SFX", -14.0)
	p_motor.stream = _loop_motor()
	p_rail = _player("SFX", -20.0)
	p_rail.stream = _loop_noise(2.0, 0.5, 3)
	p_brake = _player("SFX", -40.0)
	p_brake.stream = _loop_noise(1.5, 1.0, 1)
	p_squeal = _player("SFX", -60.0)
	p_squeal.stream = _loop_squeal()
	p_ambience = _player("SFX", -26.0)
	p_ambience.stream = _loop_ambience()
	p_alarm = _player("SFX", -12.0)
	p_alarm.stream = _loop_alarm()
	p_atp = _player("SFX", -10.0)
	p_atp.stream = _loop_atp()
	p_fx = _player("SFX", -6.0)
	p_fx2 = _player("SFX", -8.0)
	p_clack = _player("SFX", -16.0)
	p_chime = _player("SFX", -8.0)
	p_announce = _player("Announce", -4.0)
	p_announce.finished.connect(_on_announce_finished)

# ---------------------------------------------------------------------------
# Sentez yardımcıları

func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _loop_motor() -> AudioStreamWAV:
	# 100 Hz temel + harmonikler; 1 s döngü (tam periyot sayısı)
	var n := MIX_RATE
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		v += 0.5 * sin(TAU * 100.0 * t)
		v += 0.25 * sin(TAU * 200.0 * t)
		v += 0.15 * sin(TAU * 300.0 * t + 0.5)
		v += 0.1 * sin(TAU * 500.0 * t)
		v += 0.08 * sign(sin(TAU * 100.0 * t))   # kare bileşen (inverter)
		s[i] = v * 0.6
	return _wav(s, true)

func _loop_noise(seconds: float, smooth: float, seed: int) -> AudioStreamWAV:
	var n := int(MIX_RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var prev := 0.0
	var a := clampf(1.0 - smooth * 0.9, 0.05, 1.0)
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		prev = prev + a * (w - prev)   # basit alçak geçiren
		s[i] = prev * 0.8
	# Kesintisiz döngü için uçları yumuşat
	var fade := 400
	for i in fade:
		var f := float(i) / fade
		s[i] *= f
		s[n - 1 - i] *= f
	return _wav(s, true)

func _loop_squeal() -> AudioStreamWAV:
	var n := MIX_RATE
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var vib := 1.0 + 0.01 * sin(TAU * 6.0 * t)
		s[i] = 0.5 * sin(TAU * 2600.0 * vib * t) + 0.2 * sin(TAU * 3900.0 * t)
	return _wav(s, true)

func _loop_ambience() -> AudioStreamWAV:
	var n := MIX_RATE * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var w := rng.randf_range(-1.0, 1.0)
		prev = prev + 0.02 * (w - prev)
		s[i] = 0.3 * sin(TAU * 60.0 * t) + 0.15 * sin(TAU * 120.0 * t) + prev * 2.0
	var fade := 400
	for i in fade:
		var f := float(i) / fade
		s[i] *= f
		s[n - 1 - i] *= f
	return _wav(s, true)

func _loop_alarm() -> AudioStreamWAV:
	var n := MIX_RATE
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 880.0 if fmod(t, 0.5) < 0.25 else 660.0
		s[i] = 0.5 * sin(TAU * f * t)
	return _wav(s, true)

func _loop_atp() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = (0.5 * sin(TAU * 1200.0 * t)) if fmod(t, 0.25) < 0.1 else 0.0
	return _wav(s, true)

func _one_shot(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(MIX_RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = fn.call(float(i) / MIX_RATE, seconds)
	return _wav(s, false)

func _make_streams() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	s_clack = _one_shot(0.12, func(t: float, d: float) -> float:
		return rng.randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.9)
	s_click = _one_shot(0.05, func(t: float, d: float) -> float:
		return (sin(TAU * 1800.0 * t) + rng.randf_range(-0.3, 0.3)) * exp(-t * 90.0) * 0.6)
	s_chime = _one_shot(0.45, func(t: float, d: float) -> float:
		return (0.6 * sin(TAU * 880.0 * t) + 0.3 * sin(TAU * 1320.0 * t)) * exp(-t * 7.0))
	s_door_motor = _one_shot(1.6, func(t: float, d: float) -> float:
		var env := sin(PI * t / d)
		return rng.randf_range(-1.0, 1.0) * 0.35 * env + 0.25 * env * sin(TAU * (180.0 + 60.0 * t) * t))
	s_horn = _one_shot(1.2, func(t: float, d: float) -> float:
		var env := minf(1.0, t * 20.0) * minf(1.0, (d - t) * 8.0)
		return env * (0.4 * sin(TAU * 440.0 * t) + 0.35 * sin(TAU * 554.4 * t) + 0.15 * sin(TAU * 880.0 * t)))
	s_msg = _one_shot(0.6, func(t: float, d: float) -> float:
		var f := 660.0 if t < 0.3 else 990.0
		return 0.5 * sin(TAU * f * t) * exp(-fmod(t, 0.3) * 6.0))
	s_beep = _one_shot(0.15, func(t: float, d: float) -> float:
		return 0.5 * sin(TAU * 1000.0 * t) * exp(-t * 10.0))

# ---------------------------------------------------------------------------
# Bağlama ve güncelleme

func attach(p_train: TrainController, p_mission: MissionManager, p_route: RouteData, p_faults: FaultManager) -> void:
	train = p_train
	mission = p_mission
	route = p_route
	faults = p_faults
	_attached = true
	train.horn_sounded.connect(func() -> void: _play(p_fx, s_horn))
	train.doors.doors_closing.connect(_on_doors_closing)
	train.doors.doors_opened.connect(func(_s, _st, _c) -> void: _play(p_fx2, s_door_motor))
	train.emergency_changed.connect(_on_emergency_changed)
	apply_settings()
	p_ambience.play()
	p_motor.play()
	p_rail.play()
	p_brake.play()
	p_squeal.play()
	# Hoş geldiniz anonsu: PISSystem tetikler (v0.4)

func detach() -> void:
	_attached = false
	for p in [p_motor, p_rail, p_brake, p_squeal, p_ambience, p_alarm, p_atp]:
		p.stop()
	train = null

func apply_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Announce"), linear_to_db(maxf(announce_volume, 0.0001)))

func _play(p: AudioStreamPlayer, s: AudioStream) -> void:
	p.stream = s
	p.play()

func play_click() -> void:
	_play(p_fx2, s_click)

func play_message_tone() -> void:
	_play(p_fx2, s_msg)

func play_beep() -> void:
	_play(p_fx2, s_beep)

func _process(delta: float) -> void:
	if not _attached or train == null or not is_instance_valid(train):
		return
	if GameState.paused:
		return
	var v := train.speed_kmh()
	var lever := train.lever
	# Motor: perde hızla; ses çekişte yüksek, serbest akışta düşük, duruşta yok
	var pitch := 0.55 + (v / 80.0) * 3.2
	p_motor.pitch_scale = clampf(pitch, 0.5, 4.5)
	var traction_amp := 0.0
	if lever > 0.0 and not train.emergency_active() and train.doors.all_closed() and not train.traction_cut:
		traction_amp = 0.35 + 0.65 * lever
	elif lever < 0.0 and v > 2.0:
		traction_amp = 0.25 + 0.3 * absf(lever)   # rejeneratif fren inverteri
	elif v > 1.0:
		traction_amp = 0.12
	var speed_gate := clampf(v / 6.0, 0.0, 1.0)
	p_motor.volume_db = linear_to_db(maxf(traction_amp * (0.4 + 0.6 * speed_gate) * zone_gain, 0.0005)) - 10.0
	# Ray gürültüsü: hızla artar
	var rail_amp := clampf(v / 80.0, 0.0, 1.0)
	p_rail.volume_db = linear_to_db(maxf((rail_amp * rail_amp * 0.9 + rail_amp * 0.1) * (0.7 + 0.3 * zone_gain), 0.0005)) - 8.0
	p_rail.pitch_scale = 0.8 + rail_amp * 0.6
	# Ray eki takırtısı (her 12,5 m)
	_clack_dist += train.speed * delta
	if _clack_dist >= 12.5 and v > 3.0:
		_clack_dist = 0.0
		p_clack.pitch_scale = 0.9 + randf() * 0.2
		_play(p_clack, s_clack)
	# Fren hışırtısı ve gıcırtı
	var braking := (lever < -0.1 or train.emergency_active()) and v > 1.0
	var brake_amp := (absf(lever) if not train.emergency_active() else 1.0) * clampf(v / 30.0, 0.2, 1.0) if braking else 0.0
	p_brake.volume_db = linear_to_db(maxf(brake_amp * zone_gain, 0.0005)) - 14.0
	var squeal_amp := 0.0
	if braking and v < 16.0 and v > 1.5 and absf(lever) > 0.35:
		squeal_amp = (1.0 - v / 16.0) * 0.6
	p_squeal.volume_db = linear_to_db(maxf(squeal_amp, 0.0005)) - 20.0
	p_squeal.pitch_scale = 0.9 + v / 40.0
	# ATP uyarısı
	if train.atp_warning and not train.emergency_active():
		if not p_atp.playing:
			p_atp.play()
	elif p_atp.playing:
		p_atp.stop()
	# Kapı ikazı tekrarları
	if _chime_count > 0:
		_chime_timer -= delta
		if _chime_timer <= 0.0:
			_chime_timer = 0.5
			_chime_count -= 1
			_play(p_chime, s_chime)
	# Ortam yankısı
	var env := "tunnel"
	if not route.get_station_at(train.offset).is_empty():
		env = "station"
	elif route.get_segment_type(train.offset) == "open":
		env = "open"
	if env != _env:
		_env = env
		if _reverb:
			match env:
				"tunnel":
					_reverb.wet = 0.38
					_reverb.room_size = 0.85
				"station":
					_reverb.wet = 0.28
					_reverb.room_size = 0.7
				"open":
					_reverb.wet = 0.06
					_reverb.room_size = 0.3
	# Açık kesimde ray sesi daha açık, tünelde boğuk
	p_rail.volume_db += (2.0 if env == "open" else 0.0)

func _on_doors_closing(_side: String) -> void:
	_chime_count = 3
	_chime_timer = 0.0
	_play(p_fx2, s_door_motor)

func _on_emergency_changed(active: bool, _reasons: Array) -> void:
	if active:
		p_alarm.play()
	else:
		p_alarm.stop()

func _on_departed(_st: Dictionary) -> void:
	var nxt := mission.next_station()
	if not nxt.is_empty():
		announce("next_" + str(nxt["id"]))

func _on_signal_passed(sig: TrackSignal) -> void:
	# Yaklaşım sinyali geçilince varış anonsu
	if sig.signal_type == "approach" and sig.station_id != "":
		var st := route.get_station_by_id(sig.station_id)
		if not st.is_empty():
			if st.get("is_end", false):
				announce("terminus_" + sig.station_id)
			else:
				announce("arrive_%s_%s" % [sig.station_id, str(st.get("door_side", "right"))])

func _on_arrived(_st: Dictionary, _err: float) -> void:
	pass

func _on_state_changed(s: int) -> void:
	if s == MissionManager.State.READY and mission.departure_timer > 10.0:
		announce("hold")

## Anons kuyruğu (ardışık anonslar üst üste binmez). bilingual: TR'den sonra EN de çalınır.
## Aynı anons kuyrukta bekliyorsa tekrar eklenmez; "urgent" kuyruğu temizler.
var bilingual: bool = true
var last_announcement: String = ""
var _current_path: String = ""
signal announcement_started(name: String, lang: String)

## manifest.json (tools/make_announcements.py / import_voice_pack.py) anahtar → dosya eşlemesi;
## yoksa varsayılan adlandırma (<ad>.wav, <ad>_en.wav). Yeni ses paketleri dosya adı değiştirmeden takılır.
var _manifest: Dictionary = {}
var _manifest_loaded := false

func _announce_path(name: String, lang: String) -> String:
	if not _manifest_loaded:
		_manifest_loaded = true
		var mp := "res://assets/audio/announce/manifest.json"
		if FileAccess.file_exists(mp):
			var j := JSON.new()
			if j.parse(FileAccess.get_file_as_string(mp)) == OK and j.data is Dictionary:
				_manifest = (j.data as Dictionary).get("items", {})
	if _manifest.has(name):
		var f := str(_manifest[name].get("tr_file" if lang == "tr" else "en_file", ""))
		if f != "":
			return "res://assets/audio/announce/" + f
	return "res://assets/audio/announce/%s%s.wav" % [name, "" if lang == "tr" else "_en"]

func announce(name: String, urgent: bool = false) -> void:
	var path := _announce_path(name, "tr")
	if not ResourceLoader.exists(path):
		return
	if urgent:
		_announce_queue.clear()
		p_announce.stop()
	if _announce_queue.has(path) or (p_announce.playing and _current_path == path):
		return
	_announce_queue.append(path)
	if bilingual:
		var en := _announce_path(name, "en")
		if ResourceLoader.exists(en):
			_announce_queue.append(en)
	if not p_announce.playing:
		_on_announce_finished()

## Merkez telsiz sesi (kabin hoparlörü; anonslarla çakışmaz: ayrı oynatıcı)
var p_radio: AudioStreamPlayer
func play_radio(key: String) -> void:
	var path := "res://assets/audio/announce/%s.wav" % key
	if not ResourceLoader.exists(path):
		return
	if p_radio == null:
		p_radio = _player("SFX", -4.0)
	if p_radio.playing:
		return
	p_radio.stream = load(path)
	p_radio.play()

func is_announcing() -> bool:
	return p_announce.playing or not _announce_queue.is_empty()

func _on_announce_finished() -> void:
	if _announce_queue.is_empty():
		return
	var path: String = _announce_queue.pop_front()
	var s := load(path)
	if s:
		_current_path = path
		p_announce.stream = s
		p_announce.play()
		var base := path.get_file().get_basename()
		var lang := "en" if base.ends_with("_en") else "tr"
		last_announcement = base.trim_suffix("_en")
		announcement_started.emit(last_announcement, lang)
