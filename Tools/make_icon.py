"""Regenerates Resources/AppIcon.icns (+ SVG/PNG master in Resources/Icon).
Needs Python 3 with Pillow and rsvg-convert (brew install librsvg). Run from the repo root:
    python3 Tools/make_icon.py
"""
import math, random, struct, subprocess, sys, os

S = 1024
cx = cy = 512
random.seed(7)

def lerp(a, b, t): return a + (b - a) * t
def mix(c1, c2, t): return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))
RED, AMBER, GREEN, CYAN = (255, 59, 74), (255, 176, 32), (46, 224, 122), (82, 209, 255)
def ramp(t):
    # red -> amber -> green -> cyan around the ring
    stops = [(0, RED), (0.35, AMBER), (0.7, GREEN), (1.0, CYAN)]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1: return mix(c0, c1, (t - t0) / (t1 - t0))
    return stops[-1][1]
def hexc(c): return '#%02x%02x%02x' % c
def pt(r, a): return cx + r * math.cos(a), cy + r * math.sin(a)

progress = 0.78
parts = []

# waveform bars
n = 96
inner = 178
for i in range(n):
    f = i / n
    a = -math.pi / 2 + 2 * math.pi * f
    env = 0.35 + 0.65 * abs(math.sin(f * math.pi * 4 + 0.6)) ** 1.5
    v = env * (0.55 + 0.45 * random.random())
    length = 14 + v * 92
    x0, y0 = pt(inner, a); x1, y1 = pt(inner + length, a)
    played = f <= progress
    col = hexc(ramp(f)) if played else '#ffffff'
    op = 0.95 if played else 0.16
    parts.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{col}" stroke-opacity="{op}" stroke-width="9" stroke-linecap="round"/>')
bars = '\n'.join(parts)

# progress arc as many short segments (fake angular gradient)
R = 318
segs = []
m = 160
for i in range(int(m * progress)):
    f0, f1 = i / m, (i + 1.15) / m
    a0 = -math.pi / 2 + 2 * math.pi * f0; a1 = -math.pi / 2 + 2 * math.pi * min(f1, progress)
    x0, y0 = pt(R, a0); x1, y1 = pt(R, a1)
    segs.append(f'<path d="M{x0:.2f},{y0:.2f} A{R},{R} 0 0 1 {x1:.2f},{y1:.2f}" stroke="{hexc(ramp(f0))}" stroke-width="30" fill="none" stroke-linecap="butt"/>')
arc = '\n'.join(segs)
ha = -math.pi / 2 + 2 * math.pi * progress
hx, hy = pt(R, ha)
sx, sy = pt(R, -math.pi / 2)

ticks = []
for k in range(4):
    a = -math.pi / 2 + k * math.pi / 2
    x0, y0 = pt(R - 34, a); x1, y1 = pt(R - 22, a)
    ticks.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="#ffffff" stroke-opacity="0.45" stroke-width="6" stroke-linecap="round"/>')
ticks = '\n'.join(ticks)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
<defs>
  <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2b2f38"/><stop offset="0.55" stop-color="#14161b"/><stop offset="1" stop-color="#08090c"/>
  </linearGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.35"/><stop offset="0.4" stop-color="#ffffff" stop-opacity="0.04"/><stop offset="1" stop-color="#000000" stop-opacity="0.5"/>
  </linearGradient>
  <radialGradient id="ambient" cx="0.5" cy="0.52" r="0.5">
    <stop offset="0" stop-color="#ff3b4a" stop-opacity="0.30"/><stop offset="0.55" stop-color="#52d1ff" stop-opacity="0.08"/><stop offset="1" stop-color="#000000" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glass" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#0d1016"/><stop offset="0.86" stop-color="#05060a"/><stop offset="1" stop-color="#000000"/>
  </radialGradient>
  <radialGradient id="rec" cx="0.38" cy="0.32" r="0.75">
    <stop offset="0" stop-color="#ff9aa2"/><stop offset="0.35" stop-color="#ff3b4a"/><stop offset="1" stop-color="#9c0716"/>
  </radialGradient>
  <linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.10"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>
  </linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="18"/><feOffset dy="18"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.55"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter>
  <filter id="softglow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
  <clipPath id="sq"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath>
