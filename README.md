# M4 Vardiya — v0.4.1 (REALISM, PASSENGERS & POLISH)

Birinci şahıs İstanbul metro makinist simülasyonu · Godot 4.3+ · Windows
Kurgusal işletme: **ARS – Anadolu Raylı Sistemler İşletmesi** · Tren: **ARS T-400 "Boğaz"**
İstanbul M4 hattından esinlenilmiştir; resmî bir Metro İstanbul ürünü değildir.

## Çalıştırma

**A) Hazır Windows sürümü:** `build/M4Vardiya.exe` dosyasını çift tıklayın (kurulum gerekmez;
oyun verisi exe içine gömülüdür). İlk açılışta Windows SmartScreen uyarısı çıkarsa
"Daha fazla bilgi → Yine de çalıştır".

**B) Godot editöründen:** Godot 4.3+ (standart, .NET'siz) → Import → `project.godot` → F5.

3B modeller (`assets/models/*.glb`) ve PBR dokular (`assets/textures/*.png`) `tools/` altındaki
Blender betikleriyle üretilir (harici varlık yok). Yeniden üretmek için (Blender 4.0 + numpy):
`blender -b --python tools/bake_textures.py`, `tools/build_train.py`, `tools/build_env.py`,
`tools/build_passenger.py` (kabin: `tools/build_cabin.py`, salon: `tools/build_saloon.py`). Gerçekçi yolcular
`tools/build_passenger_mh.py` ile MakeHuman'ın **CC0** veri dosyalarından üretilir (`--mh <makehuman/data>`,
depo: github.com/makehumancommunity/makehuman; lisans `docs/LICENSE_MAKEHUMAN_ASSETS_CC0.md`). Ortam sesleri
`tools/make_ambience.py`.
Anonslar `tools/make_announcements.py` ile üretilir: Türkçe MBROLA tr2 (kadın) + İngilizce Piper/LibriTTS
(CC BY 4.0) + hoparlör filtresi; merkez telsizi MBROLA tr1 (erkek) + telsiz filtresi. Tüm sesler çevrimdışı
üretilmiş WAV dosyalarıdır; ticari kullanıma uygun lisanslar (bkz. CHANGELOG lisans notu).

