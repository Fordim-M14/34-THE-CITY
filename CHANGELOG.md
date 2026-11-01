# CHANGELOG — M4 Vardiya

## v0.4.1 — düzeltme turu (kullanıcı ekran görüntülerinden sonra)

Rapor edilen: kabinde dev boyutlu yolcu, LED yazısının kutudan taşması, vagondan geçip geri dönünce
görünmez duvar.

- **Kabinde yolcu (✅ düzeltildi, test edildi):** `PassengerManager._add_onboard_passenger` ayakta
  duran yolcuyu aracın tüm uzunluğuna (z ±8,5) rastgele koyuyordu; ön araçta bu aralık makinist
  kabinini de kapsıyordu → yolcu kabinde, koltuğun yanında, tutamağa asılı pozda duruyordu (kameraya
  çok yakın olduğu için dev görünüyor). Artık ön araçta z ≥ −6,6, arka araçta z ≤ 6,6 (kabinler
  hariç). Test: 151 yolcu yerleşimi, kabinde 0 (`WalkthroughRegressionTest`).
  Ekran görüntüsündeki figür **eski prosedürel modeldi**: v0.4.1'de tüm tren içi yolcular MakeHuman
  modelidir (testle doğrulandı: 151/151). Eski model yalnız MakeHuman sahneleri yüklenemezse
  kullanılır.
- **LED yazısı taşması (✅):** `TrainVisual._fit_label` — metin genişliği ölçülür, ekran genişliğini
  (0,78 m) aşarsa yazı ölçeklenir. İstasyon PIS ekranları için aynı (`StationBuilder.set_pis`, 0,94 m).
  Ekran görüntüsü: `shots/v41_12_pis_led_yazisi.png` ve `_sol`.
- **Görünmez duvar (geri dönüş) — iki katmanlı kalıcı önlem:**
  1. `PlayerWalker` **basamak tırmanma**: yatay hareket engellenince 0,32 m'ye kadar yukarı adım
     denenir (`test_move`); CharacterBody3D dik eşikleri (geçiş plakası 16 cm) kendiliğinden
     aşamıyordu — "ileri geçip geri dönememe" tam olarak bu basamağın belirtisidir.
  2. **Zemin emniyeti**: oyuncu vagon sınırları içindeyken zeminin 8 cm'den fazla altına inmişse
     (çarpışma boşluğu) zemine geri alınır.
  Doğrulama: `WalkthroughRegressionTest` yeni bölümler — (a) koridorun 4 hizasında yalnız W basılı
  **düz yürüyüş** Kabin→V4 ve V4→V1 (8/8); (b) **hata enjeksiyonu**: 2. vagonun zemin çarpışması
  bilerek kapatılıp (v0.4 hatasının birebir yeniden üretimi: aynı test, önlemler kapalıyken 4 hizada
  da z≈32,4 ileri ve z≈11,8 geri noktalarında **takıldı**) ileri + geri geçiş yapıldı (önlemler açıkken
  4/4 geçti, oyuncu zeminin altına inmedi). Toplam 61/61.
- Not: Gönderilen ekran görüntülerindeki yolcu modeli eski (v0.4) modeldir; aynı belirtiler v0.4'te de
  vardı. v0.4.1 çalıştığının kontrolü: ana menü alt satırı "v0.4.1", oyun içinde **F3** FPS sayacını açar.

## v0.4.1 — REALISM, PASSENGERS & POLISH

Durum: ✅ tamamlandı ve test edildi · 🟡 çalışıyor, sınırlı · ❌ tamamlanamadı

### AŞAMA 1 — Vagonlar arası görünmez duvar — ✅ (kök neden bulundu, kalıcı çözüm, 42 kontrol)
**Kök neden:** `tools/build_train.py::join_static` aynı malzemeden **tek** nesne kalınca onu
birleştirmiyor ve `Static_` öneki vermiyordu. Orta vagonlarda zemin ("Floor") tek nesneydi;
Godot'un `TrainVisual.build_walk_collisions()` işlevi yalnız `Static_*` mesh'lere çarpışma ürettiği için
**orta vagonların zemini çarpışmasızdı**. Oyuncu 2. vagonda 16 cm aşağıdaki alt şase üzerinde
yürüyor, vagon sonunda geçiş plakasına (16 cm basamak) çıkamıyordu → "görünmez duvar". Ön araç
(1. vagon) iki zemin parçasına sahip olduğu için orada birleşme oluyordu; bu yüzden V1→V2 çalışıp
V2→V3 çalışmıyordu. **Çözüm:** tek nesneler de `Static_` öneki alıyor (+ Godot tarafında `Floor`
adı da kabul ediliyor), `floor_snap_length` eklendi.
Aynı testin ortaya çıkardığı ek sorunlar: (a) koltuktan kalkış noktası koltuk arkası–bölme duvarı
arasındaki dar boşluktaydı, fizik oyuncuyu duvardan **salona itiyordu** → kalkış noktası koltuğun
sağ yanına alındı; (b) kabin kapısı kabine doğru açılıp geçidi daraltıyordu → kapı açıklığı koridor
hizasına (x 0,12–0,84 m) taşındı, kapı salona doğru duvara yaslanarak açılıyor (−168°), etkileşim
alanı sabit; (c) üç kollu direk kolları ve tutamak halkaları baş hizasındaydı → kollar 1,95 m'ye,
asılı ince parçalar (halkalar, kollar, armatürler, menfezler) `StaticNC_` grubunda, **çarpışmasız**.
Trenin çarpışması kapatılmadı: duvar, zemin, kapı kanatları, kabin kapısı, koltuk çarpışmaları duruyor.
`tests/WalkthroughRegressionTest.tscn` (gerçek kapsül + `move_and_slide`, ışınlama yok): Kabin→V1→V2→
V3→V4→V3→V2→V1→Kabin, kapalı/açık kabin kapısı, yan duvar, kapalı yolcu kapısı, zemin, koltuğa oturma,
sürüşe dönüş, boş koltuğa oturma/kalkma, hat haritası inceleme — **46/46**.

