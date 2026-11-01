extends Node
## AudioRegressionTest — anons kuyruğu (TR→EN sırası, tekrar/çakışma engeli, acil öncelik), istasyon
## anonsları (manifest çözümü), kapı anonsu, telsiz sesleri, ortam ses kaynakları.
##   godot --headless --path . res://tests/AudioRegressionTest.tscn
## Not: headless'ta ses çalınmaz ama AudioStreamPlayer.playing/kuyruk mantığı aynen çalışır.

var main: Node
var train: TrainController
var failures: Array[String] = []
var checks := 0
var started: Array = []    # [name, lang]

func _check(cond: bool, name: String) -> void:
	checks += 1
	print("  [%s] %s" % ["OK" if cond else "FAIL", name])
	if not cond:
		failures.append(name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	GameState.auto_test_mode = true
	var m := GameState.default_mission()
	m["seed"] = 31
	m["faults_enabled"] = false
	GameState.apply_mission(m)
	AudioManager.announcement_started.connect(func(n: String, l: String) -> void: started.append([n, l]))
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	train = main.get_node("Train")
	main.get_node("MissionBrief").visible = false
	main.get_node("MissionBrief").accepted.emit()
	_run()

func _run() -> void:
	await _wait(0.3)
	print("--- Manifest / dosyalar ---")
	var route := GameState.route
	var missing := []
	for st in route.stations:
		for key in ["next_%s" % st["id"], "arrive_%s_right" % st["id"], "arrive_%s_left" % st["id"], "terminus_%s" % st["id"]]:
			for lang in ["tr", "en"]:
				if not ResourceLoader.exists(AudioManager._announce_path(key, lang)):
					missing.append(key + "/" + lang)
	for key in ["closing", "hold", "delay", "emergency", "welcome_forward", "welcome_reverse"]:
		for lang in ["tr", "en"]:
			if not ResourceLoader.exists(AudioManager._announce_path(key, lang)):
				missing.append(key + "/" + lang)
	_check(missing.is_empty(), "Tüm istasyon/sistem anonsları TR+EN mevcut (eksik: %s)" % str(missing))
	for r in ["radio_departure_ok", "radio_regulation", "radio_spad", "radio_spad_permit", "radio_tsr", "radio_lead_delay", "radio_atp", "radio_ack"]:
		if not ResourceLoader.exists("res://assets/audio/announce/%s.wav" % r):
			missing.append(r)
	_check(missing.is_empty(), "Telsiz ses kalıpları mevcut")
	print("--- Kuyruk ---")
	# Hoş geldiniz anonsu PISSystem tarafından tetiklendi: TR başladı
	_check(started.size() >= 1 and started[0][0] == "welcome_forward" and started[0][1] == "tr", "Hoş geldiniz anonsu TR ile başladı (%s)" % str(started))
	_check(AudioManager.is_announcing(), "Anons çalıyor")
	var q0: int = AudioManager._announce_queue.size()
	AudioManager.announce("welcome_forward")
	_check(AudioManager._announce_queue.size() == q0, "Aynı anons kuyrukta tekrar eklenmedi")
	AudioManager.announce("next_KRT")
	_check(AudioManager._announce_queue.size() == q0 + 2, "Yeni anons TR+EN olarak kuyruğa eklendi (iki dil)")
	var q: Array = AudioManager._announce_queue
	var tr_idx := -1
	var en_idx := -1
	for i in q.size():
		if str(q[i]).ends_with("next_KRT.wav"):
			tr_idx = i
		if str(q[i]).ends_with("next_KRT_en.wav"):
			en_idx = i
	_check(tr_idx >= 0 and en_idx == tr_idx + 1, "Sıralama: TR önce, EN hemen sonra")
	_check(AudioManager.p_announce.playing and AudioManager._announce_queue.size() > 0, "Çalarken ikinci anons başlamadı (üst üste binme yok)")
	# Tek dil
	AudioManager.bilingual = false
	AudioManager.announce("next_YYS")
	var has_en := false
	for pth in AudioManager._announce_queue:
		if str(pth).ends_with("next_YYS_en.wav"):
			has_en = true
	_check(not has_en, "Yalnız TR modunda EN eklenmedi")
	AudioManager.bilingual = true
	# Acil: kuyruk temizlenir, hemen başlar
	AudioManager.announce("closing", true)
	await get_tree().process_frame
	_check(AudioManager.last_announcement == "closing", "Acil anons (kapılar kapanıyor) kuyruğu kesti → %s" % AudioManager.last_announcement)
	print("--- Olay tetikleyicileri ---")
	started.clear()
	train.doors.request_close("right")
	await _wait(0.5)
	var saw_closing := false
	for s in started:
		if s[0] == "closing":
			saw_closing = true
	_check(saw_closing, "Kapı kapanınca kapı anonsu tetiklendi")
	# Yaklaşım anonsu: KRT'ye 300 m kala hareket halinde
	var pis = main.get_node("PIS")
	var mission = main.get_node("Mission")
	await _wait(4.0)
	mission._set_state(MissionManager.State.RUNNING)
	mission.stop_index = 0
	train.offset = float(route.get_station_by_id("KRT")["stop_pos"]) - 300.0
	train.speed = 15.0
	started.clear()
	AudioManager._announce_queue.clear()
	AudioManager.p_announce.stop()
	await _wait(0.6)
	var saw_arrive := false
	for s in started:
		if s[0] == "arrive_KRT_right":
			saw_arrive = true
	_check(saw_arrive or AudioManager.last_announcement == "arrive_KRT_right", "Varış anonsu doğru istasyon + kapı yönü (arrive_KRT_right)")
	train.speed = 0.0
	# Telsiz
	var traffic = main.get_node("Traffic")
	traffic.driver_call()
	_check(AudioManager.p_radio != null and AudioManager.p_radio.playing, "Telsiz PTT sesi çalıyor")
	var before: int = traffic.messages.size()
	traffic.driver_call()
	_check(traffic.messages.size() == before + 1 and AudioManager.p_radio.playing, "İkinci telsiz mesajı yazıldı, ses üst üste binmedi (tek oynatıcı)")
	print("--- Ortam ---")
	var amb = main.get_node("Ambience")
	_check(amb._station_players.size() == route.stations.size() and amb._car_players.size() == 4, "İstasyon (%d) ve vagon (%d) ortam kaynakları" % [amb._station_players.size(), amb._car_players.size()])
	train.offset = float(route.get_station_by_id("KRT")["stop_pos"])
	await _wait(0.8)
	var playing := 0
	for sid in amb._station_players:
		if amb._station_players[sid]["crowd"].playing:
			playing += 1
	_check(playing >= 1 and playing < route.stations.size(), "Yalnızca yakın istasyon kalabalığı çalıyor (%d/%d)" % [playing, route.stations.size()])
	amb.set_zone("saloon")
	_check(AudioManager.zone_gain < 1.0 and amb._lowpass.cutoff_hz < 10000.0, "Vagon bölgesi: sürüş sesleri kısıldı + alçak geçiren")
	amb.set_zone("cab")
	_check(AudioManager.zone_gain == 1.0, "Kabin bölgesi geri")
	print("\n%d kontrol, %d hata" % [checks, failures.size()])
	for f in failures:
		print("  ✗ ", f)
	print("[TEST] " + ("BAŞARILI" if failures.is_empty() else "BAŞARISIZ"))
	get_tree().quit(0 if failures.is_empty() else 1)
