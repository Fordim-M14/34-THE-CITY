"""
make_ambience.py — Prosedürel ortam sesleri (numpy; dış kaynak yok, lisans sorunu yok).
  python3 tools/make_ambience.py [--out assets/audio/ambience]
Üretilenler (mono 22050 Hz, döngü):
  crowd_platform.wav  kalabalık peron uğultusu (uzak konuşmalar, ayak sesleri, kumaş hışırtısı)
  saloon_murmur.wav   vagon içi hafif konuşma uğultusu + kıyafet/çanta hareketleri
  hvac.wav            havalandırma uğultusu (vagon içi)
  footsteps.wav       seyrek ayak sesleri (peron)
  station_tone.wav    istasyon holü yankılı düşük uğultu (trafo/aydınlatma)
"""
import os, sys, wave
import numpy as np
from scipy.signal import butter, lfilter

argv = sys.argv[1:]
OUT = "assets/audio/ambience"
for i, a in enumerate(argv):
    if a == "--out":
        OUT = argv[i + 1]
os.makedirs(OUT, exist_ok=True)
SR = 22050
rng = np.random.default_rng(42)


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def lp(x, fc, order=2):
    b, a = butter(order, fc / (SR / 2))
    return lfilter(b, a, x)


def write(name, y, gain=0.8):
    y = y / (np.abs(y).max() + 1e-9) * gain
    # Döngü dikişi: baş/son 50 ms çapraz geçiş
    n = int(0.05 * SR)
    ramp = np.linspace(0, 1, n)
    y[:n] = y[:n] * ramp + y[-n:] * (1 - ramp)
    y = y[:-n]
    w = wave.open(os.path.join(OUT, name), "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())
    w.close()
    print("[AMB]", name, "%.1fs" % (len(y) / SR))


def voice(dur, f0, syll_rate, level):
    """Konuşma benzeri: formant bantlı gürültü + hece zarfı + hafif perde salınımı."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    src = rng.standard_normal(n)
    v = bp(src, f0 * 0.8, f0 * 1.6, 2) + 0.5 * bp(src, f0 * 2.2, f0 * 3.4, 2) + 0.25 * bp(src, f0 * 4.0, f0 * 6.0, 2)
    # Hece zarfı: rastgele uzunlukta cümleler, aralarda sessizlik
    env = np.zeros(n)
    pos = 0
    while pos < n:
        sent = int(rng.uniform(0.8, 2.5) * SR)
        gap = int(rng.uniform(0.6, 2.5) * SR)
        seg = np.arange(min(sent, n - pos)) / SR
        syl = 0.5 + 0.5 * np.sin(2 * np.pi * syll_rate * seg + rng.uniform(0, 6.28))
        syl = syl ** 1.5
        fade = np.minimum(1.0, np.minimum(seg / 0.15, (seg[-1] - seg + 1e-3) / 0.2)) if len(seg) else seg
        env[pos:pos + len(seg)] = syl * fade
        pos += sent + gap
    return v * env * level


def crowd(dur, voices, base_level):
    n = int(dur * SR)
    y = np.zeros(n)
    for k in range(voices):
        f0 = rng.uniform(110, 260)
        y += voice(dur, f0, rng.uniform(3.0, 5.5), base_level * rng.uniform(0.4, 1.0))
    return y


def footsteps(dur, rate, level):
    n = int(dur * SR)
    y = np.zeros(n)
    t = 0.0
    while t < dur:
        i = int(t * SR)
        L = int(0.08 * SR)
        if i + L < n:
            click = rng.standard_normal(L) * np.exp(-np.arange(L) / (0.012 * SR))
            click = bp(click, 150, 1800, 2)
            y[i:i + L] += click * level * rng.uniform(0.3, 1.0)
        t += rng.exponential(1.0 / rate)
    return y


def cloth(dur, rate, level):
    n = int(dur * SR)
    y = np.zeros(n)
    t = 0.0
    while t < dur:
        i = int(t * SR)
        L = int(rng.uniform(0.15, 0.4) * SR)
        if i + L < n:
            seg = rng.standard_normal(L) * np.hanning(L)
            y[i:i + L] += bp(seg, 1500, 6000, 2) * level * rng.uniform(0.3, 1.0)
        t += rng.exponential(1.0 / rate)
    return y


# 1) Peron kalabalığı
y = crowd(16.0, 14, 0.5) + footsteps(16.0, 2.5, 0.35) + cloth(16.0, 1.0, 0.25)
y = lp(y, 5000)
# Hol yankısı
ir_len = int(0.6 * SR)
ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (0.18 * SR))
ir[0] = 1.0
ir /= np.abs(ir).sum() / 2.0
y = np.convolve(y, ir)[: len(y)]
write("crowd_platform.wav", y, 0.75)
# 2) Vagon içi uğultu (daha az, daha boğuk)
y = crowd(14.0, 6, 0.35) + cloth(14.0, 0.8, 0.3)
y = lp(y, 3500)
write("saloon_murmur.wav", y, 0.6)
# 3) HVAC
n = int(8.0 * SR)
hv = lp(rng.standard_normal(n), 400, 3) + 0.4 * np.sin(2 * np.pi * 50 * np.arange(n) / SR) + 0.15 * np.sin(2 * np.pi * 100 * np.arange(n) / SR)
hv += 0.3 * bp(rng.standard_normal(n), 900, 1400, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.2 * np.arange(n) / SR))
write("hvac.wav", hv, 0.5)
# 4) Ayak sesleri (peron, seyrek)
write("footsteps.wav", lp(footsteps(10.0, 1.2, 1.0), 4000), 0.7)
# 5) İstasyon tonu
n = int(10.0 * SR)
st = 0.5 * np.sin(2 * np.pi * 100 * np.arange(n) / SR) + 0.25 * np.sin(2 * np.pi * 200 * np.arange(n) / SR) + lp(rng.standard_normal(n), 250, 3) * 0.8
st *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.07 * np.arange(n) / SR)
write("station_tone.wav", st, 0.45)
print("[AMB] done")
