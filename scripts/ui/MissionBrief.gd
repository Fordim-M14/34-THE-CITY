extends CanvasLayer
## MissionBrief — vardiya başı görev ekranı: sefer, hat, istasyon listesi/tarife, saat,
## yolcu yoğunluğu, bilinen kısıtlamalar, kontroller.

signal accepted

@onready var title: Label = $Center/Card/VBox/Title
@onready var body: RichTextLabel = $Center/Card/VBox/Body

func show_brief(route: RouteData, traffic: TrafficManager = null) -> void:
	var m := GameState.mission
	title.text = "Sefer %s — %s (%s)" % [str(m.get("service_number", "")), route.line_name, route.direction_label]
	var lines := [
		"[color=#9adbd6]Makinist[/color]  %s%s" % [str(Career.profile.get("name", "Misafir")) if Career.has_profile else "Misafir", ("  ·  " + Career.rank_name()) if Career.has_profile else ""],
		"[color=#9adbd6]Araç[/color]  %s · %d araç     [color=#9adbd6]Saat[/color]  %s     [color=#9adbd6]Mod[/color]  %s" % [route.train_model, int(route.raw.get("train_cars", 4)), GameState.clock_text(), "Serbest sürüş" if GameState.is_free_mode() else "Kariyer vardiyası"],
		"[color=#9adbd6]Yolcu yoğunluğu[/color]  %s" % _density_text(),
		"",
		"[b]Tarife[/b] (ilk kalkıştan itibaren, tolerans ±%d sn)" % int(route.schedule_tolerance),
	]
	for s in route.stations:
		var i: int = int(s["index"])
		var t := route.schedule_for(i)
		lines.append("  %d. %-28s %02d:%02d   peron %s%s" % [i + 1, str(s["name"]), int(t) / 60, int(t) % 60, "SAĞ" if s.get("door_side") == "right" else "SOL", ("  ·  " + str(s["transfer"])) if s.has("transfer") else ""])
	lines.append("")
	if traffic and traffic.tsr_text() != "":
		lines.append("[color=#f2c94c]Dikkat:[/color] " + traffic.tsr_text())
	if traffic and traffic.lead_active:
		lines.append("[color=#9adbd6]Trafik[/color]  Öndeki sefer %s yaklaşık 4 dk önde. Blok sinyallerine uyun." % traffic.lead_service)
	lines.append("")
	lines.append("[b]Görev[/b]  Kapıları kapat → kalkış sinyali yeşil → hız sınırlarına uyarak sür → her istasyonda [b]DUR 4[/b] hizasında dur (±0,5 m) → kapıları doğru tarafta aç → yolcu iniş/binişi → kapat → kalkış izni")
	lines.append("[color=#f2c94c]Kontroller[/color]  W/S kol · N nötr · Space ACİL FREN · Shift+R acil fren sıfırlama · Q/E kapılar · R yön · F onay · L far · K kabin ışığı · H korna · Tab MMI sayfası · Fare: bakış, sol tık: kabin düğmeleri · M fareyi bırak · Esc menü")
	body.text = "\n".join(lines)
	visible = true

func _density_text() -> String:
	var d := GameState.current_density()
	if d >= 1.2:
		return "ZİRVE — çok yoğun"
	if d >= 0.7:
		return "Normal"
	if d >= 0.4:
		return "Sakin"
	return "Gece — çok az"

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("confirm"):
		visible = false
		accepted.emit()
		get_viewport().set_input_as_handled()
