"""Builds Resources/Drums/*.wav from Karoryfer 'Big Rusty Drums' (CC0-1.0) multi-mic FLACs.
Usage (from Tools/drums): python3 build_drums.py <path to karoryfer.big-rusty-drums checkout> <output dir>"""
import os, subprocess, sys
import numpy as np
from scipy.io import wavfile
from spec import SPEC, layers

SRC, OUT = sys.argv[1], sys.argv[2]
SR = 44100
MAXLEN = {"crash": 4.5, "ride": 3.5, "hat_open": 2.0}
os.makedirs(OUT, exist_ok=True)

def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(SR), "-"],
                         check=True, capture_output=True).stdout
    ch = int(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", path],
                            check=True, capture_output=True, text=True).stdout.strip())
    a = np.frombuffer(raw, dtype=np.float32).reshape(-1, ch)
    return a if ch == 2 else np.repeat(a, 2, axis=1)

total = 0
for g, (folder, prefix, n, mics) in SPEC.items():
    takes = {}
    for vi, vl in enumerate(layers(n)):
        for rr in (1, 2):
            mix = None
            for mic, w in mics.items():
                a = load(f"{SRC}/Samples/{folder}/{mic}/{prefix}_vl{vl}_rr{rr}.flac") * w
                if mix is None: mix = a
                else:
                    m = max(len(mix), len(a))
                    mix = np.pad(mix, ((0, m - len(mix)), (0, 0))) + np.pad(a, ((0, m - len(a)), (0, 0)))
            takes[(vi + 1, rr)] = mix
    peak = max(np.abs(t).max() for t in takes.values())
    for (v, rr), t in takes.items():
        t = t / peak * 0.89
        # start at the first transient (remove pre-roll), keep 1 ms before it
        thr = np.abs(t).max() * 0.02
        start = max(0, int(np.argmax(np.abs(t).max(axis=1) > thr)) - int(0.001 * SR))
        t = t[start:]
        # trim the tail at -60 dB of this take's peak, cap length, fade out
        env = np.abs(t).max(axis=1)
        above = np.nonzero(env > env.max() * 0.001)[0]
        end = min(len(t), (above[-1] + 1 if len(above) else len(t)) + int(0.02 * SR))
        end = min(end, int(MAXLEN.get(g, 1.6) * SR))
        t = t[:end].copy()
        fade = min(len(t), int(0.03 * SR))
        t[-fade:] *= np.linspace(1, 0, fade)[:, None]
        out = f"{OUT}/{g}_v{v}_rr{rr}.wav"
        wavfile.write(out, SR, (np.clip(t, -1, 1) * 32767).astype(np.int16))
        total += os.path.getsize(out)
    print(f"{g:12s} ok")
print(f"total {total/1e6:.1f} MB")
