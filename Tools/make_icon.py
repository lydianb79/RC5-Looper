"""Regenerates the app icon: Resources/AppIcon.icns plus the SVG / 1024 px masters in Resources/Icon.

Needs Python 3 with Pillow and rsvg-convert (brew install librsvg). Run from the repo root:
    python3 Tools/make_icon.py

Every size is rendered from vector art at 4x and downsampled, and the small sizes (16-64 px)
use a simplified drawing with thicker shapes so they stay crisp in Finder and the Dock.
"""
import io, math, os, random, struct, subprocess
from PIL import Image

OUT_DIR = 'Resources/Icon'
os.makedirs(OUT_DIR, exist_ok=True)
S = 1024
C = S / 2


def squircle(x0, y0, size, n=5.0, steps=720):
    """Apple-style continuous-corner square (superellipse)."""
    r = size / 2
    cx, cy = x0 + r, y0 + r
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = cx + r * math.copysign(abs(ct) ** (2 / n), ct)
        y = cy + r * math.copysign(abs(st) ** (2 / n), st)
        pts.append(f'{x:.2f},{y:.2f}')
    return 'M' + ' L'.join(pts) + ' Z'


def pt(r, a):
    return C + r * math.cos(a), C + r * math.sin(a)


def arc(r, a0, a1):
    x0, y0 = pt(r, a0)
    x1, y1 = pt(r, a1)
    large = 1 if (a1 - a0) % (2 * math.pi) > math.pi else 0
    return f'M{x0:.2f},{y0:.2f} A{r},{r} 0 {large} 1 {x1:.2f},{y1:.2f}'


def lerp(a, b, t):
    return a + (b - a) * t


STOPS = [(0.0, (0x5B, 0xE9, 0xFF)), (0.5, (0x8B, 0x7C, 0xFF)), (1.0, (0xFF, 0x5C, 0xC8))]


def ramp(t):
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return '#%02x%02x%02x' % tuple(int(lerp(a, b, f)) for a, b in zip(c0, c1))
    return '#%02x%02x%02x' % STOPS[-1][1]