### AŞAMA 2 — Gerçekçi yolcular — ✅ (CC0 MakeHuman verisi; fotogerçekçi değil, gerçek anatomi)
`tools/build_passenger_mh.py`: GitHub `makehumancommunity/makehuman` deposunun **CC0 1.0** veri
dosyaları (taban mesh 19.158 vertex, makro hedefler, 163 kemikli iskelet + ağırlıklar, gözler) kendi
Blender betiğimizle işlenir (MakeHuman programı/AGPL kodu kullanılmaz). 6 vücut varyantı: genç/yaşlı/
iri erkek, genç/yaşlı/ince kadın (cinsiyet × yaş × etnik köken × kilo hedef karışımı). Gerçek yüz
(göz küresi + iris, kaşlar, dudaklar), kafatası derisinden kısa saç / helper'dan uzun saç, kel
varyantı; gömlek/pantolon/ayakkabı helper yüzeylerinden (kumaş normal map), ceket, sırt ve el
çantası, telefon; dekimasyon %18 → ~12,5k yüzey/karakter. Eski 6 animasyon (idle, walk, sit,
sit_phone, stand_phone, stand_hold) MakeHuman iskeletine taşındı; bükülme işareti üretim sırasında
otomatik doğrulanır. Oyunda: rastgele varyant, tutarlı renk seti, boy/genişlik varyasyonu, hair/
jacket/bag/phone görünürlüğü. Lisans kopyası `docs/LICENSE_MAKEHUMAN_ASSETS_CC0.md`. **Denenip
reddedilen:** MB-Lab (çıktıları AGPL). **Sınır:** deri/kumaş fotoğraf dokusu yok (düz renk + PBR),
animasyonlar el yapımı (motion capture değil).

### AŞAMA 3 — Türkçe anonslar — 🟡 (değiştirme altyapısı ✅, nöral TR ses ❌ lisans)
Ticari lisansı doğrulanmış Türkçe nöral ses bulunamadı: Piper tr_TR-dfki **CC BY-NC-SA**, Meta
MMS-TTS **CC BY-NC**, Coqui XTTS **CPML** (ticari yasak); HuggingFace bu ortamdan erişilemiyor.
Mevcut MBROLA tr2 sesi korundu. Yeni: `assets/audio/announce/manifest.json` (anahtar → dosya +
TR/EN kayıt metinleri), `AudioManager` manifestten çözer, `tools/import_voice_pack.py` (stüdyo veya
Azure/ElevenLabs kayıtlarını dönüştürür, RMS eşitler, hoparlör filtresi + çan ekler, eksikleri
listeler), `docs/VOICE_PACK.md`. Tüm anonslar **RMS eşitlemeli** yeniden üretildi (−19 dBFS).

### AŞAMA 4 — Vagon içi grafikler — ✅
Yeni PBR seti `seat_pattern` (çapraz dokuma + nokta desenli metro koltuk kumaşı), duvar panelleri
`panel_lines`, tutamak plastiği, metal pürüzlülük ayarı; koltuk kabuğu/kumaş, kapı contaları, kapı
mekanizması, körük, PIS/harita/reklam panoları, CCTV kubbeleri v0.4'ten korundu.

### AŞAMA 5 — Yolcu sesleri ve ortam — ✅ (`scripts/main/AmbienceManager.gd`, `tools/make_ambience.py`)
Prosedürel (lisanssız) döngüler: peron kalabalığı (uzak konuşmalar + ayak sesleri + kumaş), hol
tonu, vagon içi uğultu (doluluğa göre), havalandırma. AudioStreamPlayer3D, mesafeyle azalma, yalnız
160 m içindeki istasyonlar çalar (0,5 sn güncelleme). **Dinleyici bölgesi:** kabin → vagon geçişinde
motor/ray/fren kısılır + 6,5 kHz alçak geçiren, anons yakınlaşır.

### AŞAMA 6 — Kabin ↔ vagon geçişi — ✅ (animasyonlu kapı, çarpışma görselle senkron, kamera devri)

### AŞAMA 7 — FPS ve optimizasyon — ✅ (ölçüm ❌ GPU yok)
FPS sayacı (F3 / Ayarlar → Görüntü): anlık + 2 sn ortalama FPS, kare ms, ön ayar, çözünürlük ×
render ölçeği, renderer, çizim çağrısı, üçgen sayısı, GPU adı. Optimizasyon: 45 m'den uzak yolcu
animasyonu durur, yürürken CCTV render durur, diğer trenlerde LOD, statik birleştirme. Görünür yolcu
üst sınırı tren içi 96, istasyon 64. **RTX 4070 ölçümü yapılamadı** (konteynerde GPU yok).

