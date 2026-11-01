extends Node
## Career — makinist kariyeri (autoload): profil, deneyim/seviye/rütbe, oyun içi maaş,
## kilit açma, günlük/haftalık görevler, başarımlar, istatistikler, kayıt/yükleme.
## Tüm para tamamen oyun içi sanal paradır (₺ olarak gösterilir).

signal profile_changed
signal achievement_unlocked(id: String, title: String)
signal task_completed(task: Dictionary)

const SAVE_PATH := "user://career.json"
const LEVEL_XP := [0, 400, 1000, 1800, 2900, 4300, 6000, 8200, 11000, 14500, 18500, 23000]
const RANKS := {1: "Aday Makinist", 2: "Makinist", 4: "Kıdemli Makinist", 6: "Uzman Makinist", 8: "Baş Makinist", 10: "Eğitmen Makinist"}

const ACHIEVEMENTS := {
	"first_mission": {"title": "İlk Vardiya", "desc": "İlk seferini tamamla", "xp": 40},
	"precise": {"title": "Hassas Makinist", "desc": "Bir seferde tüm istasyonlarda ±0,5 m duruş", "xp": 90},
	"punctual": {"title": "Dakik", "desc": "Bir seferde tüm istasyonlara tarifede var", "xp": 80},
	"safe_hands": {"title": "Güvenli Eller", "desc": "Güvenlik 25/25 ile sefer tamamla", "xp": 60},
	"night_owl": {"title": "Gece Kuşu", "desc": "Bir gece seferi tamamla", "xp": 60},
	"marmaray": {"title": "Marmaray Aktarması", "desc": "Pendik'e sefer tamamla", "xp": 40},
	"ten_missions": {"title": "On Sefer", "desc": "10 sefer tamamla", "xp": 150},
	"hundred_km": {"title": "100 Kilometre", "desc": "Toplam 100 km sür", "xp": 150},
	"fault_master": {"title": "Arıza Ustası", "desc": "Toplam 5 arızayı prosedürle gider", "xp": 120},
	"grade_a": {"title": "A Sınıfı", "desc": "A veya A+ ile sefer tamamla", "xp": 80},
	"return_trip": {"title": "Gidiş-Dönüş", "desc": "Dönüş yönünde sefer tamamla", "xp": 60},
	"rush_hour": {"title": "Zirve Saat", "desc": "Zirve saatte (07:00–09:30) sefer tamamla", "xp": 60},
}

const DAILY_POOL := [
	{"id": "d_mission", "title": "1 sefer tamamla", "type": "missions", "goal": 1, "xp": 40, "money": 150},
	{"id": "d_precise3", "title": "3 istasyonda ±0,5 m duruş", "type": "perfect_stops", "goal": 3, "xp": 60, "money": 200},
	{"id": "d_nospad", "title": "Sinyal ihlalsiz 1 sefer", "type": "clean_safety", "goal": 1, "xp": 50, "money": 150},
	{"id": "d_km", "title": "10 km sür", "type": "km", "goal": 10, "xp": 45, "money": 120},
	{"id": "d_ontime", "title": "4 istasyona tarifede var", "type": "on_time_stops", "goal": 4, "xp": 55, "money": 180},
	{"id": "d_passengers", "title": "300 yolcu taşı", "type": "passengers", "goal": 300, "xp": 45, "money": 140},
]
const WEEKLY_POOL := [
	{"id": "w_missions", "title": "Haftada 5 sefer", "type": "missions", "goal": 5, "xp": 200, "money": 900},
	{"id": "w_score", "title": "3 seferde 85+ puan", "type": "high_score", "goal": 3, "xp": 180, "money": 700},
	{"id": "w_km", "title": "40 km sür", "type": "km", "goal": 40, "xp": 150, "money": 600},
	{"id": "w_faults", "title": "3 arıza gider", "type": "faults", "goal": 3, "xp": 150, "money": 500},
]

var profile: Dictionary = {}
var has_profile: bool = false

func _ready() -> void:
	load_profile()