**Grafik:** Forward+ renderer (Vulkan; yoksa OpenGL3'e düşer). Ayarlar → Görüntü'de Düşük/Orta/
Yüksek/Ultra ön ayarları ve tek tek seçenekler. Ayarlar → Kamera'da FOV, koltuk yüksekliği/ileri,
sallanma. Yakınlaştırma: sağ fare tuşu veya Z; bakışı ortala: C.

## Kontroller

| Tuş | İşlev |
|---|---|
| **W / S** | Kol ileri (çekiş) / geri (fren), kademeli |
| **N** | Kol nötr |
| **Space** | **Acil fren** (manuel) |
| **Shift + R** | **Acil fren sıfırlama** — yalnızca tren durmuş + kol nötr + güvenlik şartları sağlanmışsa |
| **F** | Onay: merkez mesajı / sinyal ihlali onayı / arıza prosedürü adımı |
| **E / Q** | Sağ / sol kapılar |
| **R** | Yön kolu (İLERİ → NÖTR → GERİ), sadece duruşta |
| **L / K** | Farlar / kabin ışığı |
| **H** | Korna |
| **Tab** | MMI ekran sayfası (Sürüş · Arıza · Merkez · Sefer) |
| **Fare** | Bakış; **sol tık** kabindeki düğme/kola basar; **tekerlek** kol üzerindeyken kademe |
| **X** | **Koltuktan kalk / otur** — tren durmuş, kol nötr, acil fren yokken; yürüme modunda WASD + Shift, kabin kapısı / boş yolcu koltuğu / ekran-harita-acil ekipman incelemesi için tık/E, koltuktan kalk X/E |
| **F3** | FPS sayacı (anlık/ortalama FPS, kare süresi, kalite, çözünürlük) |
| **Kabin düğmeleri** | CCTV aç/kapat, KAM ► (kamera değiştir), ANONS (manuel anons), PTT (telsizle merkezi ara), şalterler: FAR UZUN / SİLECEK / FAN / TR-EN, parlaklık potansiyometresi (tekerlek) |
| **M** | Fareyi serbest bırak / yakala |

**Kolay kontrol modu** (Ayarlar → Tuşlar → Sürüş kontrol modu): W basılı hızlan, S basılı fren, E peron
kapıları, hız limiti otomatik korunur. **Serbest sürüş** (Seviye 3): zaman baskısı/kariyer cezası yok,
istenen yönde sürüş, Esc → "Seferi bitir".

**Otomatik kayıt:** sürüşte her 20 sn, duraklatmada ve pencere kapatılırken `user://autosave.json`
yazılır; ana menüde "Kaldığın yerden devam et". Bozuk kayıt yok sayılır.
| **Esc** | Duraklatma menüsü (devam, ayarlar, yeniden başlat, ana menü) |
| **F5** | Seferi yeniden başlat |

Tuşlar Ayarlar → Tuş atamaları bölümünden değiştirilebilir (Shift+R ve fare sabittir).

## Acil fren modeli (v2)

Nedenler ayrı ayrı yönetilir: **MANUEL** (Space), **ATP** (limit +10 km/s), **SİNYAL İHLALİ**
(kırmızı sinyal geçildi), **ARIZA**. Biri aktifken çekiş uygulanamaz. Sıfırlama şartları HUD'da
ve MMI'da anlık gösterilir:
- her durumda: tren tamamen durmuş ve kol NÖTR;
- ATP: hız ihlali ortadan kalkmış;
- Sinyal ihlali: F ile onay → merkez ~12 sn sonra izin verir → Shift+R;
- Arıza: ilgili arıza giderilmiş.

## Sefer akışı

Görev ekranı → yolcu alımı (kapılar açık) → kapıları kapat → kalkış izni / sinyal yeşil →
sür → her istasyonda DUR 4 hizasında dur (±0,5 m) → kapıları doğru tarafta aç → yolcu
iniş/binişi (süre yolcu sayısına göre uzar) → kapat → kalkış izni → … → son istasyon → rapor.

Hat 4 (6 istasyon, 8,4 km): Sabiha Gökçen Havalimanı · Kurtköy · Yayalar-Şeyhli (açık kesim)
· Fevzi Çakmak-Hastane · Tavşantepe · Pendik. Gidiş ve dönüş yönü desteklenir.

## Sistemler

- **Trafik ve sinyalizasyon:** öndeki sefer basit fizikle simüle edilir ve 3B modeliyle hatta
  görünür; blok sinyalleri onun konumundan türetilir (kırmızı/sarı/yeşil). Hat **çift hatlıdır**:
  karşı yön hattında 3 sefer (karşı peronda durur, hızlanır/frenler, LOD). Merkez telsiz
  mesajları sesli + yazılı; PTT ile merkez aranır. Regülasyon beklemesi ve geçici hız kısıtlaması.
- **CCTV:** 16 kamera (8 vagon içi, 8 kapı/peron), kabin monitöründe; kapı açılınca otomatik kapı
  kamerası. **Gezilebilir tren içi:** X ile koltuktan kalkıp 4 vagonu dolaşma (CharacterBody3D).
- **PIS / anonslar:** tren içi 24 LED ekran + hat haritası + reklam panoları, istasyon PIS ekranları
  (gerçek tahmini varış, sefer no, gecikme uyarısı); TR + EN anonslar (kuyruk, kapıyla senkron).
- **Arızalar (8):** kapı arızası, fren uyarısı, katener kesintisi, sinyal arızası, çekiş motoru,
  MMI ekranı, yolcu kaynaklı gecikme, imdat alarmı. Her birinin prosedürü MMI "ARIZA" sayfasında;
  prosedür uygulanmazsa ceza.
- **Yolcular:** peronda bekleme (bir kısmı telefona bakar), kapıya yönelme, iniş/biniş, çıkışa
  yürüme, kapı sıkışması; tren içinde doluluğa göre oturan / direğe tutunan / telefona bakan
  görünür yolcular; yüz, saç, ceket, çanta varyantları; saate göre yoğunluk.
- **Kabin:** tıklanabilir kol, yön kolu, kapı aç/kapat düğmeleri, far, kabin ışığı, korna, onay,
  acil fren mantarı, acil reset; analog hız saati; MMI ekranı (4 sayfa); ikaz lambaları.
- **Ses:** prosedürel çekiş vınlaması (hızla değişir), ray/tekerlek, ray eki, fren hışırtı ve
  gıcırtısı, kapı ikazı/motoru, korna, ATP uyarısı, acil alarm, merkez tonu; Türkçe anonslar;
  tünel/istasyon/açık kesim yankısı.
- **Kariyer:** profil, XP/seviye/rütbe, sanal maaş, kilitler (dönüş sv.2, serbest sürüş ve gece
  sv.3, zirve saat sv.4), günlük/haftalık görevler, 12 başarım, istatistikler, otomatik kayıt
  (`user://career.json`).
- **Menüler:** ana menü (3B arka plan), vardiya seçimi (yön, saat, seçenekler), görevler,
  ayarlar (çözünürlük, tam ekran, kalite, sesler, fare, tuş atama), duraklatma.

## Testler

```bash
godot --headless --path . res://tests/EmergencyBrakeTest.tscn   # acil fren (19 kontrol)
godot --headless --path . res://tests/UnitTests.tscn            # rota/sinyal/dönüş/puan/kariyer (37)
godot --headless --path . res://tests/AutoDriveTest.tscn -- --seed 99 [--reverse] [--no-faults]
godot --headless --path . res://tests/SystemsTest.tscn          # v0.4 sistemleri: model, CCTV, yürüme, kayıt (46)
godot --headless --path . res://tests/WalkthroughRegressionTest.tscn   # gerçek yürüyüşle 4 vagon geçişi (46)
godot --headless --path . res://tests/ControlsRegressionTest.tscn      # kolay/gerçekçi/serbest sürüş, titreşim, ayarlar (20)
godot --headless --path . res://tests/AudioRegressionTest.tscn         # anons kuyruğu TR/EN, telsiz, ortam (18)
godot --headless --path . res://tests/SaveRegressionTest.tscn          # otomatik kayıt / devam / kariyer (17)
xvfb-run godot --path . --rendering-driver vulkan res://tests/ShotV41.tscn  # v0.4.1 ekran görüntüleri
xvfb-run godot --path . --rendering-driver vulkan res://tests/ShotV4.tscn   # v0.4 ekran görüntüleri (user://shots)
```

## Rota verisi

`data/routes/hat4.json`: istasyonlar (konum, peron, kapı tarafı, stil, tarife), hız limitleri,
segmentler (tünel/açık), sinyal kuralları, hat eğrisi (Bezier, yükseklik dahil). Yeni hat için
aynı yapıda ikinci bir JSON eklemek ve `GameState.DEFAULT_ROUTE`'u/menüyü genişletmek yeterlidir.

Bkz. `CHANGELOG.md` (neyin bitip neyin eksik olduğu) ve `PLAN.md`.
