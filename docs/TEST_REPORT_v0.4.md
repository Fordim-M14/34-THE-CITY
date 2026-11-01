# TEST_REPORT — M4 Vardiya v0.4

Ortam: Godot 4.3 stable (headless + Forward+/Vulkan lavapipe yazılım render, 1600×900), Linux
konteyner (GPU yok). Blender 4.0.2 (model/doku üretimi). Tarih: 2026-11-01.

## 1. Otomatik testler

| Test | Kapsam | Sonuç |
|---|---|---|
| `tests/UnitTests.tscn` | Rota verisi (6 istasyon, 8,4 km, tamamen tünel), sinyal üretimi, dönüş aynalama, puanlama, kariyer kayıt/yükleme, tuş atama, yoğunluk | **37/37 ✅** |
| `tests/EmergencyBrakeTest.tscn` | Manuel/ATP/SPAD acil fren, Shift+R şartları, onay + merkez izni, tuş haritası | **19/19 ✅** |
| `tests/SystemsTest.tscn` (yeni) | Tren modeli düğümleri (4 araç, 208 koltuk noktası, 8 CCTV noktası, 12/12 kapı çifti, 78 birleştirilmiş statik mesh, 28 etkileşimli kontrol), CCTV (16 kamera, değiştirme, kapı tarafı seçimi, aç/kapat), şalter/parlaklık/telsiz PTT, yürüme modu (kalkış şartı, kamera/kontrol devri, 429 çarpışma gövdesi, kabin kapısı 100°, kapıdan salona yürüme, duvardan geçmeme, geçişten 2. vagona geçme, koltuğa dönüş), PIS (342 Label3D, 24 LED ekran), otomatik kayıt (yazma, doğrulama, açıklama, bozuk kayıt toleransı, kayıttan devam, temizleme) | **46/46 ✅** |
| `tests/AutoDriveTest.tscn --seed 4242` | Otopilotla tam hat (gidiş), arızalar açık, trafik/sinyal/kapı/yolcu/anons/PIS/kayıt sistemleri çalışırken | **5/5 istasyon, 93/100 (A) ✅** |
| `tests/AutoDriveTest.tscn --seed 99 --reverse` | Tam hat (dönüş) | **5/5 istasyon ✅** |
| `tests/ShotV4.tscn` (Forward+) | 18 gerçek oyun içi ekran görüntüsü | **18/18 üretildi ✅** |

## 2. Özellik bazlı doğrulama

| İstenen | Doğrulama | Durum |
|---|---|---|
| Kabin görüşü (ray/sinyal/peron görünür) | v4_01 ekran görüntüsü; Cam_Eye/konsol yükseklikleri v0.3 ile aynı | ✅ |
| Tren fiziği, ATP, sinyaller | EmergencyBrakeTest + AutoDrive | ✅ |
| Kapılar (animasyon, taraf, sıkışma) | DoorChk (kanatlar ±0,66 m), AutoDrive | ✅ |
| Yolcular (biniş/iniş, oturan, telefon) | AutoDrive yolcu sayıları; v4_07/v4_14 görüntüleri | ✅ |
| Diğer trenler (karşı yön + öndeki) | v4_17 (karşı tünelde geçen tren), v4_18 (karşı peron); TrafficManager.nearest_opposing() | ✅ |
| CCTV | SystemsTest; v4_01/v4_03 monitör gerçek salon görüntüsü | ✅ |
| Gezilebilir vagonlar | SystemsTest yürüme bölümü; v4_06/07/08 | ✅ |
| Anonslar TR/EN, çakışmama | AudioManager kuyruğu (tekrar/üst üste engeli); 62 WAV üretildi | ✅ (ses kalitesi notu: CHANGELOG 6) |
| Dijital ekranlar (tren/istasyon) | SystemsTest PIS; v4_07 LED yazısı; istasyon PIS metni PISSystem._refresh_stations | ✅ |
| Kariyer / sefer sonu istatistikleri | UnitTests kariyer; ScoreScreen yeni özet bloğu | ✅ |
| Kayıt/yükleme | SystemsTest (6 kontrol) | ✅ |
| Serbest sürüş / kolay kontrol | Kod yolu (MissionManager.end_free_drive, TrainController._read_input_easy); otomatik test yok | 🟡 manuel test önerilir |
| Kamera titreşimleri + ayar | CabinCamera; Ayarlar → Kamera; otomatik test yok | 🟡 manuel test önerilir |
| FPS hedefi (1080p Yüksek 60+) | **Ölçülemedi** (GPU yok) | ❓ |

## 3. Ekran görüntüleri (Forward+, 1600×900, `shots/`)

1. `v4_01_cabin_forward` — makinist kabini, ön görüş
2. `v4_02_cabin_panel` — konsol yakın plan (kol, hız saati, MMI, lambalar, acil mantar)
3. `v4_03_cabin_cctv_monitor` — CCTV monitörü (canlı salon görüntüsü)
4. `v4_07_walk_saloon` — yürüme modunda yolcu vagonu (oturan/ayakta yolcular)
5. `v4_08_walk_gangway` — vagonlar arası geçiş
6. `v4_10_train_front` — tren dış görünümü (peronda)
7. `v4_14_kurtkoy_boarding` — yolcuların bulunduğu istasyon, biniş
8. `v4_12_tunnel_exterior` — tünel ve raylar (3. ray)
9. `v4_17_opposing_train_exterior` — karşı yönden geçen metro (ikinci tünel)
10. `v4_18_station_twin_track` — çift hatlı istasyon, karşı peron

## 4. Bilinen sorunlar / açık işler
- Test senaryosunda ışınlanma nedeniyle oluşan SPAD durumu ekran görüntüsü için temizleniyor (oyun davranışı değil).
- Headless çalıştırmada dummy renderer "Parameter m is null" uyarıları (Label3D/mesh; v0.3'te de vardı, oyunu etkilemez).
- Karşı peronda bekleyen yolcu yok (yalnızca oyuncu peronunda); karşı trenlerin iç mekânı var ama yolcusuz.
- Kolay mod/serbest sürüş/titreşim ayarı için manuel oyun testi yapılmalı (otomatik testle kapsanmadı).