### AŞAMA 8/11 — Testler — ✅ (hepsi gerçekten çalıştırıldı)
Yeni: `ControlsRegressionTest` 20/20 (kolay mod W/S/nötr/limit yardımcısı — testte ortaya çıkan
"limit düşüşünde ATP tetikleme" hatası için 450 m ileriye bakan fren mesafesi eklendi —, kapı
kontrolü, HUD; gerçekçi kademe; titreşim aç/kapat/şiddet/fare; ayar kaydet/yükle; serbest sürüş:
zaman cezası yok, atlama bitirmez, istenince biter, kariyer değişmez), `AudioRegressionTest` 18/18,
`SaveRegressionTest` 17/17, `WalkthroughRegressionTest` 46/46. Mevcut: Unit 37/37, EmergencyBrake
19/19, Systems 46/46, AutoDrive gidiş (90/100 A) + dönüş (83/100 B).

### AŞAMA 9 — İstasyon atmosferi — ✅
Yolcuların %30'u banklarda oturur (telefonla/telefonsuz), %35'i peronda dolaşır, kalanı yakın
çevrede bekler; tren gelip kapılar açılınca 0–7 sn rastgele gecikmeyle kapılara yönelirler (herkes
aynı anda fırlamaz); yoğunluk saate bağlı (mevcut); istasyon uğultusu (Aşama 5). Yolcu sayıları
artırıldı (en çok 64/istasyon).

### AŞAMA 10 — Vagon içi etkileşimler — ✅
Yürürken: boş koltuğa oturma (dolu koltukta "Bu koltuk dolu"), otururken serbest bakış, X/E ile
kalkıp eski konuma dönme; incelenebilir nesneler: yolcu bilgi ekranı (anlık metin), hat haritası
(güzergâh), kapı üstü acil açma kolu, acil çağrı butonu (merkez telsizle yanıt verir).

### Bilinen sınırlar
- FPS ölçülmedi (GPU yok). Yeni yolcular v0.4'ten ağır (~12,5k yüzey/karakter, 163 kemik); 4070'te
  "Yüksek" için 60+ beklenir; düşerse önce yolcu/görünürlük ayarı (Orta ön ayar).
- Türkçe anons sesi diphone (bkz. Aşama 3). Yolcu deri/kumaş dokuları düz renk.
- Headless testler gerçek oynanışın yerini tutmaz; Forward+ ekran görüntüleri yazılım render ile alındı.

## v0.4 — REALISM & IMMERSION UPDATE

Durum: ✅ tamamlandı/test edildi · 🟡 çalışıyor, sınırlı · ❌ yapılmadı

### P0
1. **Ultra gerçekçi makinist kabini — ✅** (`tools/build_cabin.py`, Blender → GLB)
   Profil-ekstrüde konsol (diz boşluğu, eğik gösterge paneli, yastıklı kol dayama, açılı yan
   kanatlar), körüklü master kol + kademe plakası (B7…0…P4), tırtıllı 3 konumlu yön kolu, yüzüklü
   aydınlatmalı düğmeler (bezel + halka + kapak, basılma animasyonu), 4 anahtar şalter (far uzun /
   silecek / fan / anons dili — rocker animasyonu), parlaklık potansiyometresi, cam kubbeli analog hız
   saati (41 çentik, kırmızı bölge, rakamlar) + dijital hız, çerçeveli ikaz lambası modülü, MMI +
   yumuşak tuşlar, **CCTV monitörü** (sol A sütunu, kol üzerinde), telsiz ünitesi (ekran, tuşlar,
   düğmeler, ahize yuvası, spiral kablo, PTT), bolsterli deri koltuk (ray, piston, körük, yükseklik
   kolu, kolçaklar, başlık), ölü adam pedalı, menteşeli kabin kapısı (cam, kol, kilit, menteşe, tekme
   plakası), contalı sürgülü yan camlar + mandal, tavan armatürü + hoparlör + menfez + vantilatör +
   kablo kanalı, duvar panel derzleri + vidalar, sigorta panosu (24 şalter + LED), yangın tüpü +
   braket + etiket, acil çekiç kutusu, askı, doküman cebi, dolap, güneşlik, bayrak, çay, sefer
   çizelgesi. Yeni PBR setleri: `plastic_grain`, `leather`, `metal_worn`, `rubber_ribbed`, `panel_lines`.
   **Kök neden düzeltmesi:** v0.3'te tren GLB'sine MaterialLib dokuları hiç uygulanmıyordu
   (yalnızca props/istasyon); artık tüm trene uygulanıyor → plastik/metal/kauçuk/cam ayrımı görünür.
   Ön görüş korunur (göz noktası, konsol yüksekliği ve ön cam değişmedi).
2. **Ultra gerçekçi yolcu vagonları — ✅** (`tools/build_saloon.py`)
   Tekil kalıp koltuklar (plastik kabuk + kumaş + alt ısıtıcı ızgarası), cam bölücü paneller,
   alüminyum çerçeveli + contalı pencereler, kapı mekanizması (üst kılavuz ray kutusu, makaralar,
   kauçuk kenar contaları, cam çerçeveleri, tekme plakası, kapı cebi pervazları, acil kapı açma
   kutusu, uyarı plakası), kapı üstü LED PIS + hat haritası + reklam panoları, perfore tavan + yan
   kavisli paneller + klima menfezleri + gömme LED armatürler, üç kollu orta direkler, halkalı
   tutamaklar, hoparlörler, CCTV kubbeleri, interkom, yangın tüpü, **vagonlar arası körüklü geçiş**
   (geçiş plakası, körük halkaları, tutamaklar). ~1500 statik parça malzeme başına tek mesh'e
   birleştirildi (`join_static`) → araç başına ~25 çizim çağrısı.
