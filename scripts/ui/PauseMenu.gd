extends CanvasLayer
## PauseMenu — oyun içi ESC menüsü: devam, ayarlar, seferi yeniden başlat, ana menü, çıkış.
## Duraklatma: get_tree().paused + GameState.paused (süre sayaçları durur).

signal resumed

var _root: Control
var _panel: Control
var _settings: SettingsMenu

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.theme()
	add_child(_root)

func open() -> void:
	var m := get_tree().current_scene
	if m and m.has_node("Train"):
		SaveGame.save_from_main(m)
	if visible:
		return
	visible = true
	GameState.paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main()

func resume() -> void:
	visible = false
	GameState.paused = false
	get_tree().paused = false
	if _panel:
		_panel.queue_free()
		_panel = null
	resumed.emit()

func _clear() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_panel)

func _show_main() -> void:
	_clear()
	UITheme.dim(_panel, 0.65)
	var vb := UITheme.card(_panel, 520)
	vb.add_child(UITheme.title("Duraklatıldı", 32))
	vb.add_child(UITheme.label("Sefer %s · %s · Puan %d" % [str(GameState.mission.get("service_number", "")), GameState.clock_text(), Scoring.total_score()], 15, UITheme.MUTED))
	vb.add_child(UITheme.button("Devam et  (Esc)", resume))
	vb.add_child(UITheme.button("Ayarlar", _show_settings))
	if GameState.is_free_mode():
		vb.add_child(UITheme.button("Seferi bitir (serbest sürüş)", func() -> void:
			resume()
			var m := get_tree().current_scene
			if m and m.has_node("Mission"):
				m.get_node("Mission").end_free_drive()))
	vb.add_child(UITheme.button("Seferi yeniden başlat", func() -> void:
		resume()
		get_tree().reload_current_scene()))
	vb.add_child(UITheme.button("Ana menüye dön", func() -> void:
		resume()
		AudioManager.detach()
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")))
	vb.add_child(UITheme.button("Oyundan çık", func() -> void: get_tree().quit()))

func _show_settings() -> void:
	_clear()
	UITheme.dim(_panel, 0.65)
	var sm := SettingsMenu.new()
	sm.process_mode = Node.PROCESS_MODE_ALWAYS
	sm.closed.connect(_show_main)
	_panel.add_child(sm)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause") and _panel and _panel.get_child_count() > 0 and not (_panel.get_child(_panel.get_child_count() - 1) is SettingsMenu):
		resume()
		get_viewport().set_input_as_handled()
