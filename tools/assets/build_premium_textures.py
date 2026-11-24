"""EXIT 6 Premium texture sets: tileable PBR maps for SurfaceAppearance.

Run:  python tools/assets/build_premium_textures.py
Out:  assets/wear/premium/tex/<set>_<map>.png  (512 x 512, seamless)
      build/premium_textures.png               (contact sheet)

Every set is procedural and original (periodic noise, so tiles have no
seams). Colour maps are near-white: Exit6Style tints them per item through
SurfaceAppearance.Color, so one set serves every colourway. Normal maps are
tangent space, OpenGL convention (green = up), as Roblox expects. Flat maps
are never written (a set without a metalness map is simply non-metal).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "wear" / "premium" / "tex"
N = 512
rng = np.random.default_rng(6)
Y, X = np.mgrid[0:N, 0:N].astype(np.float64)


def fnoise(lo, hi, aniso=(1.0, 1.0)):
    """Tileable band-passed noise in [-1, 1]; lo/hi are cycles per tile."""
    w = rng.standard_normal((N, N))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(N)[:, None] * N * aniso[1]
    fx = np.fft.fftfreq(N)[None, :] * N * aniso[0]
    r = np.sqrt(fx * fx + fy * fy)
    band = np.exp(-((np.log(np.maximum(r, 1e-6)) - np.log(np.sqrt(lo * hi))) ** 2) / (2 * (np.log(hi / lo) / 2.5) ** 2))
    band[0, 0] = 0
    out = np.real(np.fft.ifft2(F * band))
    return out / (np.abs(out).max() + 1e-9)


def normal_map(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / 2
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) / 2   # image rows run down; +Y is up
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).round().clip(0, 255).astype(np.uint8)


def gray(a):
    return (np.clip(a, 0, 1) * 255).round().astype(np.uint8)


def worley(count, seed):
    """Tileable cellular distance (F1) for pebbled grain."""
    r = np.random.default_rng(seed)
    pts = r.random((count, 2)) * N
    d = np.full((N, N), 1e9)
    for py, px in pts:
        dy = np.abs(Y - py); dy = np.minimum(dy, N - dy)
        dx = np.abs(X - px); dx = np.minimum(dx, N - dx)
        d = np.minimum(d, np.sqrt(dx * dx + dy * dy))
    return d / d.max()


SETS: dict[str, dict[str, np.ndarray]] = {}


def nylon():
    # glossy shell: fine ripstop grid, weave, soft wrinkles
    grid = ((np.minimum(X % 32, 32 - X % 32) < 1.2) | (np.minimum(Y % 32, 32 - Y % 32) < 1.2)).astype(float)
    weave = 0.5 + 0.5 * np.sin(X * np.pi / 2) * np.sin(Y * np.pi / 2)
    wrinkle = fnoise(2, 6, (1.0, 0.6))
    h = 0.35 * grid + 0.08 * weave + 0.9 * wrinkle
    return {"color": gray(0.9 + 0.05 * wrinkle - 0.04 * grid),
            "normal": normal_map(h, 5.0),
            "roughness": gray(0.3 + 0.08 * wrinkle + 0.1 * grid)}


def fleece():
    # heathered cotton fleece with a faint twill
    fib = fnoise(60, 200)
    twill = np.sin((X + Y) * 2 * np.pi / 8)
    h = 0.6 * fib + 0.25 * twill + 0.4 * fnoise(3, 8)
    return {"color": gray(0.86 + 0.07 * fnoise(80, 220) + 0.03 * twill),
            "normal": normal_map(h, 9.0),
            "roughness": gray(0.86 + 0.06 * fib)}


def knit():
    # 1x1 rib: raised wales with V-shaped stitches
    wale = np.abs(np.sin(X * np.pi / 16))
    vee = np.abs(np.sin((Y + np.abs((X % 16) - 8)) * np.pi / 8))
    h = 0.8 * wale + 0.35 * wale * vee + 0.15 * fnoise(40, 120)
    return {"color": gray(0.78 + 0.16 * wale * (0.7 + 0.3 * vee)),
            "normal": normal_map(h, 4.0),
            "roughness": gray(0.9 + 0.05 * (1 - wale))}


def leather():
    # pebbled grain: cellular bumps, slightly glossier tops
    cells = worley(420, 11)
    bump = 1 - np.clip(cells * 3.2, 0, 1)
    h = 0.7 * bump + 0.2 * fnoise(40, 160)
    return {"color": gray(0.9 + 0.05 * bump + 0.02 * fnoise(4, 12)),
            "normal": normal_map(h, 3.0),
            "roughness": gray(0.58 - 0.14 * bump)}


def rubber():
    # cupsole rubber: fine stipple and moulded horizontal ridges
    ridge = np.abs(np.sin(Y * np.pi / 12)) ** 3
    h = 0.5 * ridge + 0.35 * fnoise(80, 240)
    return {"color": gray(0.93 + 0.03 * fnoise(60, 200)),
            "normal": normal_map(h, 3.0),
            "roughness": gray(0.72 + 0.12 * fnoise(30, 90))}


def pave():
    # pave-set brilliant stones on a hex grid with metal between them
    pitch = N / 16.0
    rowh = pitch * np.sqrt(3) / 2
    rows = int(round(N / rowh))
    rowh = N / rows
    best = np.full((N, N), 1e9); ang = np.zeros((N, N)); seed = np.zeros((N, N))
    rr = np.random.default_rng(3)
    for j in range(-1, rows + 1):
        off = (pitch / 2) * (j % 2)
        for i in range(-1, 17):
            cy, cx = j * rowh, i * pitch + off
            dy = Y - cy; dy = (dy + N / 2) % N - N / 2
            dx = X - cx; dx = (dx + N / 2) % N - N / 2
            d = np.sqrt(dx * dx + dy * dy)
            m = d < best
            best = np.where(m, d, best)
            ang = np.where(m, np.arctan2(dy, dx), ang)
            seed = np.where(m, rr.random(), seed)
    R = pitch * 0.44
    stone = best < R
    t = np.clip(best / R, 0, 1)
    # eight-facet crown: a cone broken into facets, table on top
    fac = np.cos((ang * 8 / (2 * np.pi) % 1 - 0.5) * np.pi) * 0.15
    h = np.where(stone, np.where(t < 0.45, 1.0, 1.0 - (t - 0.45) * 1.6 + fac * t), 0.25)
    sparkle = 0.5 + 0.5 * np.cos(ang * 8 + seed * 12)
    col = np.where(stone, 0.86 + 0.14 * sparkle * (t > 0.3), 0.72)
    prong = (~stone) & (best < R * 1.18)
    return {"color": gray(col),
            "normal": normal_map(h, 9.0),
            "roughness": gray(np.where(stone, 0.03 + 0.04 * (1 - sparkle), np.where(prong, 0.18, 0.3))),
            "metalness": gray(np.where(stone, 0.82, 1.0))}


def metal():
    # polished silver with fine directional brushing and a few scratches
    brush = fnoise(30, 220, (0.08, 1.0))
    scratch = (fnoise(20, 60, (1.0, 0.15)) > 0.45).astype(float)
    h = 0.5 * brush + 0.3 * scratch
    return {"color": gray(0.93 + 0.04 * brush),
            "normal": normal_map(h, 6.0),
            "roughness": gray(0.16 + 0.07 * brush + 0.12 * scratch),
            "metalness": gray(0.97 - 0.06 * scratch)}


def locs():
    # matted loc fibre: coiled bumps plus fly-away fibres
    coil = fnoise(10, 40)
    fibre = fnoise(60, 200, (1.0, 0.3))
    h = 0.7 * coil + 0.4 * fibre
    return {"color": gray(0.78 + 0.15 * coil + 0.07 * fibre),
            "normal": normal_map(h, 4.0),
            "roughness": gray(0.68 + 0.1 * fibre)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("nylon", nylon), ("fleece", fleece), ("knit", knit), ("leather", leather),
                     ("rubber", rubber), ("pave", pave), ("metal", metal), ("locs", locs)):
        SETS[name] = fn()
    tiles = []
    for name, maps in SETS.items():
        for kind, arr in maps.items():
            assert arr.std() > 0.5, f"{name}_{kind} is flat"
            Image.fromarray(arr).save(OUT / f"{name}_{kind}.png", optimize=True)
            tiles.append(Image.fromarray(arr).convert("RGB").resize((128, 128)))
        print(f"{name:8s} " + ", ".join(maps))
    cols = 8
    sheet = Image.new("RGB", (128 * cols, 128 * ((len(tiles) + cols - 1) // cols)), (20, 20, 24))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * 128, (i // cols) * 128))
    (ROOT / "build").mkdir(exist_ok=True)
    sheet.save(ROOT / "build" / "premium_textures.png")
    print(f"{len(tiles)} maps -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
