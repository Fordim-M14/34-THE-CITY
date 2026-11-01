# TEST_REPORT — M4 Vardiya v0.4.1

Ortam: Godot 4.3 stable (headless testler; ekran görüntüleri Forward+/Vulkan **lavapipe yazılım render**,
1600×900), Linux konteyner (**GPU yok**). Blender 4.0.2 (model/doku/karakter üretimi). Tarih: 2026-11-01.
Tüm testler son kod üzerinde bu tarihte **gerçekten çalıştırıldı**; çıktı: `[TEST] BAŞARILI`.
v0.4 raporu: `docs/TEST_REPORT_v0.4.md`.

## 1. Otomatik testler (toplam 218 kontrol + 2 otopilot seferi)

| Test | Kapsam | Sonuç |
|---|---|---|
| `tests/UnitTests.tscn` | Rota, sinyal, puanlama, kariyer, tuş atama, yoğunluk | **37/37 ✅** |
| `tests/EmergencyBrakeTest.tscn` | Manuel/ATP/SPAD acil fren, Shift+R, merkez izni | **19/19 ✅** |
| `tests/SystemsTest.tscn` | Tren modeli düğümleri, CCTV, şalterler, yürüme modu temel, PIS, kayıt | **46/46 ✅** |
| `tests/WalkthroughRegressionTest.tscn` **(yeni, AŞAMA 1)** | Gerçek `CharacterBody3D` + `move_and_slide` ile (ışınlama yok): koltuktan kalkış; **kapalı kabin kapısı geçişi engeller**; açık kapıdan V1'e; V1→V2→V3→V4 ve V4→V3→V2→V1→Kabin dönüşü; her vagonda zemin yüksekliği; yan duvar + kapalı yolcu kapısı dışarı çıkışı engeller; boş koltuğa oturma / kalkma; hat haritası inceleme; **düz çizgi taraması** (4 hiza × ileri/geri, yalnız W); **hata enjeksiyonu** (2. vagon zemin çarpışması kapalıyken ileri + geri geçiş — v0.4 hatasının yeniden üretimi); tren içi yolcu yerleşimi (kabinde 0, hepsi MakeHuman); koltuğa dönüp sürüşe geçme | **61/61 ✅** |
| `tests/ControlsRegressionTest.tscn` **(yeni)** | Kolay mod: W hızlanır, S yavaşlar, bırakınca sabit, limit düşüşünde ATP tetiklenmez (ileri bakışlı sınırlayıcı), 0'da durur; gerçekçi mod kademeler; kapı kontrolü; kamera titreşimi aç/kapat/şiddet/fare; ayarlar kaydet–yükle; serbest sürüş (süre cezası yok, istasyon atlamak bitirmez, "seferi bitir" çalışır, kariyere yazılmaz) | **20/20 ✅** |
| `tests/AudioRegressionTest.tscn` **(yeni)** | Manifest çözümü (tüm anahtarlar dosyaya karşılık geliyor), TR→EN sıra, çift anons bastırma, aynı dosya üst üste çalmaz, telsiz sesi + metin, bölge (kabin/vagon) kazancı ve alçak geçiren, istasyon ortam sesleri 160 m içinde çalar, vagon uğultusu doluluğa göre | **18/18 ✅** |
| `tests/SaveRegressionTest.tscn` **(yeni)** | Otomatik kayıt (20 sn), kapanışta kayıt, bozuk JSON → silinir ve oyun açılır, eksik alanlı kayıt reddi, devam sonrası konum/hız/görev/kapı/puan, serbest sürüş kaydı, kariyer dokunulmaz | **17/17 ✅** |
| `tests/AutoDriveTest.tscn --seed 4243` | Otopilotla tam hat (gidiş) — tüm sistemler açık | **5/5 istasyon, 90/100 (A) ✅** |
| `tests/AutoDriveTest.tscn --seed 98 --reverse` | Tam hat (dönüş) | **5/5 istasyon, 83/100 (B) ✅** |
| `tests/ShotV41.tscn` (Forward+) | 11 gerçek oyun içi ekran görüntüsü | **11/11 üretildi ✅** |

## 2. Görünmez duvar — kök neden ve kanıt

- **Belirti:** v0.4'te V1→V2 geçiliyor, V2→V3 geçilemiyordu.
- **Kök neden:** `tools/build_train.py::join_static` bir malzeme grubunda **tek nesne** kalınca birleştirme
  yapmadan geçiyor, nesneye `Static_` öneki vermiyordu. Orta vagonların zemini ("Floor") tek nesneydi →
  GLB'de `Static_` öneki yok → `TrainVisual.build_walk_collisions()` yalnız `Static_*` mesh'lere çarpışma
  ürettiği için **orta vagonlarda zemin çarpışması yoktu**. Oyuncu zeminin 16 cm altındaki alt şase
  çarpışmasında yürüyor, vagon ucundaki geçiş plakasına basamak gibi çıkamıyordu. 1. vagonda zemin iki
  parça olduğundan (kabin bölme kesimi) birleştirme çalışıyor ve sorun görünmüyordu.
- **Kanıt:** test başına vagon içi zemin yüksekliği ölçümleri (hepsi 0,95–1,30 m bandında; önceden V2'de
  ~0,79 m), 4 vagon ileri–geri yürüyüş 46/46.
- **Çözüm (kalıcı):** tek nesneler de `Static_<malzeme>_<ad>` olarak adlandırılıyor; Godot tarafında ayrıca
  "Floor" adı kabul ediliyor; `floor_snap_length = 0,25`. Trenin çarpışmaları kapatılmadı.