3. **Çalışan CCTV — ✅** (`scripts/train/CCTVSystem.gd`) 16 kamera: 8 vagon içi (tavan kubbeleri)
   + 8 kapı/peron (her vagonun dış yüzü). Tek SubViewport 384×288, ~12 fps güncelleme, yalnızca
   monitör açıkken render. Kapı açılınca o tarafın kapı kamerasına geçer; CCTV düğmesi aç/kapat,
   KAM ► düğmesi veya monitöre tıklayarak kamera değiştirme; üst yazı (kamera adı, saat, REC).
   Forward+'ta ViewportTexture doğrudan; Compatibility'de ImageTexture kopyası.
4. **Gezilebilir tren içi — ✅** (`scripts/train/PlayerWalker.gd`) X: koltuktan kalk (tren durmuş,
   kol nötr, acil fren yok). WASD + Shift, fare bakış, baş sallanması; kabin kapısını aç (tık/E),
   geçişlerden 4 vagonu dolaş, yolcuları yakından gör; koltuk yanında X ile otur ve sürüşe devam.
   Çarpışmalar statik mesh'lerden trimesh (429 gövde) + kapı kanatları kutu; düşme koruması.
5. **Temel testler — ✅** Yeni `tests/SystemsTest.tscn` (46 kontrol).

### P1
6. **Doğal anonslar — 🟡 (lisans/erişim sınırı)** `tools/make_announcements.py`: 31 anons × TR + EN,
   hoparlör filtresi (bant geçiren, kompresyon, vagon yankısı), ding-dong çan. TR/EN kuyruk (üst
   üste binmez, tekrar eklenmez, kapı kapanış anonsu acil öncelikli), kabin şalteriyle TR / TR+EN.
   Tetikleyiciler: hoş geldiniz, kalkışta sonraki istasyon, 320 m kala varış + kapı yönü, son
   istasyon, kapı kapanıyor (kapı sistemiyle senkron), sinyal beklemesi, gecikme, acil fren.
   **Sesler:** İngilizce = Piper TTS (MIT) + LibriTTS high (CC BY 4.0, ticari uygun), kadın konuşmacı.
   Türkçe = MBROLA tr2 kadın diphone sesi (Debian paketi; espeak-ng'den belirgin daha doğal, ancak
   stüdyo/nöral kalitede değil). Nöral Türkçe Piper sesi (dfki) CC BY-NC-SA lisanslı → ticari oyun
   için kullanılmadı; HuggingFace erişimi de bu ortamda kapalı. Steam sürümü için önerim: stüdyo
   kaydı veya lisanslı nöral TTS (Azure/ElevenLabs) ile aynı metinleri yeniden üretmek — metin ve
   tetikleme altyapısı hazır, yalnızca WAV dosyaları değişir.