def svg(detail=True):
    random.seed(11)
    body = squircle(100, 100, 824)
    progress = 0.74
    start = -math.pi / 2
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">',
           '<defs>',
           '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
           '<stop offset="0" stop-color="#2a2f45"/><stop offset="0.55" stop-color="#141726"/><stop offset="1" stop-color="#07080e"/></linearGradient>',
           '<radialGradient id="glowA" cx="0.25" cy="0.18" r="0.75"><stop offset="0" stop-color="#4f6bff" stop-opacity="0.45"/><stop offset="1" stop-color="#4f6bff" stop-opacity="0"/></radialGradient>',
           '<radialGradient id="glowB" cx="0.85" cy="0.95" r="0.7"><stop offset="0" stop-color="#ff4fb3" stop-opacity="0.32"/><stop offset="1" stop-color="#ff4fb3" stop-opacity="0"/></radialGradient>',
           '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.35"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0.05"/><stop offset="1" stop-color="#000000" stop-opacity="0.4"/></linearGradient>',
           '<linearGradient id="bezel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5d6380"/><stop offset="0.5" stop-color="#23263a"/><stop offset="1" stop-color="#0b0c14"/></linearGradient>',
           '<radialGradient id="dial" cx="0.5" cy="0.42" r="0.6"><stop offset="0" stop-color="#1b1e30"/><stop offset="1" stop-color="#05060b"/></radialGradient>',
           '<radialGradient id="btn" cx="0.42" cy="0.32" r="0.75"><stop offset="0" stop-color="#ff8a80"/><stop offset="0.45" stop-color="#ff3b4a"/><stop offset="1" stop-color="#8e0f1f"/></radialGradient>',
           '<radialGradient id="btnGlow" cx="0.5" cy="0.5" r="0.5"><stop offset="0.55" stop-color="#ff3b4a" stop-opacity="0.55"/><stop offset="1" stop-color="#ff3b4a" stop-opacity="0"/></radialGradient>',
           '<linearGradient id="spec" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.85"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient>',
           '<linearGradient id="arcg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5be9ff"/><stop offset="0.5" stop-color="#8b7cff"/><stop offset="1" stop-color="#ff5cc8"/></linearGradient>',
           '<filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="18"/><feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
           '<filter id="blur12" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="12"/></filter>',
           '<filter id="blur6" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>',
           f'<clipPath id="body"><path d="{body}"/></clipPath>',
           '</defs>']
    # body with drop shadow
    out.append(f'<g filter="url(#shadow)"><path d="{body}" fill="url(#bg)"/></g>')
    out.append(f'<g clip-path="url(#body)"><rect width="{S}" height="{S}" fill="url(#glowA)"/><rect width="{S}" height="{S}" fill="url(#glowB)"/></g>')
    out.append(f'<path d="{body}" fill="none" stroke="url(#rim)" stroke-width="4"/>')
    # bezel and dial
    R = 352
    out.append(f'<circle cx="{C}" cy="{C}" r="{R + 22}" fill="url(#bezel)"/>')
    out.append(f'<circle cx="{C}" cy="{C}" r="{R + 8}" fill="url(#dial)"/>')
    out.append(f'<circle cx="{C}" cy="{C}" r="{R + 8}" fill="none" stroke="#000" stroke-opacity="0.6" stroke-width="3"/>')
    ring_r = R - 22
    track_w = 26 if detail else 44
    out.append(f'<circle cx="{C}" cy="{C}" r="{ring_r}" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="{track_w}"/>')
    # radial waveform
    if detail:
        n = 112
        inner = 160
        for i in range(n):
            f = i / n
            a = start + 2 * math.pi * f
            env = 0.3 + 0.7 * abs(math.sin(f * math.pi * 3 + 0.5)) ** 1.4
            v = env * (0.6 + 0.4 * random.random())
            length = 10 + v * 104
            x0, y0 = pt(inner, a)
            x1, y1 = pt(inner + length, a)
            played = f <= progress
            col = ramp(f / progress) if played else '#ffffff'
            op = 0.95 if played else 0.14
            out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{col}" '
                       f'stroke-opacity="{op}" stroke-width="7.5" stroke-linecap="round"/>')
        # bar ticks
        for k in range(4):
            a = start + k * math.pi / 2
            x0, y0 = pt(ring_r - 30, a)
            x1, y1 = pt(ring_r - 44, a)
            out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="#ffffff" stroke-opacity="0.35" stroke-width="5" stroke-linecap="round"/>')
    # progress arc with glow
    a1 = start + 2 * math.pi * progress
    d = arc(ring_r, start, a1)
    segs = 90
    glow, line = [], []
    for k in range(segs):
        f0, f1 = k / segs, (k + 1.6) / segs
        if f0 >= 1:
            break
        sd = arc(ring_r, start + (a1 - start) * f0, start + (a1 - start) * min(1, f1))
        col = ramp((k + 0.5) / segs)
        cap = 'round' if k in (0, segs - 1) else 'butt'
        glow.append(f'<path d="{sd}" fill="none" stroke="{col}" stroke-width="{track_w + 12}" stroke-linecap="{cap}"/>')
        line.append(f'<path d="{sd}" fill="none" stroke="{col}" stroke-width="{track_w}" stroke-linecap="{cap}"/>')
    out.append('<g opacity="0.5" filter="url(#blur12)">' + ''.join(glow) + '</g>')
    out.append('<g>' + ''.join(line) + '</g>')
    hx, hy = pt(ring_r, a1)
    out.append(f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{track_w * 0.95:.1f}" fill="#ffffff" opacity="0.6" filter="url(#blur6)"/>')
    out.append(f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{track_w * 0.62:.1f}" fill="#ffffff"/>')
    # record button
    br = 108 if detail else 150
    out.append(f'<circle cx="{C}" cy="{C}" r="{br + 46}" fill="url(#btnGlow)"/>')
    out.append(f'<circle cx="{C}" cy="{C}" r="{br + 16}" fill="#06070c"/>')
    out.append(f'<circle cx="{C}" cy="{C}" r="{br + 16}" fill="none" stroke="#ffffff" stroke-opacity="0.12" stroke-width="3"/>')
    out.append(f'<circle cx="{C}" cy="{C}" r="{br}" fill="url(#btn)"/>')
    out.append(f'<ellipse cx="{C}" cy="{C - br * 0.48:.1f}" rx="{br * 0.62:.1f}" ry="{br * 0.34:.1f}" fill="url(#spec)" opacity="0.75"/>')
    out.append(f'<circle cx="{C}" cy="{C}" r="{br}" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="2"/>')
    out.append('</svg>')
    return '\n'.join(out)


def render(svg_text, px):
    """Vector render at 4x the target size, then a high-quality downsample."""
    big = max(px * 4, 1024)
    png = subprocess.run(['rsvg-convert', '-w', str(big), '-h', str(big)], input=svg_text.encode(),
                         capture_output=True, check=True).stdout
    img = Image.open(io.BytesIO(png)).convert('RGBA')
    return img if big == px else img.resize((px, px), Image.LANCZOS)


full = svg(True)
simple = svg(False)
open(f'{OUT_DIR}/AppIcon.svg', 'w').write(full)
master = render(full, 1024)
master.save(f'{OUT_DIR}/AppIcon-1024.png', optimize=True)

entries = [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128), ('ic08', 256), ('ic09', 512),
           ('ic10', 1024), ('ic11', 32), ('ic12', 64), ('ic13', 256), ('ic14', 512)]
cache = {}
chunks = b''
for tag, px in entries:
    if px not in cache:
        img = render(simple if px <= 64 else full, px)
        buf = io.BytesIO()
        img.save(buf, format='PNG', optimize=True)
        cache[px] = buf.getvalue()
    data = cache[px]
    chunks += tag.encode() + struct.pack('>I', len(data) + 8) + data
icns = b'icns' + struct.pack('>I', len(chunks) + 8) + chunks
open('Resources/AppIcon.icns', 'wb').write(icns)
for px in (16, 32, 64, 128):
    render(simple if px <= 64 else full, px).save(f'/tmp/icon_{px}.png')
print('ok', len(icns))
