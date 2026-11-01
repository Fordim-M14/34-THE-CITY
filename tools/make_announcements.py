"""
make_announcements.py — Yolcu anonsları (TR + EN) üretir ve hoparlör filtresi uygular.
  python3 tools/make_announcements.py [--out assets/audio/announce] [--en-voice /path/en-us-libritts-high.onnx]

Türkçe : espeak-ng + MBROLA tr2 (kadın diphone sesi; Debian paketi, çıktı sesleri serbestçe
         kullanılabilir). Not: stüdyo kalitesi değildir; ticari lisansı uygun en iyi çevrimdışı seçenek.
İngilizce: Piper TTS (MIT) + LibriTTS "high" sesi (CC BY 4.0, ticari kullanım uygun), konuşmacı 12 (kadın).
Filtre: 220–5600 Hz bant geçiren, hafif kompresyon, kısa yankı, çan (ding-dong) ön sesi.
Dosyalar: <ad>.wav (TR), <ad>_en.wav (EN). Adlar AudioManager/PISSystem ile aynıdır.
"""
import os, sys, json, subprocess, wave, tempfile, shutil
import numpy as np
from scipy.signal import butter, lfilter, resample_poly

argv = sys.argv[1:]
OUT = "assets/audio/announce"
EN_VOICE = "/tmp/piper_voices/en-us-libritts-high.onnx"
EN_SPEAKER = 12
for i, a in enumerate(argv):
    if a == "--out":
        OUT = argv[i + 1]
    if a == "--en-voice":
        EN_VOICE = argv[i + 1]
    if a == "--en-speaker":
        EN_SPEAKER = int(argv[i + 1])
os.makedirs(OUT, exist_ok=True)
SR = 22050

route = json.load(open("data/routes/hat4.json", encoding="utf-8"))
EN_NAMES = {
    "SGH": "Sabiha Gokchen Airport", "KRT": "Kurtkoy", "YYS": "Yayalar Sheyhli",
    "FCH": "Fevzi Chakmak Hospital", "TVS": "Tavshantepe", "PND": "Pendik",
}

texts = {}   # name -> (tr, en)
texts["welcome_forward"] = ("A.R.S. Hat dört'e hoş geldiniz. Bu tren Kadıköy yönüne gitmektedir.",
                            "Welcome to A.R.S. Line four. This train is bound for Kadikoy.")
texts["welcome_reverse"] = ("A.R.S. Hat dört'e hoş geldiniz. Bu tren Sabiha Gökçen Havalimanı yönüne gitmektedir.",
                            "Welcome to A.R.S. Line four. This train is bound for Sabiha Gokchen Airport.")
texts["closing"] = ("Kapılar kapanıyor. Lütfen kapılardan uzak durunuz.",
                    "Doors are closing. Please stand clear of the doors.")
texts["delay"] = ("Sayın yolcular, önümüzdeki trenin gecikmesi nedeniyle kısa bir süre bekleyeceğiz. Anlayışınız için teşekkür ederiz.",
                  "Dear passengers, we will be waiting briefly due to a delay of the train ahead. Thank you for your understanding.")
texts["emergency"] = ("Sayın yolcular, güvenliğiniz için acil fren uygulanmıştır. Lütfen tutunma yerlerinden tutununuz.",
                      "Dear passengers, the emergency brake has been applied for your safety. Please hold on.")
texts["hold"] = ("Sayın yolcular, sinyal nedeniyle kısa bir süre bekleyeceğiz.",
                 "Dear passengers, we are being held at a signal and will depart shortly.")
texts["mind_gap"] = ("Lütfen tren ile peron arasındaki boşluğa dikkat ediniz.",
                     "Please mind the gap between the train and the platform.")
for st in route["stations"]:
    sid, name = st["id"], st["name"]
    en = EN_NAMES.get(sid, name)
    texts["next_" + sid] = ("Gelecek istasyon, %s." % name, "Next station, %s." % en)
    texts["arrive_%s_right" % sid] = ("%s. Kapılar sağdan açılacaktır." % name, "%s. Doors will open on the right." % en)
    texts["arrive_%s_left" % sid] = ("%s. Kapılar soldan açılacaktır." % name, "%s. Doors will open on the left." % en)
    texts["terminus_" + sid] = ("Son istasyon, %s. Lütfen tüm eşyalarınızı alarak ininiz. İyi günler dileriz." % name,
                                "This is the last stop, %s. Please take all your belongings with you. Have a nice day." % en)


def read_wav(path):
    w = wave.open(path)
    sr = w.getframerate()
    n = w.getnchannels()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    if n > 1:
        x = x.reshape(-1, n).mean(axis=1)
    if sr != SR:
        from math import gcd
        g = gcd(sr, SR)
        x = resample_poly(x, SR // g, sr // g)
    return x


def write_wav(path, x):
    x = np.clip(x, -1.0, 1.0)
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((x * 32767).astype(np.int16).tobytes())
    w.close()


def chime():
    """İki tonlu peron çanı (ding-dong), 0,9 s."""
    t = np.arange(int(0.45 * SR)) / SR
    def tone(f, dur_env):
        env = np.exp(-t * dur_env)
        return (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2 * t) + 0.15 * np.sin(2 * np.pi * f * 3 * t)) * env
    a = tone(880.0, 4.0)
    b = tone(659.25, 3.5)
    out = np.concatenate([a, b]) * 0.35
    return out


TARGET_RMS = 0.11   # ~ -19 dBFS: tüm anonslar aynı algılanan seviyede


def normalize_rms(y):
    rms = float(np.sqrt(np.mean(y * y)) + 1e-9)
    g = TARGET_RMS / rms
    y = y * min(g, 6.0)
    peak = float(np.abs(y).max() + 1e-9)
    if peak > 0.95:
        y = y / peak * 0.95
    return y.astype(np.float32)