</defs>

<g filter="url(#shadow)">
  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#body)"/>
</g>
<g clip-path="url(#sq)">
  <rect x="100" y="100" width="824" height="824" fill="url(#ambient)"/>
  <!-- screws -->
  <g fill="#8a8f99" fill-opacity="0.55">
    <circle cx="170" cy="170" r="11"/><circle cx="854" cy="170" r="11"/><circle cx="170" cy="854" r="11"/><circle cx="854" cy="854" r="11"/>
  </g>
  <!-- glass display disc -->
  <circle cx="{cx}" cy="{cy}" r="372" fill="url(#glass)"/>
  <circle cx="{cx}" cy="{cy}" r="372" fill="none" stroke="#000" stroke-width="10"/>
  <circle cx="{cx}" cy="{cy}" r="366" fill="none" stroke="#ffffff" stroke-opacity="0.10" stroke-width="2"/>
  <!-- ring track -->
  <circle cx="{cx}" cy="{cy}" r="{R}" fill="none" stroke="#ffffff" stroke-opacity="0.07" stroke-width="30"/>
  {ticks}
  {bars}
  <!-- glow pass of the arc -->
  <g filter="url(#glow)" opacity="0.9">{arc}</g>
  {arc}
  <circle cx="{sx:.1f}" cy="{sy:.1f}" r="15" fill="{hexc(RED)}"/>
  <!-- playhead -->
  <circle cx="{hx:.1f}" cy="{hy:.1f}" r="30" fill="#ffffff" filter="url(#softglow)" opacity="0.9"/>
  <circle cx="{hx:.1f}" cy="{hy:.1f}" r="21" fill="#ffffff"/>
  <!-- record button -->
  <circle cx="{cx}" cy="{cy}" r="120" fill="#ff3b4a" filter="url(#glow)" opacity="0.75"/>
  <circle cx="{cx}" cy="{cy}" r="112" fill="#050608"/>
  <circle cx="{cx}" cy="{cy}" r="96" fill="url(#rec)"/>
  <ellipse cx="{cx}" cy="{cy-44}" rx="58" ry="30" fill="#ffffff" fill-opacity="0.22"/>
  <!-- glass reflection -->
  <rect x="100" y="100" width="824" height="420" fill="url(#shine)"/>
</g>
<rect x="101.5" y="101.5" width="821" height="821" rx="185" fill="none" stroke="url(#rim)" stroke-width="3"/>
</svg>
'''
os.makedirs('Resources/Icon', exist_ok=True)
open('Resources/Icon/AppIcon.svg', 'w').write(svg)
subprocess.run(['rsvg-convert', '-w', '1024', '-h', '1024', 'Resources/Icon/AppIcon.svg', '-o', 'Resources/Icon/AppIcon-1024.png'], check=True)

# build .icns from PNG renditions
from PIL import Image
master = Image.open('Resources/Icon/AppIcon-1024.png').convert('RGBA')
entries = [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128), ('ic08', 256), ('ic09', 512),
           ('ic10', 1024), ('ic11', 32), ('ic12', 64), ('ic13', 256), ('ic14', 512)]
import io
chunks = b''
for typ, px in entries:
    buf = io.BytesIO()
    master.resize((px, px), Image.LANCZOS).save(buf, format='PNG', optimize=True)
    data = buf.getvalue()
    chunks += typ.encode() + struct.pack('>I', len(data) + 8) + data
icns = b'icns' + struct.pack('>I', len(chunks) + 8) + chunks
open('Resources/AppIcon.icns', 'wb').write(icns)
print('ok', len(icns))