- **İkinci katman (düzeltme turu):** oyuncuda 0,32 m basamak tırmanma + vagon içi zemin emniyeti. Testte 2. vagonun
  zemin çarpışması bilerek kapatılarak v0.4 hatası yeniden üretildi (önlemler kapalı: 4/4 hizada takıldı; açık: 4/4 geçti).
- **Yan bulgular (aynı testle):** kalkış noktası koltuk arkasına sıkışıyordu → koltuk yanına; kabin kapısı
  kabine açılıyordu → koridor hizasına taşındı, salona doğru duvara yaslanır; direk kolları/halkalar baş
  hizasında ve çarpışmalıydı → yükseltildi ve `StaticNC_` (çarpışmasız) grubuna alındı.

## 3. Özellik bazlı durum (v0.4.1 şartnamesi)

| Aşama | İstenen | Doğrulama | Durum |
|---|---|---|---|
| 1 | Görünmez duvar kalıcı çözüm + gerçek yürüyüş testleri | Walkthrough 46/46, bölüm 2 | ✅ |
| 2 | Çok daha gerçekçi yolcular (lisanslı) | MakeHuman CC0 verisi, 6 varyant, gerçek yüz/saç/kıyafet; v41_07 | ✅ (fotogerçekçi değil) |
| 3 | Profesyonel Türkçe anons | Ticari lisanslı nöral TR ses **bulunamadı** (Piper tr NC, MMS NC, XTTS CPML); mevcut ses korundu, **manifest + içe aktarma aracı + RMS eşitleme + hoparlör filtresi** eklendi | 🟡 altyapı ✅ / ses ❌ |
| 4 | Vagon içi grafik | Yeni koltuk kumaşı, panel, plastik, metal setleri; v41_03/06 | ✅ |
| 5 | Yolcu/ortam sesleri 3D, bölgeye bağlı | AudioRegression (ortam, bölge kazancı); prosedürel, lisanssız | ✅ |
| 6 | Doğal kabin↔vagon geçişi | Walkthrough (kapı kapalı engeller/açık geçer), v41_02/04 | ✅ |
| 7 | FPS sayacı + optimizasyon | F3 overlay (v41_11); LOD/anim-durdurma/CCTV durdurma kodda; **RTX 4070 ölçümü yapılamadı** | ✅ sayaç / ❓ ölçüm |
| 8 | Kolay mod / serbest sürüş / titreşim testleri | ControlsRegression 20/20 | ✅ |
| 9 | Canlı istasyonlar | Bank oturma, dolaşma, telefon, kademeli biniş, uğultu; v41_10/10b | ✅ (kalabalık "orta yoğun", 64 üst sınır) |
| 10 | Vagon içi etkileşim | Koltuğa otur/kalk, PIS/harita/acil kol/acil çağrı inceleme; Walkthrough + v41_08 | ✅ |
| 11 | Testler korunup yenileri eklendi ve çalıştırıldı | Bölüm 1 | ✅ |
| 12 | 10 gerçek ekran görüntüsü | 11 adet (bölüm 4) | ✅ |
| 13 | Windows build + teslim | `build/M4Vardiya.exe` (export template ile), zip, dokümanlar | ✅ (Windows'ta çalıştırma burada test edilemedi) |

## 4. Ekran görüntüleri (Forward+, 1600×900, `shots/`)

1. `v41_01_makinist_kabini` — kabin, ön görüş
2. `v41_02_kabin_kapisi_acik` — kabin kapısı açık, salona bakış (yürüme modu)
3. `v41_03_birinci_vagon` — 1. vagon içi, MakeHuman yolcular oturuyor
4. `v41_04_ikinci_vagona_gecis` — körük geçidinden 2. vagona
5. `v41_05_ucuncu_vagona_gecis` — 2→3 geçiş (eski görünmez duvar noktası)
6. `v41_06_dorduncu_vagon` — 4. vagon
7. `v41_07_yolcu_yuzu_kiyafet` — yolcu yüzü/kıyafet yakın plan
8. `v41_08_koltukta_oturma` — boş koltuğa oturmuş oyuncu görüşü
9. `v41_09_cctv_ekrani` — kabin CCTV ekranı canlı görüntü
10. `v41_10_yolcu_dolu_istasyon` — Kurtköy peronu, yolcular (bank/dolaşan/binen)
11. `v41_10b_istasyon_yolcular_yakin` — peron yakın plan
12. `v41_11_fps_gostergesi` — FPS sayacı (F3) açık
13. `v41_12_pis_led_yazisi` / `_sol` — uzun LED metninin ekrana sığdırılması (sağ/sol ekran)

Not: yazılım render olduğu için görüntülerdeki FPS 1–7 ortamın değeridir, oyunun değil.

## 5. Yapılamayanlar / sınırlar (açıkça)
- GPU olmadığından hiçbir FPS hedefi **ölçülmedi**; 4070 1080p "Yüksek" için 60+ beklentidir, garanti değildir.
- Türkçe nöral/stüdyo anons sesi lisans nedeniyle eklenemedi (altyapı hazır: `docs/VOICE_PACK.md`).
- Yolcular gerçek anatomi ve kıyafet geometrisine sahip ama deri/kumaş **fotoğraf dokusu yok**; animasyonlar el yapımı.
- Windows EXE bu ortamda çalıştırılamadı (Linux); export resmi 4.3 şablonuyla üretildi.
