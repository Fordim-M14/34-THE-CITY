extends Node
## UnitTests — rota verisi, sinyal üretimi, dönüş aynalama, puanlama, kariyer ve ayarlar.
##   godot --headless --path . res://tests/UnitTests.tscn

var failures: Array[String] = []
var checks := 0

func _check(cond: bool, name: String) -> void:
	checks += 1
	if cond:
		print("  [OK]   ", name)
	else:
		print("  [FAIL] ", name)
		failures.append(name)

func _ready() -> void:
	print("--- RouteData ---")
	var r := GameState.route_forward
	_check(r != null and r.stations.size() == 6, "Hat 4 yüklendi, 6 istasyon")
	_check(r.track_length > 8300.0, "Hat uzunluğu > 8300 m (%.1f)" % r.track_length)
	for i in r.stations.size() - 1:
		_check(float(r.stations[i]["stop_pos"]) < float(r.stations[i + 1]["stop_pos"]), "İstasyon sırası artan: %s < %s" % [r.stations[i]["id"], r.stations[i + 1]["id"]])
	_check(r.get_speed_limit_kmh(100.0) == 40.0 and r.get_speed_limit_kmh(1000.0) == 70.0, "Hız limiti sorgusu")
	_check(r.get_segment_type(3500.0) == "tunnel" and r.get_segment_type(1000.0) == "tunnel", "Segment tipi sorgusu (tamamen yer altı)")
	var dep := 0
	var app := 0
	var blk := 0
	for s in r.signals:
		match s["type"]:
			"departure": dep += 1
			"approach": app += 1
			"block": blk += 1
	_check(dep == 5 and app == 5 and blk >= 3, "Sinyal üretimi: %d kalkış, %d yaklaşım, %d blok" % [dep, app, blk])
	var sorted := r.signals.duplicate()
	sorted.sort_custom(func(a, b): return float(a["pos"]) < float(b["pos"]))
	var ok_order := true
	for i in sorted.size() - 1:
		if float(sorted[i + 1]["pos"]) - float(sorted[i]["pos"]) < 50.0:
			ok_order = false
	_check(ok_order, "Sinyaller arası en az 50 m")
	_check(absf(r.get_grade(3000.0)) < 0.02 and r.get_grade(3000.0) > 0.0, "Eğim hesabı (+%.3f @ 3000 m)" % r.get_grade(3000.0))

	print("--- Dönüş yönü (reversed) ---")
	var rv := r.reversed()
	_check(rv.stations.size() == 6 and str(rv.stations[0]["id"]) == "PND" and str(rv.stations[5]["id"]) == "SGH", "Dönüşte istasyon sırası ters")
	_check(str(rv.stations[0]["door_side"]) == "left", "Dönüşte kapı tarafı ters (sol)")
	var pnd_f := r.get_station_by_id("PND")
	var pnd_r := rv.get_station_by_id("PND")
	var mirror_ok := absf((r.track_length - float(pnd_f["platform_end"])) - float(pnd_r["platform_start"])) < 0.01
	_check(mirror_ok, "Peron aynalama tutarlı")
	var stop_in_platform := float(pnd_r["stop_pos"]) > float(pnd_r["platform_start"]) and float(pnd_r["stop_pos"]) < float(pnd_r["platform_end"])
	_check(stop_in_platform, "Dönüşte duruş noktası peron içinde")
	var lim_mirror := rv.get_speed_limit_kmh(r.track_length - 100.0) == r.get_speed_limit_kmh(100.0)
	_check(lim_mirror, "Hız limitleri aynalandı")
	_check(rv.get_segment_type(r.track_length - 3500.0) == "tunnel", "Segmentler aynalandı")
	_check(absf(rv.track_length - r.track_length) < 1.0, "Ters eğri uzunluğu eşit")
	_check(rv.schedule_for(5) == r.schedule_for(5) and rv.schedule_for(0) == 0.0, "Dönüş tarifesi (toplam korunur)")

	print("--- Scoring ---")
	Scoring.reset()
	_check(Scoring.total_score() == 100, "Başlangıç 100 puan")
	Scoring.add_penalty("spad", "test")
	_check(Scoring.total_score() == 85 and Scoring.category_scores[Scoring.Cat.SAFETY] == 10, "SPAD −15 güvenlik")
	Scoring.add_penalty("buffer_hit")
	_check(Scoring.category_scores[Scoring.Cat.SAFETY] == 0, "Kategori 0'ın altına inmez")
	Scoring.record_arrival({"id": "X", "name": "X"}, 0.2, 35.0, 20.0)
	_check(Scoring.category_scores[Scoring.Cat.TIMING] == 21, "35 sn gecikme (tolerans 20) → −4 zamanlama")
	_check(Scoring.total_score() == 71 and Scoring.grade() == "C", "Not hesabı (71 → C)")
	Scoring.reset()

	print("--- Career ---")
	var had := Career.has_profile
	var backup := Career.profile.duplicate(true) if had else {}
	Career.new_profile("Test Makinist")
	_check(Career.has_profile and Career.level() == 1 and Career.rank_name() == "Aday Makinist", "Yeni profil: seviye 1, Aday Makinist")
	_check(Career.profile["daily"]["tasks"].size() == 3 and Career.profile["weekly"]["tasks"].size() == 2, "Günlük 3 / haftalık 2 görev atandı")
	_check(not Career.is_unlocked("reverse") and not Career.is_unlocked("free"), "Seviye 1'de dönüş ve serbest sürüş kilitli")
	Scoring.reset()
	Scoring.stats["stops"] = [{"id": "KRT", "name": "Kurtköy", "err": 0.1, "delta": 3.0}, {"id": "PND", "name": "Pendik", "err": 0.2, "delta": -5.0}]
	Scoring.stats["distance_m"] = 8000.0
	Scoring.stats["passengers_boarded"] = 120
	var res := Career.complete_mission(r, "")
	_check(res["xp"] > 150 and res["xp"] < 900 and res["money"] > 500, "Sefer ödülü dengeli: +%d XP, +%d ₺" % [int(res["xp"]), int(res["money"])])
	_check("first_mission" in Career.profile["achievements"] and "precise" in Career.profile["achievements"] and "marmaray" in Career.profile["achievements"], "Başarımlar: ilk sefer, hassas, marmaray")
	_check(int(Career.profile["stats"]["missions"]) == 1 and int(Career.profile["stats"]["perfect_stops"]) == 2, "İstatistikler güncellendi")
	var lvl_after := Career.level()
	_check(Career.load_profile() and Career.profile["name"] == "Test Makinist" and Career.level() == lvl_after, "Kayıt/yükleme tutarlı")
	for i in 6:
		Scoring.reset()
		Scoring.stats["stops"] = [{"id": "PND", "name": "Pendik", "err": 0.1, "delta": 0.0}]
		Career.complete_mission(r, "")
	_check(Career.level() >= 2 and Career.level() <= 4 and Career.is_unlocked("reverse"), "7 seferden sonra seviye 2–4, dönüş açıldı (seviye %d)" % Career.level())
	var failed := Career.complete_mission(r, "Tampona çarpma")
	_check(int(failed["xp"]) < 100 and int(Career.profile["stats"]["failed"]) == 1, "Başarısız sefer düşük ödül")
	# Geri yükle
	if had:
		Career.profile = backup
		Career.save_profile()
	else:
		Career.delete_profile()

	print("--- Settings / Input ---")
	GameState.rebind_action("horn", KEY_J)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	_check(InputMap.event_is_action(ev, "horn"), "Tuş yeniden atama (korna → J)")
	GameState.rebind_action("horn", KEY_H)
	_check(GameState.binding_text("emergency_reset") == "Shift+R", "Shift+R etiketi")
	_check(GameState.density_for_hour(8.0) > GameState.density_for_hour(13.0) and GameState.density_for_hour(2.0) < 0.5, "Saate göre yoğunluk")

	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  HATA: ", f)
	print("[TEST] %s" % ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
