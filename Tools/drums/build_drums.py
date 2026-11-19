"""Builds Resources/Drums from Karoryfer 'Big Rusty Drums' (CC0-1.0) multi-mic FLACs.

Usage: python3 build_drums.py <karoryfer.big-rusty-drums checkout> <output dir>

For every group in spec.py it mixes the close / overhead / bleed microphones of each
velocity layer and round-robin take into a stereo file, places the mono close mics at
the instrument's position in the overhead image, trims pre-roll and silent tails
(relative to the loudest take of the group, so soft hits keep their natural decay),
and writes 16-bit ALAC .caf files plus manifest.json with the measured attack loudness
of every layer (the app uses it to pick layers by velocity)."""
import json, os, subprocess, sys
import numpy as np
from spec import SPEC, layers

SRC, OUT = sys.argv[1], sys.argv[2]
SR = 44100
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(SR), "-"],
                         check=True, capture_output=True).stdout
    ch = int(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", path],
                            check=True, capture_output=True, text=True).stdout.strip())
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch).astype(np.float64)


def add(mix, a):
    if mix is None:
        return a.copy()
    m = max(len(mix), len(a))
    return np.pad(mix, ((0, m - len(mix)), (0, 0))) + np.pad(a, ((0, m - len(a)), (0, 0)))


def attack_db(t):
    """Loudest 30 ms RMS (mono sum) in dB: what the ear hears as the hit's loudness."""
    m = t.mean(axis=1)
    w = int(0.03 * SR)
    e = np.convolve(m * m, np.ones(w) / w, mode="valid")
    return 10 * np.log10(max(e.max(), 1e-12))


def write_caf(path, t):
    pcm = np.clip(t * 32767 + rng.triangular(-1, 0, 1, t.shape), -32768, 32767).astype("<i2")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "alac", path], input=pcm.tobytes(), check=True)


manifest = {"sampleRate": SR, "groups": {}}
total_s = 0.0
for g, (folder, prefix, n, keep, rrs, mics, maxlen) in SPEC.items():
    vls = layers(n, keep)
    # position of the instrument in the overhead image -> pan for the mono close mics
    oh = load(f"{SRC}/Samples/{folder}/oh/{prefix}_vl{n}_rr1.flac")
    el, er = np.sqrt((oh[:, 0] ** 2).mean()), np.sqrt((oh[:, 1] ** 2).mean())
    pos = float(np.clip((er - el) / (er + el + 1e-12), -0.8, 0.8))        # -1 left … +1 right
    ang = (pos + 1) * np.pi / 4
    pan = np.array([np.cos(ang), np.sin(ang)]) * np.sqrt(2)
    takes = {}
    for vi, vl in enumerate(vls):
        for rr in range(1, rrs + 1):
            mix = None
            for mic, w in mics.items():
                a = load(f"{SRC}/Samples/{folder}/{mic}/{prefix}_vl{vl}_rr{rr}.flac")
                a = a * pan[None, :] if a.shape[1] == 1 else a
                mix = add(mix, a * w)
            takes[(vi, rr - 1)] = mix
    peak = max(np.abs(t).max() for t in takes.values())
    # common pre-roll: the loudest take's onset defines where the transient sits
    floor = peak * 10 ** (-62 / 20)
    info = []
    for vi in range(len(vls)):
        dbs = []
        for rr in range(rrs):
            t = takes[(vi, rr)] / peak * 0.89
            env = np.abs(t).max(axis=1)
            thr = env.max() * 0.06
            start = max(0, int(np.argmax(env > thr)) - int(0.0015 * SR))
            t = t[start:]
            env = env[start:]
            above = np.nonzero(env > floor / peak * 0.89)[0]
            end = (above[-1] + 1 if len(above) else len(t)) + int(0.01 * SR)
            end = min(len(t), end, int(maxlen * SR))
            t = t[:end].copy()
            fade = min(len(t), int(0.06 * SR) if end >= int(maxlen * SR) else int(0.01 * SR))
            t[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
            dbs.append(attack_db(t))
            write_caf(f"{OUT}/{g}_v{vi + 1}_rr{rr + 1}.caf", t)
            total_s += len(t) / SR
        info.append(round(float(np.mean(dbs)), 2))
    top = max(info)
    manifest["groups"][g] = {"layers": len(vls), "roundRobins": rrs, "pan": round(pos, 3),
                             "loudness": [round(x - top, 2) for x in info]}
    print(f"{g:12s} layers {vls}  pan {pos:+.2f}  loudness {[round(x - top, 1) for x in info]}")

with open(f"{OUT}/manifest.json", "w") as f:
    json.dump(manifest, f, indent=1)
size = sum(os.path.getsize(f"{OUT}/{x}") for x in os.listdir(OUT))
print(f"audio {total_s:.0f} s stereo, files {size / 1e6:.1f} MB, RAM as int16 {total_s * SR * 4 / 1e6:.0f} MB")