func new_profile(driver_name: String) -> void:
	profile = {
		"name": driver_name,
		"created": Time.get_datetime_string_from_system(),
		"xp": 0, "level": 1, "money": 1500,
		"stats": {"missions": 0, "failed": 0, "distance_m": 0.0, "on_time_stops": 0, "total_stops": 0,
			"perfect_stops": 0, "score_sum": 0, "safety_sum": 0, "comfort_sum": 0, "passengers": 0,
			"faults_resolved": 0, "spad": 0, "emergency": 0, "play_time_s": 0.0, "night_missions": 0},
		"achievements": [],
		"daily": {"date": "", "tasks": []},
		"weekly": {"week": "", "tasks": []},
		"history": [],
		"service_counter": 4107,
	}
	has_profile = true
	_refresh_tasks()
	save_profile()
	profile_changed.emit()

func save_profile() -> void:
	if not has_profile:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "  "))

func load_profile() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		has_profile = false
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		has_profile = false
		return false
	profile = json.data
	has_profile = true
	_refresh_tasks()
	return true

func delete_profile() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	profile = {}
	has_profile = false
	profile_changed.emit()

# ---------------------------------------------------------------------------
# Seviye / rütbe / kilitler

func level_for_xp(xp: int) -> int:
	var lvl := 1
	for i in LEVEL_XP.size():
		if xp >= LEVEL_XP[i]:
			lvl = i + 1
	return lvl

func xp_to_next() -> int:
	var lvl: int = int(profile.get("level", 1))
	if lvl >= LEVEL_XP.size():
		return 0
	return LEVEL_XP[lvl] - int(profile.get("xp", 0))

func rank_name(lvl: int = -1) -> String:
	if lvl < 0:
		lvl = int(profile.get("level", 1))
	var best := "Aday Makinist"
	for k in RANKS:
		if lvl >= k:
			best = RANKS[k]
	return best

func level() -> int:
	return int(profile.get("level", 1))

func unlocks() -> Array:
	# [{"level", "title", "unlocked"}]
	var lvl := level() if has_profile else 1
	return [
		{"level": 1, "title": "Hat 4 gidiş seferi (gündüz)", "unlocked": true},
		{"level": 2, "title": "Dönüş seferleri (Pendik → Havalimanı)", "unlocked": lvl >= 2},
		{"level": 3, "title": "Serbest sürüş modu", "unlocked": lvl >= 3},
		{"level": 3, "title": "Gece seferleri", "unlocked": lvl >= 3},
		{"level": 4, "title": "Zirve saat seferleri (yoğun yolcu)", "unlocked": lvl >= 4},
		{"level": 5, "title": "Yüksek arıza yoğunluğu (zorlu vardiya)", "unlocked": lvl >= 5},
	]

func is_unlocked(feature: String) -> bool:
	var lvl := level() if has_profile else 1
	match feature:
		"reverse": return lvl >= 2
		"free": return lvl >= 3
		"night": return lvl >= 3
		"rush": return lvl >= 4
		"hard": return lvl >= 5
	return true

func next_service_number() -> String:
	var n: int = int(profile.get("service_counter", 4107))
	profile["service_counter"] = n + 2
	return str(n)

# ---------------------------------------------------------------------------
# Görev tamamlama

