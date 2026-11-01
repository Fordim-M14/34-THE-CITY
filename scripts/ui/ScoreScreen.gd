extends CanvasLayer
## ScoreScreen — görev sonu raporu: kategori puanları, istasyon bazlı duruş/tarife tablosu,
## istatistikler, cezalar, kariyer ödülleri (XP, maaş, seviye, başarımlar, görevler).

@onready var title: Label = $Center/Card/VBox/Title
@onready var grade_label: Label = $Center/Card/VBox/Grade
@onready var body: RichTextLabel = $Center/Card/VBox/Body
@onready var prompt: Label = $Center/Card/VBox/Prompt

func show_results(route: RouteData, failed_reason: String = "", result: Dictionary = {}) -> void:
	var total := Scoring.total_score()
	var grade := Scoring.grade()
	if failed_reason != "":
		title.text = "Görev başarısız — %s" % failed_reason
		grade_label.text = "F  ·  %d / 100" % total
		grade_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	else:
		title.text = "Sefer tamamlandı — %s → %s" % [str(route.get_start_station().get("name", "")), str(route.get_end_station().get("name", ""))]
		grade_label.text = "%s  ·  %d / 100" % [grade, total]
		grade_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.15) if total >= 65 else Color(1, 0.5, 0.3))
	var st := Scoring.stats
	var lines: Array[String] = []
	lines.append("[b]Kategoriler[/b]")
	for cat in [Scoring.Cat.TIMING, Scoring.Cat.COMFORT, Scoring.Cat.SAFETY, Scoring.Cat.STOPPING]:
		var sc := int(Scoring.category_scores[cat])
		lines.append("  %-22s %s  %2d / 25" % [Scoring.CAT_NAMES[cat], _bar(sc, 25), sc])
	lines.append("")
	lines.append("[b]İstasyonlar[/b]")
	for sp in st.get("stops", []):
		var err: float = float(sp["err"])
		var dl: float = float(sp["delta"])
		var ec := "#59f280" if absf(err) <= 0.5 else ("#f2c94c" if absf(err) <= 1.5 else "#ff5a4a")
		var dc := "#59f280" if absf(dl) <= route.schedule_tolerance else "#ff5a4a"
		lines.append("  %-26s duruş [color=%s]%+.2f m[/color]   tarife [color=%s]%+d sn[/color]" % [str(sp["name"]), ec, err, dc, int(dl)])
	lines.append("")
	var mt := float(st.get("mission_time", 0.0))
	var dist_km := float(st.get("distance_m", 0.0)) / 1000.0
	var mov := maxf(1.0, float(st.get("moving_seconds", 1.0)))
	var avg_kmh := (float(st.get("distance_m", 0.0)) / mov) * 3.6
	var stops_arr: Array = st.get("stops", [])
	var err_sum := 0.0
	var on_time := 0
	for sp in stops_arr:
		err_sum += absf(float(sp["err"]))
		if absf(float(sp["delta"])) <= route.schedule_tolerance:
			on_time += 1
	var pax := int(st.get("passengers_boarded", 0)) + int(st.get("passengers_alighted", 0))
	lines.append("[b]SEFER ÖZETİ[/b]")
	lines.append("  Sürüş süresi  [color=#9adbd6]%d dk %02d sn[/color]      Toplam mesafe  [color=#9adbd6]%.2f km[/color]      Taşınan yolcu  [color=#9adbd6]%d[/color]" % [int(mt) / 60, int(mt) % 60, dist_km, pax])
	lines.append("  Ortalama hız  [color=#9adbd6]%.0f km/s[/color]      Maksimum hız  [color=#9adbd6]%d km/s[/color]      Duruş hassasiyeti  [color=#9adbd6]±%.2f m[/color] (ort.)" % [avg_kmh, int(float(st.get("max_speed_kmh", 0.0))), err_sum / maxf(1.0, stops_arr.size())])
	lines.append("  Zamanında varış  [color=#9adbd6]%d / %d (%d%%)[/color]      Kazanılan XP  [color=#f2c94c]+%d[/color]      Sanal maaş  [color=#f2c94c]+%d ₺[/color]%s" % [on_time, stops_arr.size(), int(100.0 * on_time / maxf(1.0, stops_arr.size())), int(result.get("xp", 0)), int(result.get("money", 0)), "" if result.get("career", false) else "  (serbest sürüş: kariyere işlenmez)"])
	lines.append("")
	lines.append("[b]İstatistikler[/b]  süre %d:%02d · mesafe %.1f km · azami %d km/s · hız aşımı %.1f sn · sert fren %d · acil fren %d · sinyal ihlali %d" % [int(mt) / 60, int(mt) % 60, float(st.get("distance_m", 0.0)) / 1000.0, int(float(st.get("max_speed_kmh", 0.0))), float(st.get("overspeed_seconds", 0.0)), int(st.get("hard_brakes", 0)), int(st.get("emergency_count", 0)), int(st.get("spad_count", 0))])
	lines.append("  Yolcu: %d bindi, %d indi · Arıza: %d / %d giderildi" % [int(st.get("passengers_boarded", 0)), int(st.get("passengers_alighted", 0)), int(st.get("faults_resolved", 0)), int(st.get("faults", 0))])
	if Scoring.penalties.is_empty():
		lines.append("[color=#59f280]Ceza yok — kusursuz sefer.[/color]")
	else:
		lines.append("[b]Cezalar[/b]")
		var shown := 0
		for p in Scoring.penalties:
			if shown >= 6:
				lines.append("  … ve %d ceza daha" % (Scoring.penalties.size() - shown))
				break
			lines.append("  [color=#ff5a4a]−%d[/color]  %s" % [int(p["points"]), str(p["text"])])
			shown += 1
	if result.get("career", false):
		lines.append("")
		lines.append("[b]Kariyer[/b]  +%d XP · +%d ₺ (sanal)%s" % [int(result["xp"]), int(result["money"]), ("  ·  [color=#f2c94c]SEVİYE ATLADIN: %d → %d (%s)[/color]" % [int(result["level_before"]), int(result["level_after"]), Career.rank_name()]) if int(result["level_after"]) > int(result["level_before"]) else ""])
		for a in result.get("new_achievements", []):
			lines.append("  [color=#f2c94c]★ Başarım:[/color] %s" % str(Career.ACHIEVEMENTS[a]["title"]))
		for t in result.get("completed_tasks", []):
			lines.append("  [color=#9adbd6]✓ Görev tamamlandı:[/color] %s" % str(t["title"]))
	body.text = "\n".join(lines)
	prompt.text = "F5 — Yeni sefer (aynı ayarlar)      Enter — Ana menü"
	visible = true

func _bar(value: int, max_value: int) -> String:
	var n := int(round(float(value) / float(max_value) * 10.0))
	var s := ""
	for i in 10:
		s += "█" if i < n else "░"
	return s

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("confirm"):
		AudioManager.detach()
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		get_viewport().set_input_as_handled()
