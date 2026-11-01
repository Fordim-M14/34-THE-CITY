# M4 VARDİYA — Claude Code proje hafızası

Bu dosya her oturumda otomatik okunur. Ayrıntılı durum için `docs/HANDOFF.md`, geçmiş için
`CHANGELOG.md`, test durumu için `TEST_REPORT.md`, gelecek iş için `docs/spec/v0.5_*.md`.

## Proje nedir
- Godot **4.3 stable** (GDScript, Forward+/Vulkan), Windows x86_64. Sürüm: **v0.4.1** (project.godot `config/version`).
- Birinci şahıs İstanbul metro makinist simülatörü. Kurgusal işletme **ARS**, tren **ARS T-400 "Boğaz"**
  (4 araç, 88 m), **Hat 4 — Havalimanı Hattı** (M4'ten esinlenir; resmî Metro İstanbul kimliği kullanılmaz).
- Hedef: ücretli Steam sürümü. Hedef donanım i7-12650H + RTX 4070 Laptop, 1080p 60 FPS (ölçülmedi).
- Dil: oyun içi ve dokümanlar **Türkçe**; kod yorumları Türkçe; sınıf/değişken adları İngilizce.

## Kesin kurallar (kullanıcının şartı)
1. **"Tamamlandı" yalnız gerçekten çalışıyor ve test edilmişse denir.** Ölçülmemiş FPS, test edilmemiş
   özellik, çalıştırılmamış test raporlanmaz. Her özellik için durum: tamamlandı / sınırlı / yapılmadı.
2. Mevcut sistemleri bozma: sürüş, ATP/sinyal, acil fren, kapılar, MMI, CCTV, anons, vagon geçişi, kayıt.
3. Hata çözümünde tahmin yok: kök nedeni bul, test ile kanıtla, kalıcı düzelt.
4. Lisansı belirsiz model/ses/doku/logo ekleme. Kullanılan dış varlıklar: MakeHuman verisi (CC0,
   `docs/LICENSE_MAKEHUMAN_ASSETS_CC0.md`), Piper LibriTTS EN sesi (CC BY 4.0, `docs/LICENSE_LIBRITTS_VOICE.md`),
   MBROLA tr1/tr2 + espeak-ng (TR anons). Ticari lisanslı Türkçe nöral ses **bulunamadı** (NC lisanslar).
5. Primitif kutu/silindirle "model" yapıp geçme; modeller Blender betikleriyle (`tools/`) üretilir.
6. Her aşama sonunda testler **gerçekten çalıştırılır**; rapora çıktılar yazılır.
7. Dosya değişikliklerini `CHANGELOG.md`'ye dosya bazında yaz; ilerlemeyi `DEVELOPMENT_PROGRESS.md`'de tut
   (v0.5'ten itibaren; durumlar: TAMAMLANDI / KISMEN / BAŞLANMADI / ENGELLENDİ, TEST EDİLDİ / EDİLEMEDİ).

## Klasörler
- `scripts/autoload/` GameState, Scoring, AudioManager, Career, Settings, SaveGame, PerfOverlay(Perf) — autoload sırası project.godot'ta.
- `scripts/main/` Main, MissionManager, TrafficManager (AI trenler + OCC telsiz), PassengerManager, PISSystem, AmbienceManager, FaultManager.
- `scripts/train/` TrainController (fizik/ATP), TrainVisual (GLB kurulum, çarpışma, kabin kontrolleri), TrainDoors, CabinCamera, CabinInteraction, PlayerWalker (yürüme modu), CCTVSystem, MMIScreen, OtherTrain, RouteMapFactory.
- `scripts/world/` TrackBuilder (çift hat), StationBuilder, RouteData, MaterialLib, TextureFactory, MeshUtil, TrackSignal.
- `scripts/ui/` HUD, MainMenu, PauseMenu, SettingsMenu, MissionBrief, ScoreScreen, UITheme.
- `scenes/main/Main.tscn` oyun; `scenes/ui/*`. `data/routes/hat4_sgh_kurtkoy.json` rota (6 istasyon, 8,4 km).
- `assets/models/` t400_front.glb, t400_mid.glb (tren), passenger_*.glb (6 MakeHuman varyantı), passenger.glb (eski yedek), `props/*.glb`.
- `assets/textures/` Blender'da pişirilmiş PBR setleri (`*_albedo/_normal/_rough.png`). `assets/audio/announce/` (manifest.json), `assets/audio/ambience/`.
- `tools/` Blender 4.0 headless betikleri: build_train.py (build_cabin/build_saloon'u içe alır), build_env.py (prop'lar),
  build_passenger_mh.py (MakeHuman), bake_textures.py, make_announcements.py, make_ambience.py, import_voice_pack.py.
- `tests/` headless regresyon testleri + ekran görüntüsü sahneleri. `shots/` gerçek oyun içi görüntüler.

## Komutlar
```
# Testler (headless, hepsi "[TEST] BAŞARILI" ile bitmeli)
godot --headless --path . res://tests/UnitTests.tscn                 # 37
godot --headless --path . res://tests/EmergencyBrakeTest.tscn        # 19
godot --headless --path . res://tests/SystemsTest.tscn               # 46
godot --headless --path . res://tests/WalkthroughRegressionTest.tscn # 61 (gerçek yürüyüş, hata enjeksiyonu)
godot --headless --path . res://tests/ControlsRegressionTest.tscn    # 20
godot --headless --path . res://tests/AudioRegressionTest.tscn       # 18
godot --headless --path . res://tests/SaveRegressionTest.tscn        # 17
godot --headless --path . res://tests/AutoDriveTest.tscn -- --seed 4243 [--reverse]
# Ekran görüntüleri (GPU ile normal pencere; Linux'ta xvfb + lavapipe ile de çalışır)
godot --path . --rendering-driver vulkan res://tests/ShotV41.tscn [-- --only station|pis]
# Modeller (Blender 4.0.x)
blender -b --python tools/build_train.py -- --out assets/models
blender -b --python tools/build_passenger_mh.py -- --mh <makehuman/data> --out assets/models
# Windows export (resmî 4.3 export şablonları kurulu olmalı)
godot --headless --path . --export-release "Windows Desktop" ../build/M4Vardiya.exe
```
- Windows'ta `godot` yerine Godot_v4.3-stable_win64.exe tam yolu. Yeni GLB/PNG eklendiğinde editörü bir kez açıp
  import ettirmek gerekir (`godot --headless --path . --import` da olur).
- Test çıktılarında "RID allocations leaked" ve ObjectDB uyarıları normaldir (çıkışta), hata değildir.

## Mimari notlar (bilinmesi şart)
- Eksen: Blender +Y ileri/+Z yukarı → Godot −Z ileri/+Y yukarı. Araç yerel: −z kabin/ileri, +z arka; `TrainVisual.FLOOR_Y = 1.1`.
  Araç i'nin yerel z'si = z + i·(CAR_LENGTH 21.5 + CAR_GAP 0.6). Yolcu modeli yerel +Z'ye bakar.
- Çarpışma: `TrainVisual.build_walk_collisions()` yalnız `Static_*`, `_Shell`, `GangPlate`, `Bulkhead_1`, `EndWall`,
  `CabSeat_`, `Glass_`, `Floor` mesh'lerine trimesh üretir; `StaticNC_*` (halkalar, direk kolları, armatür) çarpışmasız.
  `tools/build_train.py::join_static` KEEP/NOCOL önekleriyle gruplar; **tek nesneli gruplar da `Static_` alır** (v0.4 görünmez
  duvarın kök nedeni buydu).
- PlayerWalker: CharacterBody3D kapsül r=0,22 h=1,7; 0,32 m basamak tırmanma (`test_move`), vagon içi zemin emniyeti, floor_snap 0,25.
  Etkileşim: Area3D katman 2, meta `action` ∈ sit / cab_door / seat_sit / inspect.
- Kabin kapısı `CabDoorPivot` (x=0,12), açık −168° (salon duvarına yaslanır). Kabin kamerası `CabinCamera` (yaw ±115°, pitch −55..40).
- Yolcular: PassengerManager; istasyon `PState` (WAITING/SEATED/boarding…), tren içi `onboard_nodes` (koltuk `SeatPos_*` altına
  y −0,93 ofset; ayakta kabin bölgesi hariç z∈[−6,6..8,5]). Animasyon LOD 45 m.
- Anons: `assets/audio/announce/manifest.json` anahtar→dosya; AudioManager kuyruk TR→EN, kopya bastırma; bölge kazancı (kabin/vagon).
- Kayıt: SaveGame JSON `user://`, 20 sn otomatik, bozuk dosya silinir; Career ayrı.
- Ses bölgesi, 3D ortam: AmbienceManager (istasyon 160 m, vagon uğultusu doluluğa göre).
- Diğer trenler: TrafficManager 1 öndeki + 3 karşı yön, karşı hat x=−8 m, LOD 220/900 m.

## Bilinen sınırlar
- GPU'suz ortamda FPS ölçülemedi. Yolcu başına ~12,5k üçgen, 163 kemik; sorun olursa önce yolcu üst sınırı (tren 96 / istasyon 64).
- TR anons sesi diphone (MBROLA); stüdyo/nöral paket `tools/import_voice_pack.py` + `docs/VOICE_PACK.md` ile takılır.
- Yolcu deri/kumaş dokuları düz renk + PBR (fotoğraf dokusu yok).

## Sıradaki iş
`docs/spec/v0.5_istanbulda_yasam.md` + `docs/spec/v0.5_ek_gercek_istanbul.md` (v0.5.0–v0.5.5: dünya saati, 1./3. şahıs,
Sabiha Gökçen dış dünya, gezilebilir istasyon + turnike, yolcu olarak binme, vardiya/personel alanı, ARS Phone, ekonomi,
diyalog, taksi/otobüs, 3 bölge (Kurtköy–Pendik–Kadıköy) OSM tabanlı, turist görevleri, fotoğraf, olaylar, yeni tren,
yolcu AI, grafik, optimizasyon, testler A–M). **Kullanıcı "yap" demeden başlanmaz.** Başlamadan önce: projeyi yedekle,
`DEVELOPMENT_PROGRESS.md` oluştur, OSM/Overpass erişimini dene, Kadıköy uzatması vs bölge geçişi kararını kullanıcıya sor.