def speaker_filter(x):
    b, a = butter(2, [220.0 / (SR / 2), 5600.0 / (SR / 2)], btype="band")
    y = lfilter(b, a, x)
    # Hafif kompresyon (yumuşak sınırlama)
    y = np.tanh(y * 2.2) / np.tanh(2.2)
    # Kısa yankı (vagon içi): azalan gürültü darbe cevabı
    rng = np.random.default_rng(3)
    ir_len = int(0.25 * SR)
    ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (0.06 * SR))
    ir[0] = 1.0
    ir /= np.abs(ir).sum() / 1.6
    y = np.convolve(y, ir)[: len(x) + ir_len]
    return normalize_rms(y)


def tts_tr(text, path):
    subprocess.run(["espeak-ng", "-v", "mb/mb-tr2", "-s", "150", "-p", "52", "-a", "170", "-w", path, text],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def tts_en(text, path):
    subprocess.run([sys.executable, "-m", "piper", "-m", EN_VOICE, "-s", str(EN_SPEAKER), "-f", path,
                    "--length-scale", "1.08", "--sentence-silence", "0.35"],
                   input=text.encode("utf-8"), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


tmp = tempfile.mkdtemp()
ch = chime()
manifest = {"version": 1, "voice_tr": "mbrola-tr2 (diphone, CC-free output)", "voice_en": "piper libritts-high spk12 (CC BY 4.0)",
            "note": "Profesyonel kayıt için tools/import_voice_pack.py — aynı anahtarlarla WAV/MP3 verin.", "items": {}}
RADIO_ONLY = "--radio-only" in argv
if RADIO_ONLY:
    texts = {}
pad = np.zeros(int(0.25 * SR), dtype=np.float32)
have_en = os.path.exists(EN_VOICE)
for name, (tr, en) in texts.items():
    p_tr = os.path.join(tmp, name + "_tr.wav")
    tts_tr(tr, p_tr)
    x = read_wav(p_tr)
    y = np.concatenate([ch, pad, speaker_filter(x), pad])
    write_wav(os.path.join(OUT, name + ".wav"), y)
    if have_en:
        p_en = os.path.join(tmp, name + "_en.wav")
        tts_en(en, p_en)
        xe = read_wav(p_en)
        ye = np.concatenate([speaker_filter(xe), pad])
        write_wav(os.path.join(OUT, name + "_en.wav"), ye)
    manifest["items"][name] = {"tr_text": tr, "en_text": en, "tr_file": name + ".wav", "en_file": (name + "_en.wav") if have_en else ""}
    print("[ANNOUNCE]", name, "%.1fs" % (len(y) / SR), "(+en)" if have_en else "")
# Yalnız çan
write_wav(os.path.join(OUT, "chime.wav"), np.concatenate([ch, pad]))

# ---------------------------------------------------------------------------
# Merkez (OCC) telsiz sesleri: erkek ses (MBROLA tr1) + telsiz filtresi (dar bant, squelch)
RADIO = {
    "radio_departure_ok": "Merkezden sefere. Kalkış izniniz verilmiştir. İyi seferler.",
    "radio_regulation": "Merkezden sefere. İstasyonda regülasyon beklemesi uygulayın. Kalkış sinyali yeşile dönünce hareket edin.",
    "radio_spad": "Merkezden sefere. Sinyal kırmızıda geçildi. Treni durdurun ve ihlali onaylayın. İzin verilene kadar bekleyin.",
    "radio_spad_permit": "Merkezden sefere. Hareket izniniz verilmiştir. Acil freni sıfırlayıp dikkatli ilerleyin.",
    "radio_tsr": "Merkezden sefere. İleride geçici hız kısıtlaması var. Hızınızı düşürün.",
    "radio_lead_delay": "Merkezden sefere. Öndeki sefer istasyonda bekliyor. Sinyallere uyun.",
    "radio_atp": "Merkezden sefere. ATP müdahalesi kaydedildi. Hız limitlerine uyun.",
    "radio_ack": "Merkezden sefere. Anlaşıldı, hat normal. Devam edin.",
    "radio_hold_signal": "Merkezden sefere. Önünüzdeki tren nedeniyle sinyalde bekleyin.",
    "radio_fault": "Merkezden sefere. Arıza bildiriminiz alındı. Prosedürü uygulayın ve bilgi verin.",
}


def radio_filter(x):
    b, a = butter(3, [400.0 / (SR / 2), 3200.0 / (SR / 2)], btype="band")
    y = lfilter(b, a, x)
    y = np.tanh(y * 4.0) / np.tanh(4.0)
    rng = np.random.default_rng(7)
    y = y + rng.standard_normal(len(y)) * 0.012
    # Squelch: başta/sonda kısa gürültü patlaması
    sq = rng.standard_normal(int(0.07 * SR)) * np.linspace(0.25, 0.0, int(0.07 * SR))
    y = np.concatenate([sq, y, sq[::-1]])
    y = y / (np.abs(y).max() + 1e-6) * 0.8
    return y.astype(np.float32)


for name, text in RADIO.items():
    p_r = os.path.join(tmp, name + ".wav")
    subprocess.run(["espeak-ng", "-v", "mb/mb-tr1", "-s", "155", "-p", "40", "-a", "170", "-w", p_r, text],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    write_wav(os.path.join(OUT, name + ".wav"), radio_filter(read_wav(p_r)))
    print("[RADIO]", name)
shutil.rmtree(tmp, ignore_errors=True)
if not RADIO_ONLY:
    json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("[ANNOUNCE] done:", len(texts), "metin; EN:", have_en)
