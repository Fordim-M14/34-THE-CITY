"""
import_voice_pack.py — Profesyonel (stüdyo / lisanslı nöral TTS) anons kayıtlarını oyuna aktarır.
  python3 tools/import_voice_pack.py --src /path/to/pack [--lang tr|en] [--no-filter]

Kaynak klasörde dosya adları manifest anahtarlarıyla aynı olmalı:
  next_PND.wav, arrive_PND_right.wav, closing.wav, welcome_forward.wav ...  (TR)
  next_PND_en.wav ... (EN)  — ya da --lang en ile uzantısız anahtarlar EN kabul edilir.
WAV/MP3/OGG/FLAC kabul edilir (ffmpeg varsa dönüştürülür). Her dosya: mono 22050 Hz, hoparlör
filtresi (isteğe bağlı), RMS eşitleme, başına ding-dong çanı (TR dosyalarına) eklenir ve
assets/audio/announce/ altına yazılır; manifest.json güncellenir. Eksik anahtarlar listelenir.
Metinler assets/audio/announce/manifest.json içindedir (tr_text / en_text) — kayıt senaryosu olarak kullanın.
"""
import os, sys, json, subprocess, shutil, tempfile
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

argv = sys.argv[1:]
SRC = None
LANG = "auto"
FILTER = True
OUT = "assets/audio/announce"
for i, a in enumerate(argv):
    if a == "--src":
        SRC = argv[i + 1]
    if a == "--lang":
        LANG = argv[i + 1]
    if a == "--no-filter":
        FILTER = False
    if a == "--out":
        OUT = argv[i + 1]
if not SRC:
    print(__doc__)
    sys.exit(1)

# make_announcements içindeki yardımcıları (okuma/yazma/filtre/çan) yeniden kullan
import importlib.util
spec = importlib.util.spec_from_file_location("ma", os.path.join(os.path.dirname(__file__), "make_announcements.py"))
# make_announcements modül düzeyinde üretim yapar; yalnızca fonksiyonları almak için kaynak metinden çıkar
src = open(os.path.join(os.path.dirname(__file__), "make_announcements.py"), encoding="utf-8").read()
head = src.split("tmp = tempfile.mkdtemp()")[0]
ns = {}
exec(compile(head, "make_announcements_head", "exec"), ns)
read_wav, write_wav, speaker_filter, chime, normalize_rms, SR = ns["read_wav"], ns["write_wav"], ns["speaker_filter"], ns["chime"], ns["normalize_rms"], ns["SR"]

manifest_path = os.path.join(OUT, "manifest.json")
manifest = json.load(open(manifest_path, encoding="utf-8")) if os.path.exists(manifest_path) else {"version": 1, "items": {}}
items = manifest["items"]
tmp = tempfile.mkdtemp()
ch = chime()
pad = np.zeros(int(0.25 * SR), dtype=np.float32)
done, unknown = [], []
for fn in sorted(os.listdir(SRC)):
    stem, ext = os.path.splitext(fn)
    if ext.lower() not in (".wav", ".mp3", ".ogg", ".flac"):
        continue
    lang = LANG
    key = stem
    if stem.endswith("_en"):
        key, lang = stem[:-3], "en"
    elif lang == "auto":
        lang = "tr"
    if key not in items:
        unknown.append(fn)
        continue
    path = os.path.join(SRC, fn)
    if ext.lower() != ".wav":
        conv = os.path.join(tmp, stem + ".wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), conv], check=True)
        path = conv
    x = read_wav(path)
    y = speaker_filter(x) if FILTER else normalize_rms(x)
    if lang == "tr":
        y = np.concatenate([ch, pad, y, pad])
        out_name = key + ".wav"
        items[key]["tr_file"] = out_name
    else:
        y = np.concatenate([y, pad])
        out_name = key + "_en.wav"
        items[key]["en_file"] = out_name
    write_wav(os.path.join(OUT, out_name), y)
    done.append(out_name)
manifest["voice_" + ("tr" if LANG != "en" else "en")] = "imported pack: " + os.path.basename(os.path.normpath(SRC))
json.dump(manifest, open(manifest_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
shutil.rmtree(tmp, ignore_errors=True)
missing_tr = [k for k, v in items.items() if not os.path.exists(os.path.join(OUT, v.get("tr_file", "")))]
missing_en = [k for k, v in items.items() if not v.get("en_file") or not os.path.exists(os.path.join(OUT, v["en_file"]))]
print("[VOICE] aktarılan:", len(done), "bilinmeyen:", unknown)
print("[VOICE] eksik TR:", missing_tr)
print("[VOICE] eksik EN:", missing_en)
print("[VOICE] Godot'ta yeniden içe aktarma gerekir (editörü açın ya da --headless --import).")
