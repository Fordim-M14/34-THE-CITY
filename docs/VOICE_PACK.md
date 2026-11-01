# Anons ses paketi değiştirme (profesyonel kayıt / lisanslı TTS)

Oyun, anonsları `assets/audio/announce/manifest.json` üzerinden çözer. Her anahtar için
`tr_file` ve `en_file` vardır; metinler `tr_text` / `en_text` alanlarındadır (kayıt senaryosu).

1. Stüdyoda veya ticari lisanslı nöral TTS ile (ör. Azure Neural "tr-TR-EmelNeural", ElevenLabs)
   her anahtarı aynı adla kaydedin: `next_PND.wav`, `arrive_PND_right.wav`, `closing.wav` …
   İngilizce için `_en` soneki: `next_PND_en.wav`.
2. `python3 tools/import_voice_pack.py --src /kayitlar` → mono 22,05 kHz'e çevirir, RMS eşitler,
   hoparlör filtresi ve çan ekler, manifesti günceller, eksikleri listeler.
3. Godot'ta projeyi bir kez açın (içe aktarma) ve EXE'yi yeniden dışa aktarın.

Mevcut sesler: TR = MBROLA tr2 (diphone; Debian paketi, üretilen ses dosyaları serbest), EN = Piper +
LibriTTS (CC BY 4.0 — kredilerde "LibriTTS (CC BY 4.0) / Piper TTS (MIT)" atfı). Türkçe nöral sesler
(Piper tr_TR dfki: CC BY-NC-SA; MMS-TTS: CC BY-NC) ticari kullanıma kapalı olduğu için kullanılmadı.
