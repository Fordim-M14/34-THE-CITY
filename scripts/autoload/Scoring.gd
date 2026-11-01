extends Node
## Scoring — ceza/puan hesaplaması ve olay günlüğü (autoload).
## Dört kategori, her biri 25 puan: Zamanlama, Konfor, Güvenlik, Duruş Hassasiyeti.

signal penalty_added(code: String, points: int, text: String)
signal event_logged(text: String)

enum Cat { TIMING, COMFORT, SAFETY, STOPPING }

const CAT_NAMES := {
	Cat.TIMING: "Zamanlama",
	Cat.COMFORT: "Yolcu Konforu",
	Cat.SAFETY: "Güvenlik",
	Cat.STOPPING: "Duruş Hassasiyeti",
}

## code -> [kategori, puan, açıklama]
const PENALTIES := {
	"hard_brake":       [Cat.COMFORT,  3,  "Sert fren (yolcu konforu)"],
	"harsh_accel":      [Cat.COMFORT,  2,  "Ani kalkış"],
	"jerk":             [Cat.COMFORT,  1,  "Sarsıntılı kol kullanımı"],
	"overspeed":        [Cat.SAFETY,   2,  "Hız sınırı aşımı"],
	"overspeed_atp":    [Cat.SAFETY,   8,  "ATP müdahalesi — ciddi hız aşımı"],
	"spad":             [Cat.SAFETY,   15, "SİNYAL İHLALİ — kırmızı sinyal geçildi"],
	"emergency_used":   [Cat.SAFETY,   4,  "Acil fren kullanıldı"],
	"door_wrong_side":  [Cat.SAFETY,   10, "Kapılar YANLIŞ TARAFTA açıldı"],
	"door_moving":      [Cat.SAFETY,   3,  "Hareket halinde kapı komutu"],
	"door_off_platform":[Cat.SAFETY,   8,  "Peron dışında kapı açıldı"],
	"stop_minor":       [Cat.STOPPING, 5,  "Duruş noktası sapması (>0.5 m)"],
	"stop_major":       [Cat.STOPPING, 12, "Duruş noktası sapması (>1.5 m)"],
	"stop_fail":        [Cat.STOPPING, 25, "Peron duruşu BAŞARISIZ (>3 m)"],
	"overrun":          [Cat.STOPPING, 10, "Peron geçildi, geri manevra"],
	"buffer_hit":       [Cat.SAFETY,   25, "TAMPONA ÇARPMA"],
	"station_skipped":  [Cat.SAFETY,   20, "İSTASYON ATLANDI — durulmadan geçildi"],
	"door_obstruction": [Cat.SAFETY,   6,  "Kapı yolcuya çarptı — erken kapatma"],
	"early_door_close": [Cat.COMFORT,  3,  "Yolcu inişi/binişi bitmeden kapı kapatıldı"],
	"fault_ignored":    [Cat.SAFETY,   6,  "Arıza prosedürü uygulanmadı"],
	"fault_delay":      [Cat.TIMING,   0,  "Arıza gecikmesi"],
	"tsr_violation":    [Cat.SAFETY,   5,  "Geçici hız kısıtlaması ihlali"],
	"no_headlights":    [Cat.SAFETY,   4,  "Farlar kapalı sürüş"],
	"moved_doors_open": [Cat.SAFETY,   12, "Kapılar açıkken hareket"],
	"late":             [Cat.TIMING,   0,  "Gecikme"],
	"early":            [Cat.TIMING,   0,  "Erken varış"],
}

var category_scores: Dictionary = {}
var penalties: Array = []     # [{code, points, text, time}]
var event_log: Array = []
var stats: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	category_scores = {Cat.TIMING: 25, Cat.COMFORT: 25, Cat.SAFETY: 25, Cat.STOPPING: 25}
	penalties.clear()
	event_log.clear()
	stats = {
		"max_speed_kmh": 0.0,
		"overspeed_seconds": 0.0,
		"hard_brakes": 0,
		"emergency_count": 0,
		"stop_error_m": 0.0,
		"mission_time": 0.0,
		"schedule_delta": 0.0,
		"spad_count": 0,
		"stops": [],              # [{id, name, err, delta}]
		"stations_served": 0,
		"passengers_boarded": 0,
		"passengers_alighted": 0,
		"faults": 0,
		"faults_resolved": 0,
		"distance_m": 0.0,
		"moving_seconds": 0.0,
	}

func add_penalty(code: String, extra_text: String = "", override_points: int = -1) -> void:
	if not PENALTIES.has(code):
		push_warning("Scoring: bilinmeyen ceza kodu %s" % code)
		return
	var def: Array = PENALTIES[code]
	var cat: int = def[0]
	var pts: int = def[1] if override_points < 0 else override_points
	var text: String = def[2]
	if extra_text != "":
		text += " — " + extra_text
	category_scores[cat] = max(0, int(category_scores[cat]) - pts)
	var entry := {"code": code, "points": pts, "text": text, "time": GameState.mission_time, "cat": cat}
	penalties.append(entry)
	log_event("[-%d] %s" % [pts, text])
	penalty_added.emit(code, pts, text)

func log_event(text: String) -> void:
	var t := GameState.mission_time
	var stamp := "%02d:%02d" % [int(t) / 60, int(t) % 60]
	event_log.append("%s  %s" % [stamp, text])
	event_logged.emit(text)

func total_score() -> int:
	var t := 0
	for k in category_scores:
		t += int(category_scores[k])
	return t

func grade() -> String:
	var s := total_score()
	if s >= 95: return "A+"
	if s >= 88: return "A"
	if s >= 78: return "B"
	if s >= 65: return "C"
	if s >= 50: return "D"
	return "F"

## Görev sonunda zamanlama puanını hesaplar (tek varış; eski API).
func finalize_timing(mission_time: float, schedule: float, tolerance: float) -> void:
	stats["mission_time"] = mission_time
	var delta := mission_time - schedule
	stats["schedule_delta"] = delta
	_apply_timing_penalty(delta, tolerance, "")

## Bir istasyona varış zamanlamasını kaydeder (çok duraklı seferler).
func record_arrival(station: Dictionary, err_m: float, delta_s: float, tolerance: float) -> void:
	var entry := {"id": str(station["id"]), "name": str(station["name"]), "err": err_m, "delta": delta_s}
	(stats["stops"] as Array).append(entry)
	stats["stations_served"] = int(stats["stations_served"]) + 1
	stats["schedule_delta"] = delta_s
	_apply_timing_penalty(delta_s, tolerance, str(station["name"]), 8)

func _apply_timing_penalty(delta: float, tolerance: float, where: String, cap: int = 25) -> void:
	var over := absf(delta) - tolerance
	if over > 0.0:
		var pts := int(clamp(ceil(over / 10.0) * 2.0, 0.0, float(cap)))
		var code := "late" if delta > 0.0 else "early"
		var txt := "%d sn %s" % [int(absf(delta)), "geç" if delta > 0.0 else "erken"]
		if where != "":
			txt = where + ": " + txt
		add_penalty(code, txt, pts)
	else:
		log_event("Tarifeye uygun varış (%+d sn)%s" % [int(delta), (" — " + where) if where != "" else ""])

func summary_lines() -> Array[String]:
	var lines: Array[String] = []
	for cat in [Cat.TIMING, Cat.COMFORT, Cat.SAFETY, Cat.STOPPING]:
		lines.append("%-20s %2d / 25" % [CAT_NAMES[cat], int(category_scores[cat])])
	return lines
