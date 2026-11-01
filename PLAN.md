# M4 VARDİYA — Geliştirme Planı

Godot 4.3+ · Windows (x86_64) · Birinci şahıs metro sürüş simülasyonu

Kurgusal işletme: **ARS – Anadolu Raylı Sistemler İşletmesi**
Kurgusal tren: **ARS T-400 "Boğaz"** (4 araçlık dizi, 88 m)
Hat: **Hat 4 — Havalimanı Hattı** (M4'ten esinlenen, resmî olmayan kurgu)

> Gerçek Metro İstanbul logosu, renkleri veya araç tasarımı kullanılmaz.
> Hat ve istasyon adları İstanbul atmosferi için ilham kaynağıdır; oyun içi
> işletme kimliği tamamen kurgusaldır.

---

## 1. Klasör Yapısı

```
m4_vardiya/
├── project.godot                 # Proje ayarları (autoload, pencere, render)
├── icon.svg                      # Oyun ikonu (kurgusal ARS logosu)
├── export_presets.cfg            # Windows export ön ayarı (Aşama 4)
├── PLAN.md / README.md
│
├── data/
│   └── routes/
│       └── hat4_sgh_kurtkoy.json # Rota verisi: istasyonlar, hız limitleri, sinyaller, tarife
│
├── scenes/
│   ├── main/
│   │   └── Main.tscn             # Oyun giriş sahnesi; dünya + tren + UI'ı birleştirir
│   ├── train/
│   │   └── Train.tscn            # Tren kökü (fizik + görsel + kabin kamerası)
│   ├── world/
│   │   └── World.tscn            # Hat, tünel, istasyonlar, sinyaller (prosedürel)
│   ├── player/
│   │   └── Player.tscn           # Yürüyen makinist (Aşama 2)
│   └── ui/
│       ├── HUD.tscn              # Kabin MMI ekranı: hız, limit, sinyal, kapı, saat
│       ├── MissionBrief.tscn     # Görev ekranı (sefer bilgisi)
│       └── ScoreScreen.tscn      # Görev sonu puan ekranı
│
├── scripts/
│   ├── autoload/
│   │   ├── GameState.gd          # Oyun fazı, rota verisi, input tanımları
│   │   └── Scoring.gd            # Ceza/puan hesaplaması, olay günlüğü
│   ├── train/
│   │   ├── TrainController.gd    # Çekiş/fren/acil fren/yön fiziği, ATP, hat üzerinde konum
│   │   ├── TrainVisual.gd        # Araç gövdeleri, pencereler, farlar, kabin iç mekânı
│   │   ├── TrainDoors.gd         # Kapı kilitleme, taraf kontrolü, animasyon
│   │   └── CabinCamera.gd        # Birinci şahıs kamera (fare ile bakış)
│   ├── world/
│   │   ├── RouteData.gd          # JSON rota verisini yükler, limit/istasyon sorguları
│   │   ├── TrackBuilder.gd       # Curve3D hat + tünel segmentleri + raylar + aydınlatma
│   │   ├── StationBuilder.gd     # Peron, duvar, kolonlar, tabela, duruş levhası
│   │   └── TrackSignal.gd        # Sinyal direği (kırmızı/sarı/yeşil)
│   └── ui/
│       ├── HUD.gd
│       ├── MissionBrief.gd
│       └── ScoreScreen.gd
│
├── assets/
│   ├── materials/                # Ortak StandardMaterial3D kaynakları (Aşama 3)
│   ├── models/                   # .glb modeller (Aşama 3; şimdilik prosedürel)
│   ├── textures/
│   ├── audio/                    # Motor, fren, kapı ikazı, anons (Aşama 3)
│   └── fonts/
│
└── tests/
    └── autodrive_test.gd         # Headless otomatik sefer testi (CI)
```

---

## 2. İlk Prototip Görev Listesi (Dikey Kesit)

### Aşama 1 — Sürüş çekirdeği  ✅ bu teslimat
- [x] Godot projesi, autoload'lar, InputMap (W/S kol, Space acil, Q/E kapı, R yön)
- [x] Rota verisi JSON: SGH → Kurtköy, hız limitleri, sinyaller, tarife
- [x] Prosedürel hat: Curve3D (düz + S kurbu), tünel segmentleri, raylar, tünel lambaları
- [x] SGH ve Kurtköy peronları, kolonlar, tabela, duruş levhası ("DUR 4")
- [x] Tren fiziği: kademeli kol (−1..+1), çekiş/fren eğrisi, acil fren, yön kolu, direnç
- [x] ATP/hız denetimi: limit aşımı uyarısı ve otomatik acil fren
- [x] Sinyaller: kalkış sinyali (kapılar kapanınca yeşil), yaklaşım sinyali (sarı)
- [x] Kabin: koltuk perspektifi, cam, konsol, fare ile bakış
- [x] Kapılar: taraf kontrolü, hareket halinde kilit, sade kayar animasyon
- [x] Peronda duruş hassasiyeti (±0.5 m mükemmel / ±1.5 m iyi / >3 m hata)
- [x] Ceza sistemi: sert fren, hız aşımı, sinyal ihlali, yanlış taraf, yanlış duruş, tampon
- [x] HUD/MMI: hız, limit, hedef, kol konumu, sonraki istasyon mesafesi, sinyal, kapı, saat
- [x] Görev brifingi ve puan ekranı (zamanlama / konfor / güvenlik / duruş)
- [x] Headless otomatik sürüş testi

### v0.2 — Büyük güncelleme ✅ (bkz. CHANGELOG.md)
- [x] Acil fren v2 (nedenler, Shift+R, testler) · çok istasyonlu hat (6) ve dönüş yönü
- [x] Trafik/sinyal (öndeki tren simülasyonu) · arızalar (8) · yolcular · kariyer · menüler/ayarlar
- [x] Etkileşimli kabin + MMI · prosedürel ses + Türkçe anons · Windows EXE

### Aşama 2 (eski plan) — İstasyon ve görev akışı
- [ ] Yürüyen makinist (CharacterBody3D), personel girişi, görev panosu
- [ ] Trene biniş → kabin moduna geçiş (etkileşim tuşu)
- [ ] Kalkış öncesi kontrol listesi (kapı, fren testi, far)
- [ ] Duraklama süresi (dwell) ve kapı ikaz sesi

### Aşama 3 — Sanat ve atmosfer
- [ ] Özgün tren modeli (.glb, low-poly) ve kabin konsolu
- [ ] Tünel/peron dokuları, emissive tabela, ışık direkleri
- [ ] Ses: motor/çekiş vınlaması, fren, kapı ikazı, anons
- [ ] Kurgusal ARS marka paketi (logo, renk şeması, yolcu bilgi ekranı)

### Aşama 4 — Windows yayın
- [ ] export_presets.cfg, ikon, pencere/fullscreen ayarları, ayarlar menüsü
- [ ] Ana menü, tekrar oynama, grafik ön ayarları (düşük/orta)

---

## 3. Gerekli Sahneler ve Script'ler

| Sahne | Kök | Script | Görevi |
|---|---|---|---|
| `Main.tscn` | Node3D | `Main.gd` | World + Train + UI'ı kurar, fazları yönetir |
| `World.tscn` | Node3D | `TrackBuilder.gd` | Hat, tünel, istasyonlar, sinyaller, ışıklar |
| `Train.tscn` | Node3D | `TrainController.gd` | Fizik, hat konumu, ATP, olay sinyalleri |
| `HUD.tscn` | CanvasLayer | `HUD.gd` | MMI ekranı ve uyarı mesajları |
| `MissionBrief.tscn` | CanvasLayer | `MissionBrief.gd` | Sefer bilgisi, başlat |
| `ScoreScreen.tscn` | CanvasLayer | `ScoreScreen.gd` | Puan dökümü, tekrar/çıkış |

Autoload: `GameState` (faz, rota, input), `Scoring` (ceza/puan).

Script'ler arası sinyaller:
- `TrainController`: `speed_changed`, `stopped_at_platform(station, error_m)`, `signal_passed(sig, aspect)`, `buffer_hit`
- `TrainDoors`: `doors_opened(side)`, `doors_closed`
- `Scoring`: `penalty_added(code, points, text)`
- `GameState`: `phase_changed(phase)`

---

## 4. İlk Sürüm Sade 3B Sanat Planı

İlke: *"Işık ve siluet, doku değil."* Düşük poligon, düz renk malzemeler, az sayıda ışık,
emissive yüzeylerle atmosfer.

- **Tünel:** 10 m'lik dikdörtgen kesit segmentleri (iç yüzeyli), beton grisi, her 50 m'de
  sıcak renkli tünel lambası + emissive lamba kutusu. Yarı saydam sis ile derinlik.
- **Raylar:** iki ince koyu metal profil + traversler (her 2 m), ray üstü hafif parlaklık.
- **İstasyon:** geniş hol, açık gri beton peron, koyu kolonlar, tavanda soğuk beyaz
  floresan şeritler, sarı emniyet çizgisi, Label3D tabela (ARS kurgusal tipografi),
  "DUR 4" duruş levhası, peron kenarı siyah-sarı.
- **Tren (ARS T-400 "Boğaz"):** kutu gövde, hafif eğimli kabin önü, koyu pencere şeritleri,
  turkuaz + antrasit işletme renkleri, iki far + tepe lambası, kayar kapılar (her yan 3 adet).
- **Kabin:** koyu antrasit konsol, cam yüzey, kol (kol açısı fizikle senkron), MMI bilgisi HUD olarak.
- **Hedef bütçe:** < 50k üçgen sahne, < 60 dinamik ışık, tek yönlü gölge yok (ilk sürüm).

Aşama 3'te prosedürel geometri .glb modellerle değiştirilir; kod tarafı aynı kalır
(tüm görsel inşa `TrainVisual.gd`/`StationBuilder.gd` içinde izole).

---

## 5. Yapım Sırası

1. **Veri → Hat → Tren fiziği** (oynanışın çekirdeği, görsel olmadan test edilir)
2. **Kabin kamerası + HUD** (hissi doğrulamak için)
3. **Duruş kontrolü + kapılar + ceza/puan** (oyun döngüsü kapanır)  ← Aşama 1 burada biter
4. **İstasyon içi yürüyüş + görev panosu + trene biniş** (Aşama 2)
5. **Görsel/ses katmanı, marka** (Aşama 3)
6. **Menü, ayarlar, Windows export** (Aşama 4)
7. Tam hat verisi (JSON'a istasyon eklemek yeterli), NPC yolcular, arızalar, kariyer
