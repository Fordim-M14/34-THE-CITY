class_name TrainDoors
extends Node
## TrainDoors — kapı durumu, güvenlik kilitleri, taraf kontrolü, kayar kapı animasyonu,
## kapı arızası (sıkışan kapı çifti) ve yolcu sıkışması (PassengerManager bildirir).

signal doors_opened(side: String, station: Dictionary, correct_side: bool)
signal doors_closed(side: String)
signal doors_closing(side: String)
signal door_command_rejected(reason: String)
signal door_obstructed(side: String, index: int)

enum State { CLOSED, OPENING, OPEN, CLOSING }

const ANIM_TIME := 1.6
const SLIDE := 0.66

var train: TrainController
var state: Dictionary = {"left": State.CLOSED, "right": State.CLOSED}
var stuck: Dictionary = {}          # {"side": .., "index": ..} arızalı kapı
var obstruction_check: Callable     # (side) -> int  (engellenen kapı indeksi ya da -1)
var _panels: Dictionary = {}
var _closed_positions: Dictionary = {}
var _tweens: Dictionary = {}

func setup(p_train: TrainController, left_pairs: Array, right_pairs: Array) -> void:
	train = p_train
	_panels["left"] = left_pairs
	_panels["right"] = right_pairs
	for side in _panels:
		var arr := []
		for pair in _panels[side]:
			arr.append([pair[0].position, pair[1].position])
		_closed_positions[side] = arr

func pair_count(side: String) -> int:
	return (_panels[side] as Array).size()

func all_closed() -> bool:
	return state["left"] == State.CLOSED and state["right"] == State.CLOSED

func is_open(side: String) -> bool:
	return state[side] == State.OPEN or state[side] == State.OPENING

func state_text(side: String) -> String:
	match state[side]:
		State.CLOSED: return "KAPALI"
		State.OPENING: return "AÇILIYOR"
		State.OPEN: return "AÇIK" if stuck.is_empty() or stuck["side"] != side else "AÇIK (ARIZA)"
		State.CLOSING: return "KAPANIYOR"
	return "?"

func set_stuck(side: String, index: int) -> void:
	stuck = {"side": side, "index": index}

func clear_stuck() -> void:
	stuck = {}
	# Takılı kalan kapı kapalı konuma gelsin
	for side in _panels:
		if state[side] == State.OPEN:
			_animate(side, false)

func toggle(side: String) -> void:
	if is_open(side):
		request_close(side)
	else:
		request_open(side)

func request_open(side: String) -> void:
	if state[side] != State.CLOSED:
		return
	if not train.is_stopped():
		Scoring.add_penalty("door_moving", "%d km/s" % int(train.speed_kmh()))
		door_command_rejected.emit("Hareket halinde kapı açılamaz")
		return
	var st := train.route.get_station_at(train.offset)
	if st.is_empty():
		Scoring.add_penalty("door_off_platform")
		door_command_rejected.emit("Peron dışında kapı açılamaz")
		return
	var correct := str(st.get("door_side", "right")) == side
	if not correct:
		Scoring.add_penalty("door_wrong_side", "%s — %s peron" % [str(st["name"]), "sağ" if st["door_side"] == "right" else "sol"])
	_animate(side, true)
	Scoring.log_event("%s kapılar açıldı (%s)" % ["Sol" if side == "left" else "Sağ", str(st["name"])])
	doors_opened.emit(side, st, correct)

func request_close(side: String) -> void:
	if state[side] == State.CLOSED or state[side] == State.CLOSING:
		return
	# Yolcu sıkışması kontrolü
	if obstruction_check.is_valid():
		var idx: int = obstruction_check.call(side)
		if idx >= 0:
			Scoring.add_penalty("door_obstruction", "kapı %d" % (idx + 1))
			door_obstructed.emit(side, idx)
			door_command_rejected.emit("Kapıda yolcu var! Kapı yeniden açıldı")
			_animate(side, true)
			return
	doors_closing.emit(side)
	_animate(side, false)
	Scoring.log_event("%s kapılar kapatıldı" % ["Sol" if side == "left" else "Sağ"])

func force_open(side: String) -> void:
	state[side] = State.OPEN
	var pairs: Array = _panels[side]
	var closed: Array = _closed_positions[side]
	for i in pairs.size():
		pairs[i][0].position = closed[i][0] + Vector3(0, 0, -SLIDE)
		pairs[i][1].position = closed[i][1] + Vector3(0, 0, SLIDE)

func _animate(side: String, opening: bool) -> void:
	if _tweens.has(side) and _tweens[side] is Tween and _tweens[side].is_valid():
		_tweens[side].kill()
	state[side] = State.OPENING if opening else State.CLOSING
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var pairs: Array = _panels[side]
	var closed: Array = _closed_positions[side]
	var stuck_here: bool = (not stuck.is_empty()) and str(stuck["side"]) == side
	for i in pairs.size():
		var a: Node3D = pairs[i][0]
		var b: Node3D = pairs[i][1]
		var open_this: bool = opening or (stuck_here and int(stuck["index"]) == i)
		var ta: Vector3 = closed[i][0] + (Vector3(0, 0, -SLIDE) if open_this else Vector3.ZERO)
		var tb: Vector3 = closed[i][1] + (Vector3(0, 0, SLIDE) if open_this else Vector3.ZERO)
		tw.tween_property(a, "position", ta, ANIM_TIME)
		tw.tween_property(b, "position", tb, ANIM_TIME)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		if opening:
			state[side] = State.OPEN
		elif stuck_here:
			state[side] = State.OPEN      # arızalı kapı açık kaldı
			doors_closed.emit(side)       # deneme sayımı için (FaultManager dinler)
		else:
			state[side] = State.CLOSED
			doors_closed.emit(side)
	)
	_tweens[side] = tw