func complete_mission(route: RouteData, failed_reason: String) -> Dictionary:
	var score := Scoring.total_score()
	var grade := Scoring.grade()
	var st := Scoring.stats
	var result := {"score": score, "grade": grade, "xp": 0, "money": 0, "level_before": level(), "level_after": level(),
		"new_achievements": [], "completed_tasks": [], "career": has_profile and not GameState.is_free_mode()}
	if not has_profile or GameState.is_free_mode():
		return result
	var s: Dictionary = profile["stats"]
	var stops: Array = st.get("stops", [])
	var failed := failed_reason != ""
	# Ödüller
	var xp := 40 + int(score * 1.2)
	var money := 250 + score * 5
	var on_time := 0
	var perfect := 0
	for sp in stops:
		if absf(float(sp["delta"])) <= route.schedule_tolerance:
			on_time += 1
		if absf(float(sp["err"])) <= 0.5:
			perfect += 1
	xp += perfect * 8 + on_time * 6
	money += perfect * 40 + on_time * 30 + int(st.get("passengers_boarded", 0)) * 0.5
	if failed:
		xp = int(xp * 0.3)
		money = int(money * 0.3) - 200
	money = maxi(money, 0)
	if int(st.get("spad_count", 0)) > 0:
		money = int(money * 0.5)
	if not bool(GameState.mission.get("faults_enabled", true)):
		xp = int(xp * 0.8)
		money = int(money * 0.8)
	# İstatistikler
	s["missions"] = int(s["missions"]) + 1
	if failed:
		s["failed"] = int(s["failed"]) + 1
	s["distance_m"] = float(s["distance_m"]) + float(st.get("distance_m", 0.0))
	s["on_time_stops"] = int(s["on_time_stops"]) + on_time
	s["total_stops"] = int(s["total_stops"]) + stops.size()
	s["perfect_stops"] = int(s["perfect_stops"]) + perfect
	s["score_sum"] = int(s["score_sum"]) + score
	s["safety_sum"] = int(s["safety_sum"]) + int(Scoring.category_scores[Scoring.Cat.SAFETY])
	s["comfort_sum"] = int(s["comfort_sum"]) + int(Scoring.category_scores[Scoring.Cat.COMFORT])
	s["passengers"] = int(s["passengers"]) + int(st.get("passengers_boarded", 0)) + int(st.get("passengers_alighted", 0))
	s["faults_resolved"] = int(s["faults_resolved"]) + int(st.get("faults_resolved", 0))
	s["spad"] = int(s["spad"]) + int(st.get("spad_count", 0))
	s["emergency"] = int(s["emergency"]) + int(st.get("emergency_count", 0))
	s["play_time_s"] = float(s["play_time_s"]) + GameState.mission_time
	if GameState.is_night():
		s["night_missions"] = int(s["night_missions"]) + 1
	# Başarımlar
	var new_ach: Array = []
	if not failed:
		_try_ach("first_mission", true, new_ach)
		_try_ach("precise", stops.size() >= 2 and perfect == stops.size(), new_ach)
		_try_ach("punctual", stops.size() >= 2 and on_time == stops.size(), new_ach)
		_try_ach("safe_hands", int(Scoring.category_scores[Scoring.Cat.SAFETY]) == 25, new_ach)
		_try_ach("night_owl", GameState.is_night(), new_ach)
		_try_ach("marmaray", str(route.get_end_station().get("id", "")) == "PND", new_ach)
		_try_ach("grade_a", grade == "A" or grade == "A+", new_ach)
		_try_ach("return_trip", route.direction == "reverse", new_ach)
		var h := float(GameState.mission.get("start_time_s", 0)) / 3600.0
		_try_ach("rush_hour", h >= 7.0 and h < 9.5, new_ach)
	_try_ach("ten_missions", int(s["missions"]) >= 10, new_ach)
	_try_ach("hundred_km", float(s["distance_m"]) >= 100000.0, new_ach)
	_try_ach("fault_master", int(s["faults_resolved"]) >= 5, new_ach)
	for a in new_ach:
		xp += int(ACHIEVEMENTS[a]["xp"])
	# Görevler
	var done_tasks: Array = []
	var progress := {"missions": 1 if not failed else 0, "perfect_stops": perfect, "clean_safety": 1 if (not failed and int(st.get("spad_count", 0)) == 0) else 0,
		"km": float(st.get("distance_m", 0.0)) / 1000.0, "on_time_stops": on_time, "passengers": int(st.get("passengers_boarded", 0)) + int(st.get("passengers_alighted", 0)),
		"high_score": 1 if score >= 85 else 0, "faults": int(st.get("faults_resolved", 0))}
	for group in ["daily", "weekly"]:
		for t in profile[group]["tasks"]:
			if t.get("done", false):
				continue
			t["progress"] = float(t.get("progress", 0.0)) + float(progress.get(t["type"], 0))
			if float(t["progress"]) >= float(t["goal"]):
				t["done"] = true
				xp += int(t["xp"])
				money += int(t["money"])
				done_tasks.append(t)
				task_completed.emit(t)
	# XP / seviye / para
	profile["xp"] = int(profile["xp"]) + xp
	var new_level := level_for_xp(int(profile["xp"]))
	profile["level"] = new_level
	profile["money"] = int(profile["money"]) + money
	s["earned_total"] = int(s.get("earned_total", 0)) + money
	# Geçmiş
	var hist: Array = profile["history"]
	hist.push_front({"date": Time.get_datetime_string_from_system(), "service": str(GameState.mission.get("service_number", "")),
		"route": route.line_name, "direction": route.direction, "score": score, "grade": grade, "failed": failed_reason,
		"xp": xp, "money": money, "stops": stops.size()})
	while hist.size() > 30:
		hist.pop_back()
	result["xp"] = xp
	result["money"] = money
	result["level_after"] = new_level
	result["new_achievements"] = new_ach
	result["completed_tasks"] = done_tasks
	save_profile()
	profile_changed.emit()
	return result

