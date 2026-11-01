# M4 VARDİYA — Devir teslim notu (claude.ai → VS Code / Claude Code)

Tarih: 2026-11-01 · Sürüm: **v0.4.1** (düzeltme turu dahil) · Önceki geliştirme ortamı: Linux konteyner
(GPU yok, Godot 4.3 stable, Blender 4.0.2, Python 3 + Pillow/scipy/numpy, espeak-ng + MBROLA, Piper).

Bu dosya, proje geçmişini bilmeyen bir Claude Code oturumunun kaldığı yerden devam edebilmesi için yazıldı.
Kısa hafıza `CLAUDE.md`'de; burada ayrıntı var.

---

## 1. Sürüm geçmişi (özet)

| Sürüm | İçerik |
|---|---|
| v0.1 | Prosedürel tünel/istasyon, tren fiziği, ATP, sinyaller, HUD, görev, puanlama |
| v0.2 | Acil fren (Shift+R sıfırlama + merkez izni), 8 arıza tipi, kariyer, uzun hat, dinamik olaylar, etkileşimli kabin |
| v0.3 / v0.3.1 | Blender tren modeli (GLB), kabin v3, istasyon prop'ları, PBR dokular, grafik ön ayarları, kullanıcı geri bildirimi düzeltmeleri |
| v0.4 | Kabin v4, salon v4, CCTV (16 kamera, SubViewport), yürünebilir tren (PlayerWalker), TR/EN anons, PIS ekranları, karşı yön trenleri (çift hat), yolcu davranışları, OCC telsizi, serbest sürüş, kolay kontrol, kamera titreşimi, istasyon çeşitliliği, sefer özeti, otomatik kayıt |
| v0.4.1 | Görünmez duvar kök neden + kalıcı çözüm, MakeHuman (CC0) yolcular, anons altyapısı (manifest/voice pack), yeni malzemeler, 3D ortam sesleri + ses bölgesi, kabin↔vagon geçişi, FPS sayacı (F3) + LOD, 4 yeni regresyon testi, istasyon atmosferi, vagon içi etkileşimler |
| v0.4.1 düzeltme | Kabine yolcu konması, LED yazısı taşması, basamak tırmanma + zemin emniyeti, düz çizgi/hata enjeksiyonu testleri |

Ayrıntılar: `CHANGELOG.md` (dosya bazında), `TEST_REPORT.md`, `docs/TEST_REPORT_v0.4.md`.

## 2. Test durumu (son çalıştırma 2026-11-01, hepsi BAŞARILI)

UnitTests 37 · EmergencyBrake 19 · Systems 46 · WalkthroughRegression 61 · ControlsRegression 20 ·
AudioRegression 18 · SaveRegression 17 → **218 kontrol**; AutoDrive gidiş 90/100 (A), dönüş 83/100 (B).
Ekran görüntüleri: `shots/v41_01..v41_12*.png` (14 kare, Forward+).

Çalıştırılamayan: gerçek GPU FPS ölçümü; Windows'ta EXE'nin çalıştırılması (Linux'ta export edildi,
pakette MakeHuman sahneleri dahil doğrulandı).

## 3. Kullanıcının son geri bildirimi ve durumu

Kullanıcı 4 ekran görüntüsü gönderdi: kabinde dev yolcu, LED yazısı taşması, geri dönüşte görünmez duvar.
Üçü de v0.4.1 düzeltme turunda ele alındı (CHANGELOG en üst bölüm). Görüntülerdeki yolcu **eski
prosedürel modeldi** → büyük ihtimalle v0.4 EXE'si çalışıyordu. Kullanıcıdan yeni EXE'yi boş klasörde
denemesi istendi; **sonuç henüz gelmedi**. İlk oturumda sorulacak.

