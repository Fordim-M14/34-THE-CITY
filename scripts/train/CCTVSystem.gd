class_name CCTVSystem
extends Node
## CCTVSystem — kabindeki CCTV monitörü. Gerçek oyun sahnesini gösteren kameralar:
##   • Vagon içi kameralar (her vagonda 2, GLB'deki CCTV_Cam_* noktaları)
##   • Kapı/peron kameraları (her vagonun sağ/sol dış yüzünde, kapı hizasında, trenin
##     yanına bakar — peron ve kapı önündeki yolcular görünür)
## Tek SubViewport (384x288) + tek aktif Camera3D; görüntü yalnızca monitör açıkken ve
## ~12 fps ile güncellenir (performans). Kapılar açılınca monitör otomatik olarak doğru
## tarafın kapı kamerasına geçer. Forward+'ta ViewportTexture doğrudan kullanılır;
## Compatibility'de ImageTexture kopyası (MMI ile aynı yöntem).

const W := 384
const H := 288
const FPS := 12.0

var train: TrainController
var visual: TrainVisual
var enabled_monitor: bool = true
var cameras: Array = []        # [{name, node(Node3D), kind, car, side}]
var index: int = 0
var _vp: SubViewport
var _cam: Camera3D
var _overlay: Label
var _timer := 0.0
var _tex: ImageTexture
var _copy_mode := false
var _copy_pending := false
var _frames := 0

func setup(p_train: TrainController) -> void:
	train = p_train
	visual = train.visual
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.positional_shadow_atlas_size = 1024
	_vp.scaling_3d_scale = 1.0
	_vp.own_world_3d = false      # ana dünyayı paylaşır
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 92.0
	_cam.near = 0.1
	_cam.far = 120.0
	_cam.current = true
	_vp.add_child(_cam)
	# Monitör üst yazısı (kamera adı + saat)
	var cl := CanvasLayer.new()
	_vp.add_child(cl)
	var bar := ColorRect.new()
	bar.size = Vector2(W, 22)
	bar.color = Color(0, 0, 0, 0.55)
	cl.add_child(bar)
	_overlay = Label.new()
	_overlay.position = Vector2(6, 2)
	_overlay.add_theme_font_size_override("font_size", 14)
	_overlay.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	cl.add_child(_overlay)
	var rec := Label.new()
	rec.text = "● REC"
	rec.position = Vector2(W - 54, 2)
	rec.add_theme_font_size_override("font_size", 14)
	rec.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	cl.add_child(rec)
	_build_camera_list()
	_copy_mode = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) == "gl_compatibility" or str(RenderingServer.get_video_adapter_api_version()).begins_with("OpenGL") or OS.get_cmdline_args().has("--rendering-method=gl_compatibility")
	if _copy_mode:
		var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.02, 0.02, 0.02))
		_tex = ImageTexture.create_from_image(img)
		RenderingServer.frame_post_draw.connect(_copy_frame)
		visual.attach_cctv(_tex)
	else:
		visual.attach_cctv(_vp.get_texture())
	train.doors.doors_opened.connect(_on_doors_opened)
	_select(0)

func _build_camera_list() -> void:
	# Vagon içi kameralar
	var per_car := {}
	for d in visual.cctv_cam_nodes:
		var n: Node3D = d["node"]
		var ci: int = int(d["car"])
		per_car[ci] = int(per_car.get(ci, 0)) + 1
		var holder := Node3D.new()
		holder.name = "CCTVPose"
		n.add_child(holder)
		# Tavandan aşağı-ileri bakar (vagon boyunca)
		holder.rotation_degrees = Vector3(-38, 0, 0)
		cameras.append({"name": "VAGON %d İÇ %s" % [int(d["car"]) + 1, "A" if int(per_car[ci]) == 1 else "B"], "node": holder, "kind": "saloon", "car": int(d["car"]), "side": ""})
	# Kapı/peron kameraları: her vagonun dış yüzünde, kapı hizasında, araç boyunca bakar
	for i in train.cars.size():
		var car: Node3D = train.cars[i]
		for side in ["left", "right"]:
			var sx := -1.0 if side == "left" else 1.0
			var holder := Node3D.new()
			holder.name = "CCTVDoorCam_" + side
			# Araç yerel: x sağ, y yukarı, -z ileri. Kamera gövde yanında, çatı altı; geriye-aşağı bakar
			holder.position = Vector3(sx * 1.55, TrainVisual.ROOF_Y - 0.25, -9.0)
			holder.rotation_degrees = Vector3(-22, 180 + sx * 28, 0)
			car.add_child(holder)
			cameras.append({"name": "VAGON %d KAPI %s" % [i + 1, "SOL" if side == "left" else "SAĞ"], "node": holder, "kind": "door", "car": i, "side": side})
			# Küçük kamera gövdesi (dış)
			var body := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.08, 0.16)
			body.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.15, 0.16)
			mat.metallic = 0.6
			mat.roughness = 0.4
			body.material_override = mat
			holder.add_child(body)

func camera_count() -> int:
	return cameras.size()

func current_name() -> String:
	if cameras.is_empty():
		return ""
	return str(cameras[index]["name"])

func _select(i: int) -> void:
	if cameras.is_empty():
		return
	index = posmod(i, cameras.size())
	_sync_camera()
	_overlay.text = "KAM %02d  %s" % [index + 1, current_name()]
	_timer = 0.0

## Kamera SubViewport içinde kalır (viewport'a ait olması gerekir); konumu tutucudan kopyalanır
func _sync_camera() -> void:
	if cameras.is_empty():
		return
	var holder: Node3D = cameras[index]["node"]
	if holder and holder.is_inside_tree():
		_cam.global_transform = holder.global_transform

func next_camera() -> void:
	_select(index + 1)
	if not enabled_monitor:
		toggle()

func select_door_side(side: String) -> void:
	for i in cameras.size():
		if cameras[i]["kind"] == "door" and cameras[i]["side"] == side and int(cameras[i]["car"]) == 0:
			_select(i)
			return

func toggle() -> void:
	enabled_monitor = not enabled_monitor
	if enabled_monitor:
		visual.attach_cctv(_tex if _copy_mode else _vp.get_texture())
	else:
		visual.attach_cctv(null)
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Scoring.log_event("CCTV monitör %s" % ("AÇIK" if enabled_monitor else "KAPALI"))

func _on_doors_opened(side: String, _st: Dictionary, _correct: bool) -> void:
	select_door_side(side)

func _process(delta: float) -> void:
	if not enabled_monitor or GameState.paused or _cam == null or GameState.walking:
		return   # yürürken monitör görünmez → render yok
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / FPS
	if _vp.world_3d == null and is_inside_tree():
		_vp.world_3d = get_viewport().world_3d
	_overlay.text = "KAM %02d  %s   %s" % [index + 1, current_name(), GameState.clock_text()]
	_sync_camera()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_copy_pending = true

func _copy_frame() -> void:
	if not _copy_pending or _vp == null:
		return
	_copy_pending = false
	var img := _vp.get_texture().get_image()
	if img and img.get_size() == Vector2i(W, H):
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		_tex.update(img)