func _try_ach(id: String, cond: bool, out: Array) -> void:
	if not cond:
		return
	var list: Array = profile["achievements"]
	if id in list:
		return
	list.append(id)
	out.append(id)
	achievement_unlocked.emit(id, ACHIEVEMENTS[id]["title"])

# ---------------------------------------------------------------------------
# Günlük / haftalık görevler

func _refresh_tasks() -> void:
	if not has_profile:
		return
	var today := Time.get_date_string_from_system()
	var d := Time.get_datetime_dict_from_system()
	var week := "%d-W%02d" % [d["year"], int((int(d["day"]) + 6) / 7) + (int(d["month"]) - 1) * 5]
	var rng := RandomNumberGenerator.new()
	if profile["daily"].get("date", "") != today:
		rng.seed = hash(today)
		var pool := DAILY_POOL.duplicate(true)
		var picks: Array = []
		for i in 3:
			var k := rng.randi_range(0, pool.size() - 1)
			var t: Dictionary = pool[k]
			t["progress"] = 0.0
			t["done"] = false
			picks.append(t)
			pool.remove_at(k)
		profile["daily"] = {"date": today, "tasks": picks}
	if profile["weekly"].get("week", "") != week:
		rng.seed = hash(week)
		var pool2 := WEEKLY_POOL.duplicate(true)
		var picks2: Array = []
		for i in 2:
			var k := rng.randi_range(0, pool2.size() - 1)
			var t: Dictionary = pool2[k]
			t["progress"] = 0.0
			t["done"] = false
			picks2.append(t)
			pool2.remove_at(k)
		profile["weekly"] = {"week": week, "tasks": picks2}
	save_profile()

func stats_summary() -> Array[String]:
	if not has_profile:
		return []
	var s: Dictionary = profile["stats"]
	var m := int(s["missions"])
	var lines: Array[String] = []
	lines.append("Sefer: %d (başarısız %d)" % [m, int(s["failed"])])
	lines.append("Toplam mesafe: %.1f km" % (float(s["distance_m"]) / 1000.0))
	lines.append("Zamanında varış: %d / %d istasyon (%d%%)" % [int(s["on_time_stops"]), int(s["total_stops"]), int(100.0 * float(s["on_time_stops"]) / maxf(1.0, float(s["total_stops"])))])
	lines.append("Mükemmel duruş: %d" % int(s["perfect_stops"]))
	lines.append("Ortalama puan: %.1f · Güvenlik %.1f/25 · Konfor %.1f/25" % [float(s["score_sum"]) / maxf(1.0, m), float(s["safety_sum"]) / maxf(1.0, m), float(s["comfort_sum"]) / maxf(1.0, m)])
	lines.append("Taşınan yolcu: %d · Giderilen arıza: %d" % [int(s["passengers"]), int(s["faults_resolved"])])
	lines.append("Sinyal ihlali: %d · Acil fren: %d · Gece seferi: %d" % [int(s["spad"]), int(s["emergency"]), int(s["night_missions"])])
	lines.append("Kabin süresi: %.1f saat · Makinist seviyesi: %d (%s)" % [float(s["play_time_s"]) / 3600.0, level(), rank_name()])
	lines.append("Toplam kazanç: %d ₺ (sanal) · Ortalama performans: %%%d" % [int(s.get("earned_total", 0)), int(float(s["score_sum"]) / maxf(1.0, m))])
	return lines