Sürüm kontrolü: ana menü alt satırı "v0.4.1"; oyunda F3 FPS sayacı (v0.4'te yok).

## 4. Kritik teknik bilgiler

### Görünmez duvar (tarihçe, bir daha olmasın diye)
- v0.4: `tools/build_train.py::join_static` tek nesneli malzeme gruplarını atlıyor, `Static_` öneki vermiyordu.
  Orta vagonların zemini tek nesneydi → `Static_` yok → Godot çarpışma üretmedi → oyuncu 16 cm altta alt şasede
  yürüdü, geçiş plakası basamağını çıkamadı. 1. vagonda zemin iki parça olduğu için orada sorun yoktu.
- Çözüm 1: tek nesneler `Static_<mat>_<ad>`; Godot `Floor` adını da kabul eder.
- Çözüm 2 (düzeltme turu): PlayerWalker basamak tırmanma (0,32 m, `test_move`) + vagon içi zemin emniyeti.
- Test: `WalkthroughRegressionTest` — gerçek yürüyüş Kabin→V4→Kabin; 4 hizada düz çizgi; **hata enjeksiyonu**
  (2. vagon zemin çarpışması kapatılıp geçiş). Yeni tren modeli üretildiğinde bu test mutlaka tekrar koşulur.

### Model üretim hattı
- `blender -b --python tools/build_train.py -- --out assets/models` → t400_front.glb (kabinli ön araç), t400_mid.glb.
  Kabin `tools/build_cabin.py`, salon `tools/build_saloon.py`. Malzeme adları `scripts/world/MaterialLib.gd` `BY_NAME`
  ile PBR setlerine eşlenir. Önekler: `KEEP_` (ayrı kalır), `NOCOL_`→`StaticNC_` (çarpışmasız), diğerleri
  malzeme başına `Static_` olarak birleştirilir. Etkileşim düğümleri (`Ctl_*`, `Sw_*`, `Knob_*`, `Lever`, `Cam_Eye`,
  `SeatPos_*`, `PIS_*`, `RouteMap_*`, `CCTV_*`, `DoorL_*/DoorR_*`, `CabDoorPivot`) `TrainVisual._setup_*` tarafından bulunur.
- Yolcular: `tools/build_passenger_mh.py` MakeHuman CC0 verisi gerektirir
  (`git clone https://github.com/makehumancommunity/makehuman`, veri `makehuman/data`). 6 varyant, 6 animasyon
  (idle, walk, sit, sit_phone, stand_phone, stand_hold). Dekimasyon 0,18.
- Prop'lar: `tools/build_env.py` (bench, pis_screen, escalator, elevator, signal_head, tunnel_segment …).
- Dokular: `tools/bake_textures.py` (Cycles, 1024², albedo/normal/rough).

### Ses
- TR anons: espeak-ng + MBROLA tr2 (mb-tr2), telsiz tr1; EN: Piper libritts spk 12 (CC BY 4.0).
  `tools/make_announcements.py` → `assets/audio/announce/*.wav` + `manifest.json` (anahtar, dosya, metinler).
  RMS eşitleme −19 dBFS, hoparlör filtresi, çan. `tools/import_voice_pack.py` stüdyo/nöral kaydı manifestle eşler.
- Ortam: `tools/make_ambience.py` prosedürel (lisanssız).
- Ticari lisanslı Türkçe nöral ses **yok** (Piper tr NC, MMS NC, XTTS CPML). Kullanıcı stüdyo kaydı/Azure vb.
  sağlarsa `docs/VOICE_PACK.md` ile takılır.

### Oyun akışı
- Main.tscn: World (TrackBuilder + StationBuilder'lar) + Train (TrainController → TrainVisual → Car0..3) + Passengers +
  Traffic + PIS + Ambience + Faults + UI (HUD, MissionBrief, PauseMenu, ScoreScreen) + CCTV.
- Kontroller: W/S kol, N nötr, Space acil, Shift+R sıfırlama, Q/E kapı, R yön, F onay, L far, K ışık, H korna,
  X kalk/otur, Tab MMI, M fare, F3 FPS, Esc menü. Yürüme: WASD, Shift koşu, tık/E etkileşim.
- Kolay mod: `TrainController._read_input_easy` (450 m ileriye bakan limit yardımcısı). Serbest sürüş: MissionManager
  (ceza yok, `end_free_drive`).
- Kayıt: `user://save.json` (Windows: `%APPDATA%\Godot\app_userdata\M4 Vardiya\`), ekran görüntüleri `shots/` aynı yerde.

## 5. Ortam kurulumu (Windows, VS Code)
1. Godot 4.3 stable (editor) + **export templates 4.3 stable** (Editor → Manage Export Templates).
2. Blender 4.0.x (PATH'te `blender`), Python 3.11+ (`pip install pillow numpy scipy`), isteğe bağlı espeak-ng + MBROLA
   (anons yeniden üretimi için; mevcut WAV'lar projede, yeniden üretmek şart değil).
3. Projeyi editörde bir kez aç (import) veya `godot --headless --path . --import`.
4. Testleri `CLAUDE.md`'deki komutlarla koş; hepsi `[TEST] BAŞARILI` demeli.

## 6. Sıradaki iş: v0.5 "İstanbul'da Yaşam"
Şartname: `docs/spec/v0.5_istanbulda_yasam.md` (v0.5.0–v0.5.5) + `docs/spec/v0.5_ek_gercek_istanbul.md`
(OSM tabanlı gerçek yol ağı, gerçek yapılar, Türkiye atmosferi, GTA tarzı keşif).
Kullanıcı "yap" demeden başlanmaz. Başlangıçta:
1. Yedek al (`backups/m4_vardiya_v0.4.1_proje.zip` eşleniği).
2. `DEVELOPMENT_PROGRESS.md` oluştur (özellik × durum tablosu).
3. OSM erişimini dene (Overpass API); yoksa kullanıcıdan Kurtköy–Pendik–Kadıköy `.osm` çıktısı iste. ODbL atıfı ekle.
4. Çekirdek sırası: GameClock (5× oyun zamanı) → WorldManager (para, kart, telefon, görev, konum) → 3. şahıs kamera →
   Sabiha Gökçen dış dünya + gezilebilir istasyon + turnike → yolcu olarak binme (mevcut trenle paylaşım; en riskli
   entegrasyon, erken yap) → vardiya/personel alanı → ARS Phone → ekonomi/diyalog → taksi/otobüs → bölgeler → …
5. Kadıköy'e M4 uzatması vs bölge geçişi: analiz yapıp kullanıcıya sor.
6. Her aşama sonunda mevcut 7 test + yeni testler koşulur; `TEST_REPORT_v0.5.md`, `CHANGELOG_v0.5.md`.