7. **Dijital yolcu bilgilendirme — ✅** (`scripts/main/PISSystem.gd`) Tren içi 24 LED ekran: sonraki
   istasyon, kapı yönü, "bu istasyon", son durak, kapılar kapanıyor (3 sn'de bir TR/EN); kapı üstü
   hat haritası (6 istasyon + başlık); reklam panoları (4 kurgusal ARS kampanyası). İstasyon PIS:
   yön, sefer no, tahmini varış (gerçek konum/hız + ara istasyon beklemesi), öndeki sefer,
   "TREN YAKLAŞIYOR / PERONDA", tarife farkına göre gecikme uyarısı.
8. **Diğer metro trenleri — ✅** Hat **çift hatlı** oldu: 8 m yanal mesafede ikinci tünel, raylar,
   traversler, 3. ray, lambalar (`TrackBuilder`); istasyonlar karşı peron, hatlar arası kolon sırası,
   ayırıcı duvar, çift tünel ağzı ile genişletildi (`StationBuilder`). `OtherTrain.gd`: aynı T-400
   modeli, far/stop lambaları, hedef yazısı, LOD (220 m iç mekân gizlenir, 900 m dizi gizlenir).
   3 karşı yön seferi (karşı peronlarda durur, hızlanır/frenler, hat başında yeniden doğar) +
   öndeki sefer artık görsel. Aynı rayda karşılıklı tren üretilmez.
9. **Gelişmiş yolcular — ✅** (`tools/build_passenger.py`) Yüz (gözler, burun, kulaklar), yaka,
   kemer; varyantlar: uzun saç, ceket (+kollar), sırt çantası, el çantası, telefon; animasyonlar:
   idle, walk, **sit, sit_phone, stand_phone, stand_hold**. Tren içinde doluluğa göre oturan /
   direğe tutunan / telefona bakan görünür yolcular (koltuk noktaları GLB'den, SeatPos_*);
   peronda telefona bakanlar; boy/genişlik ve renk varyasyonu; saate göre yoğunluk (mevcut).
10. **Kabin etkileşimleri — ✅** Yeni düğmeler: CCTV, KAM ►, ANONS, PTT; şalterler (far uzun: spot
    enerjisi/menzili artar; silecek; fan: pervane döner; TR/EN); parlaklık potansiyometresi (MMI ve
    CCTV parlaklığı, tekerlek); kabin kapısı; tüm düğmelerde basılma animasyonu ve etiket.
11. **Merkez kontrol telsizi — ✅** 10 sesli kalıp (erkek ses + telsiz filtresi + squelch) + yazılı
    detaylı mesaj: kalkış izni, regülasyon, SPAD / hareket izni, TSR hatırlatma (bir sonraki istasyon
    yaklaşımı), ATP müdahalesi, öndeki sefer gecikmesi; PTT ile makinist merkezi arar (duruma göre
    yanıt). Telsiz ekranında son mesaj. Trafik/sinyal sistemiyle aynı veriden üretilir.

### P2
12. **Serbest sürüş — ✅** Zaman cezası yok (mevcut), istasyon atlama cezası/başarısızlığı yok,
    istenen yönde sürüş, Esc → "Seferi bitir"; kariyere işlenmez (sefer sonu ekranında belirtilir).
13. **Kolay kontroller — ✅** Ayarlar → Tuşlar → Sürüş kontrol modu: W basılı hızlan, S basılı
    fren, bırakınca nötr; hız limiti otomatik korunur; Q/E peron tarafındaki kapıları açar/kapatır;
    HUD tuş satırı moda göre değişir. Gerçekçi mod varsayılan ve değişmedi.
14. **Kamera titreşimleri — ✅** Kalkış/fren hissi (ivme yatışı + ani sarsıntı), ray titreşimi
    (hızla artan frekans/genlik, 25 m'de bir ray eki tıkırtısı), viraj yatışı (hat eğriliği × hız²),
    yüksek hız ek titreşimi; Ayarlar → Kamera → "Kamera titreşimleri" ile kapatılabilir; ön görüş
    ve fare kontrolü etkilenmez.
15. **İstasyon detayları — ✅** Stil bazlı ek detaylar: havalimanı (uçuş bilgi totemi, saksılar),
    modern (dijital reklam totemleri, çalışma saatleri panosu), klasik (duvar nişleri, mozaik
    panolar, ikinci bant), derin (açık kablo tavaları, acil telefon kutuları, havalandırma
    ızgaraları); karşı peron isim panoları/banklar; istasyona özgü tohumla poster dizilimi; ek
    acil çıkış işareti. Mevcut: dijital tabelalar, banklar, çöp kutuları, CCTV, yangın dolabı, saat,
    yön tabelaları, gerçek ışıklar.
16. **Sefer sonu ve kariyer istatistikleri — ✅** Sefer özeti: sürüş süresi, toplam km, taşınan
    yolcu, ortalama hız (hareket süresine göre), maksimum hız, duruş hassasiyeti (ortalama), zamanında
    varış oranı, XP, sanal maaş. Kariyer: toplam sefer, km, yolcu, kabin saati, ortalama performans,
    makinist seviyesi/rütbe, toplam kazanç.
17. **Otomatik kayıt ve devam — ✅** (`scripts/autoload/SaveGame.gd`) Her 20 sn, duraklatmada,
    pencere kapatılırken `user://autosave.json`: tren konumu/hız/kol/yön, farlar/ışık, kapı durumu,
    istasyon dizini + görev durumu, oyun saati, aktif arızalar, doluluk, puanlama (kategoriler,
    cezalar, olay günlüğü, istatistikler), öndeki sefer/TSR. Ana menüde "Kaldığın yerden devam et";
    bozuk/eski kayıt yok sayılır ve silinir (testli). Ayarlar `settings.cfg`, kariyer `career.json`.
18. **Genel grafik ikinci geçiş — ✅** Plastik pürüzlülük yeniden pişirildi (konsol parlaması
    azaldı), bölme duvarı pencere açıklığı, pencere contaları çerçeveye dönüştürüldü, kabin ışığı
    Ultra'da gölgeli, CCTV kubbeleri koyu cam, statik birleştirme ile çizim çağrısı düşürüldü, diğer
    trenlerde LOD.

### Testler (headless, Godot 4.3)
UnitTests 37/37 · EmergencyBrakeTest 19/19 · SystemsTest 46/46 · AutoDriveTest tam hat gidiş (seed
4242: 93/100 A) ve dönüş (seed 99) ✓ · ShotV4 18 Forward+ ekran görüntüsü (lavapipe). Ayrıntı:
TEST_REPORT.md.

### Bilinen sınırlar / dürüst notlar
- **FPS ölçülmedi** (konteynerde GPU yok). RTX 4070 Laptop / 1080p "Yüksek" için 60+ beklenir
  (çift tünel + 4 görünür dizi + görünür yolcular v0.3'e göre daha ağır); takılırsa "Orta".
- Türkçe anons sesi diphone sentez (bkz. madde 6). İngilizce sesi nöral.
- Yolcular prosedürel düşük poligonlu karakterlerdir (taranmış insan modeli yok; lisanslı insan
  modeli bu ortamdan indirilemedi).
- Harici varlık kullanılmadı: tüm modeller/dokular/sesler bu depodaki betiklerle üretilir.
  Lisanslar: Piper (MIT), LibriTTS sesi (CC BY 4.0 — oyun kredilerinde "LibriTTS / Piper" atfı
  gerekir), MBROLA (AGPL — yalnızca ses dosyası üretiminde kullanıldı, oyuna gömülmedi).

## v0.3.1 — Düzeltme paketi (kullanıcı geri bildirimi)

Durum: ✅ tamamlandı/test edildi · 🟡 çalışıyor, sınırlı · ❌ yapılmadı

1. **MMI ekranı bozuk/kırpık — ✅** Blender tarafında düz plaka (plane) üretiminde UV
   koordinatları yazılmıyordu; ekran dokusu tek köşeye yığılıyordu. `tools/blender_common.plane()`
   artık 0..1 UV yazıyor; MMI, dijital hız, PIS ve hedef ekranları tam görünür.
2. **Kabin detayları — ✅** Konsola Türk bayrağı (direkli, hilal-yıldızlı), çay bardağı + tabak +
   kaşık + şeker, telsiz ahizesi (spiral kablolu), sefer çizelgesi klipsli pano, ARS plakası,
   kabin kapı kolu, paspas, tavan havalandırması, vantilatör, acil çekiç, pencere çerçeveleri,
   tuş etiketleri, hız kadranı rakamları (0–80), sabit çentik halkası (ibre ile dönmüyor).
   Konsol malzemeleri koyu panel + kenar şeridi olarak yenilendi.
3. **Yayalar açık kesimi kötü görünüyor — ✅** Açık kesim kaldırıldı (bkz. 4).
4. **Hat baştan sona yer altında — ✅** `data/routes/hat4.json` segmentleri tek `tunnel` parçası
   (0–8400 m). Gökyüzü/güneş kapalı; arka plan koyu, SDFGI/volumetrik sis tünele göre ayarlı.
   Birim testleri buna göre güncellendi (37/37).
5. **Ön camın ortasındaki çubuk — ✅** Tünel tavanındaki katener teli/askı direkleri kaldırıldı
   (metroda yoktur). Yerine ray yanında **üçüncü ray** (akım rayı) + kapak + izolatörler eklendi.
6. **Kendi bulduğum küçük hatalar — ✅**
   - Hız saati çentikleri ibreyle birlikte dönüyordu → ayrı sabit tutucu.
   - İstasyon aksan renkleri JSON'daki `accent` alanını okumuyordu → okunuyor.
   - Tünel lambaları çok sönük/parlama eşiği yanlış → enerji 1,3, glow eşiği 1,6.
   - Cam yansımasında gökyüzü beyazı → kabin camında speküler düşürüldü.
   - Çeşitli GDScript tür çıkarımı uyarıları temizlendi.

Testler: UnitTests 37/37 · EmergencyBrakeTest 19/19 · AutoDriveTest (ters yön, seed 777) başarılı.
Ekran görüntüleri Forward+ (lavapipe) ile yeniden alındı: `shots/v3_final.png`.
Sınır: FPS ölçümü yine yapılmadı (konteynerde GPU yok); RTX'te Ultra'nın 60+ vermesi beklenir ama
garanti verilmiyor.

## v0.3 — VISUAL OVERHAUL

Durum: ✅ tamamlandı/test edildi · 🟡 çalışıyor, sınırlı · ❌ yapılmadı

### 1. Kabin görüşü ve kamera — ✅ (birinci öncelik)
- Göz noktası gerçek makinist ergonomisiyle (zemin +1,25 m); konsol üstü zemin +0,82 m, eğik
  gösterge paneli en yüksek noktası +1,05 m; ön cam alt kenarı +0,95 m, üst kenarı çatı −0,25 m
  (1,25 m yükseklik, 2,1 m genişlik, 13° geriye yatık). Raylar ~11 m'den itibaren, sinyaller,
  peron ve istasyonlar engelsiz görülür; konsol görüşü kapatmaz ama kaldırılmadı.
- Fare ile yumuşatılmış serbest bakış; sınırlar kabin geometrisine göre (yaw ±115°, pitch −55/+40).
- Ayarlar → Kamera: FOV 65–100, koltuk yüksekliği (−0,12…+0,15 m), koltuk ileri (0–0,35 m),
  sallanma şiddeti, fare hassasiyeti. Yakınlaştırma: sağ tık / Z (basılı). Bakışı ortala: C.
- İvmeye bağlı gövde sallanması, hıza bağlı mikro titreşim (kapatılabilir).

### 2. Tren modeli — ✅ (Blender ile üretilmiş GLB; kutu değil)
- `tools/build_train.py`: profil ekstrüzyonu, rake'li aerodinamik burun, boolean pencere/kapı
  açıklıkları, ince cidar (solidify), cam paneller, 3 çift kayar kapı (animasyonlu, cam ve sarı
  kenarlı), kapı üstü uyarı lambaları, farlar/stop lambaları (ön/arka), üst far, hedef
  göstergeleri, kaplin/tampon, silecek, klima üniteleri, çatı kanalı, pantograf, alt şase,
  bojiler (tekerlek, aks, disk, motor, yay), etek ve aksan şeridi.
- İç mekân: kauçuk zemin, delikli tavan, ışık şeritleri (ışıklı), boyuna koltuklar, direkler,
  tutamak rayları ve askılar, eşik şeritleri, yolcu bilgi ekranları, kabin bölme duvarı.
- PBR: boya (clearcoat, portakal kabuğu normal haritası), fırçalanmış metal, kumaş, kauçuk,
  cam (alfa, düşük pürüzlülük, SSR yansıması).

### 3. Kabin — ✅
- Konsol gövdesi + üst plaka + 28° eğik gösterge paneli: MMI ekranı + 4 fonksiyon tuşu, analog
  hız saati (bezel, kadran, çentikler, ışıklı ibre) + dijital hız, 6 ikaz lambası (çerçeveli),
  master kol (yuvalı), yön kolu, 9 düğme (halkalı, basılma animasyonu), acil fren mantarı,
  reset anahtarı plakası, telsiz, makinist koltuğu (sütun, kolçak, başlık), güneşlik, yangın
  söndürücü, yan konsol, A sütunları, kabin ışık şeridi, yan camlar, bölme kapısı.
- Tüm etkileşimler (tıklama/tekerlek/tuşlar) korunur; Area3D'ler GLB düğümlerine bağlanır.

### 4. İstasyonlar — ✅
- Pişirilmiş PBR dokular: fayans (normal+rough), döşeme plakası, hissedilebilir yüzey, beton,
  tavan paneli. Beş mimari stil; havalimanı stilinde cam cephe paneli.
- Proplar (Blender): bank, çöp kutusu, otomat, yangın dolabı, kamera, PIS ekranı (dinamik metin),
  yön tabelası, gömme tavan armatürü (gerçek ışık), yuvarlak kolon, yürüyen merdiven (basamak,
  cam korkuluk, tarak), sabit merdiven, asansör, tavan açıklığı + üst çıkış koridoru.
- Yansıma probu (kutu projeksiyon) her istasyonda; SSR; ışıklı reklam panoları.

### 5. Tünel ve ray — ✅
- `tunnel_segment.glb`: halka derzli kaplama (normal haritalı), sol yürüyüş yolu + korkuluk,
  3 kablo tavası + kablolar, yangın borusu, lamba yuvaları, tavan kanalı, drenaj.
- Ray profili (baş/gövde/taban) fırçalanmış metal; beton traversler (0,65 m), bağlantı plakaları,
  balast (voronoi çakıl normal haritası); rijit katener + askılar; acil çıkış nişleri (ışıklı,
  yeşil tabela), havalandırma fanları; sinyal direği modeli (başlık, siperlik, lambalar).

### 6. Aydınlatma / efektler — ✅
- Forward+ varsayılan; ACES tonemap, kontrast/doygunluk; SSAO, SSIL (Ultra), SSR, glow,
  derinlik sisi, hacimsel sis (ışık katkılı, düşük yoğunluk), SDFGI (Ultra), güneş gölgeleri
  (açık kesim, 4 bölme), far gölgeleri (Yüksek+), istasyon ışık gölgeleri (Ultra).

### 7. Yolcular — 🟡
- `passenger.glb`: özgün stilize insan figürü (baş/saç/boyun/gövde/omuz/kol/el/bacak/ayak),
  iskelet + deri; "idle" (nefes, ağırlık aktarma, kafa dönüşü) ve "walk" (bacak/kol salınımı,
  kalça zıplaması) döngüleri. Her yolcu: rastgele ten/saç/gömlek/pantolon/ayakkabı rengi,
  boy ve genişlik; kayma önleme (animasyon hızı = yürüme hızı). Gölge düşürür.
- 🟡 Mankene yakın stilize anatomi; yüz/ el detayı yok; kıyafet varyasyonu renk + kumaş normal.

### 8. Grafik ayarları — ✅
- Ön ayarlar Düşük/Orta/Yüksek/Ultra + tek tek: çözünürlük, tam ekran, V-Sync, FPS sınırı,
  render ölçeği, kenar yumuşatma (FXAA/MSAA/TAA), gölge, doku, yansıma, görüş mesafesi, sis,
  hacimsel sis, SSAO, glow, SDFGI. Chunk tabanlı görünürlük, MultiMesh, ışık yoğunluğu.
- ❌ RTX 4070 Laptop'ta FPS ölçümü yapılamadı (bu ortamda yazılım Vulkan/llvmpipe ile yalnızca
  görsel doğrulama yapıldı). Hedef 1080p "Yüksek" 60+ FPS makul ama ölçülmedi.

### 9. Varlıklar ve lisans — ✅
- Tüm modeller ve dokular bu projede `tools/*.py` Blender betikleriyle üretildi (dış model/doku
  indirilmedi; Poly Haven/ambientCG erişimi yoktu). Harici varlık yok → lisans sorunu yok.
  Blender 4.0 (GPL araç, çıktı özgür), Godot 4.3 (MIT), espeak-ng (GPL araç; üretilen ses dosyaları
  projeye ait).

### 10. Testler — ✅
- EmergencyBrakeTest 19/19, UnitTests 37/37, AutoDriveTest tam sefer (tohum 12345) başarılı;
  Forward+ ile 10 ekran görüntüsü (tests/ShotV3.tscn).


## v0.2 — Büyük Geliştirme Güncellemesi

Durum işaretleri: ✅ tamamlandı ve test edildi · 🟡 çalışıyor, sade/ilk sürüm · ❌ yapılmadı

### 1. Acil fren — ✅
- Nedenler ayrı (MANUEL / ATP / SİNYAL İHLALİ / ARIZA); çekiş kilidi; Shift+R sıfırlama;
  şart kontrolü (duruş, kol nötr, ATP ihlali bitmiş, SPAD onay+izin, arıza giderilmiş).
- HUD ve MMI'da durum + sıfırlama talimatı. `tests/EmergencyBrakeTest.tscn` 19/19.

### 2. İstanbul atmosferi — 🟡
- ✅ Beş istasyon stili (havalimanı, modern, klasik kemerli, derin tonozlu, açık kesim sundurmalı),
  fayans/beton/balast prosedürel dokular, hat renkli isim tabelaları, yön tabelaları, saat,
  kameralar, reklam panoları, banklar, çöp kutuları, yangın dolabı, yürüyen merdiven, sabit
  merdiven, asansör, ÇIKIŞ tabelası, emniyet çizgisi/kabartma.
- ✅ Tünel: kemerli profil, yürüyüş yolu, kablo tavaları, rijit katener, lambalar, km işaretleri,
  hız levhaları. Açık kesim: istinat duvarları, korkuluk, gökyüzü, güneş/gölge (kaliteye bağlı).
- 🟡 Gerçek fotoğraf dokusu/3B model yok (dış dosya kullanılmadı); geometri kutu tabanlı.
- ❌ İstasyon giriş holleri/turnike alanı (peron dışı) yok.

### 3. Etkileşimli kabin — ✅
- Nişangâh/ışın ile tıklama; kol (tık ve tekerlek), yön kolu, kapı aç/kapat ×2, far, kabin
  ışığı, korna, onay, acil fren mantarı, acil reset; analog hız saati (ibre), MMI ekranı
  (SubViewport, 4 sayfa, arızada kararma/titreme), 6 ikaz lambası, kol/yön kolu animasyonu.

### 4. Yolcular — 🟡
- ✅ Bekleme, kapıya yönelme, biniş, iniş, çıkışa yürüme, kapı sıkışması (kapı yeniden
  açılır + ceza), yoğunluk saate/istasyona göre, doluluk → çekiş ve duraklama süresi,
  uzak istasyonlarda üretilmez, uzaktakiler seyrek güncellenir.
- 🟡 Karakterler basit (kapsül gövde, baş, bacak salınımı, çanta); tren içinde yolcu çizilmez
  (sayısal taşınır).

### 5. Arızalar — ✅ (8 tip)
- Kapı, fren uyarısı, katener kesintisi, sinyal arızası, çekiş motoru, MMI, yolcu gecikmesi,
  imdat alarmı; her biri için prosedür, MMI gösterimi, çözüm koşulu, ihmal cezası.
- Entegrasyon testinde (AutoDriveTest, farklı tohumlar) tetiklenip çözüldü.

### 6. Kariyer — ✅
- Profil, XP/seviye (12 eşik), 6 rütbe, sanal maaş, kilitler, günlük 3 / haftalık 2 görev,
  12 başarım, istatistikler, son seferler, kayıt/yükleme. UnitTests ile doğrulandı.

### 7. Uzun hat — ✅
- 6 istasyon, 8,4 km, eğimler (±1 %), kurplar, 19 hız bölgesi, 14 sinyal (otomatik üretim),
  tarife, gidiş/dönüş (aynalama), kesintisiz çok duraklı sefer. JSON veri odaklı.
- ❌ Kadıköy'e kadar tam hat henüz değil (JSON'a istasyon ekleyerek genişletilebilir).

### 8. Dinamik olaylar — ✅
- Öndeki sefer simülasyonu + blok sinyalleri (gerçek bağlantı), öndeki tren gecikmeleri,
  regülasyon beklemesi, geçici hız kısıtlaması, merkez mesajları, saate göre yoğunluk.

### 9. Grafik/ses — 🟡
- ✅ Prosedürel sesler (motor/ray/fren/kapı/korna/alarm/uyarı), Türkçe anonslar (TTS), yankı.
- ✅ Daha detaylı tren (pencereler, kapı camları, klima, pantograf, bojiler/tekerlekler, hedef
  göstergeleri, burun pahı, farlar/stoplar).
- 🟡 Dokular prosedürel; gölge yalnızca güneş (açık kesim). Anons sesi sentetik (espeak).

### 10. Menüler — ✅
- Ana menü, yeni kariyer, vardiya seçimi, serbest sürüş, görevler/başarımlar/istatistik,
  ayarlar (çözünürlük, tam ekran, kalite, 3 ses kanalı, fare, tuş atama), Esc duraklatma.

### 11. Performans — 🟡
- ✅ 100 m'lik chunk'lar (uzaktakiler gizlenir), MultiMesh, ışık sayısı sınırlı, yolcu LOD,
  kalite ön ayarları (MSAA, ölçek, güneş gölgesi).
- 🟡 Gerçek Windows GPU'da ölçüm yapılamadı (bu ortamda yazılım OpenGL ile doğrulandı).

### Testler
- EmergencyBrakeTest 19/19 · UnitTests 37/37 · AutoDriveTest: gidiş (tohum 12345, 4242, 99)
  ve dönüş (777) tam sefer başarılı · ScreenshotTest 16 görüntü.

### Bilinen eksikler / sonraki adımlar
- Tam M4 rotası (Kadıköy'e kadar), ikinci hat.
- Tren içi yolcu görselleri, daha zengin karakter modelleri/animasyon.
- Gerçek doku/model paketi (isteğe bağlı), kabin 3B modeli.
- Çevrim içi/çok oyunculu yok (planlanmadı).
