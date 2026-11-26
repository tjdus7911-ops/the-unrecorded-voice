#!/usr/bin/env python3
"""타일링 PBR 텍스처 생성기 — The Unrecorded Voice (외부 이미지 사용 없음, 전부 자체 생성)

주기적(FFT) fBm 노이즈로 이음매 없는 텍스처를 만든다.
출력: game/assets/textures/pbr/<name>_albedo.jpg / _orm.jpg (R=AO G=Roughness B=Metal) / _normal.jpg (OpenGL +Y)
      game/assets/textures/decals/<name>.png (알파 데칼)
      game/assets/textures/pbr/materials.json  (타일 크기 m, 기타 속성) — Blender·Godot 공용
usage: python3 tools/textures/gen_pbr.py [--size 1024]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "textures" / "pbr"
DEC = ROOT / "game" / "assets" / "textures" / "decals"
OUT.mkdir(parents=True, exist_ok=True)
DEC.mkdir(parents=True, exist_ok=True)
N = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 1024
RNG = np.random.default_rng(1998)
META = {}


# ------------------------------------------------------------------ noise
def fbm(n=None, beta=2.0, seed=None, aniso=(1.0, 1.0), lo=1.0):
    """주기적 fBm: 1/f^beta 스펙트럼. aniso=(sx, sy) >1 이면 그 축으로 늘어남."""
    n = n or N
    r = np.random.default_rng(seed if seed is not None else RNG.integers(1 << 30))
    w = r.standard_normal((n, n))
    fx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    fy = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1.0
    spec = np.fft.fft2(w) / np.maximum(f, lo) ** (beta / 2.0)
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out = (out - out.mean()) / (out.std() + 1e-9)
    return out


def norm01(a):
    return (a - a.min()) / (a.max() - a.min() + 1e-9)


def normal_from_height(h, strength):
    # 높이(표준편차 ~1 단위)를 실제 미세 요철 수준으로 축소 — 작은 물체에서 망치 자국처럼 보이지 않도록
    k = 0.045 * strength * (N / 1024.0)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * k
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * k
    nz = np.ones_like(h)
    # OpenGL(+Y up) 규약: 이미지 행이 아래로 증가하므로 dy 부호 반전
    n = np.stack([-dx, dy, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(name, albedo, rough, metal=0.0, height=None, nstr=1.0, ao=None, tile=(1.0, 1.0), **extra):
    a = np.clip(albedo, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(OUT / f"{name}_albedo.jpg", quality=92)
    r = np.clip(rough, 0.02, 1) * np.ones(a.shape[:2])
    m = np.clip(metal, 0, 1) * np.ones(a.shape[:2])
    o = np.ones(a.shape[:2]) if ao is None else np.clip(ao, 0, 1)
    orm = np.stack([o, r, m], -1)
    Image.fromarray((orm * 255).astype(np.uint8)).save(OUT / f"{name}_orm.jpg", quality=93)
    if height is not None:
        nm = normal_from_height(height, nstr)
        Image.fromarray((nm * 255).astype(np.uint8)).save(OUT / f"{name}_normal.jpg", quality=94)
    META[name] = {"tile_m": list(tile), "normal": height is not None, **extra}
    print(f"  {name}")


def tint(base, var, amount):
    base = np.array(base)[None, None, :]
    return base * (1.0 + amount * var[..., None])


def lerp(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return np.array(a) * (1 - t) + np.array(b) * t


# ------------------------------------------------------------------ materials
def wall_paint(name="wall_paint", base=(0.80, 0.78, 0.73), tile=2.0):
    low = fbm(beta=3.2)
    mid = fbm(beta=2.0)
    stip = fbm(beta=0.6)
    alb = tint(base, low * 0.6 + mid * 0.3, 0.035)
    rough = 0.86 + 0.04 * mid
    save(name, alb, rough, 0, stip * 0.6 + mid * 0.2, 2.0, tile=(tile, tile))


def planks(name, c0, c1, tile=2.4, rows=12, per_row=2, grain_stretch=14, gap=0.0015, rough=(0.38, 0.58), nstr=4.0,
           size=None):
    n = size or N
    grain = fbm(n, 2.2, aniso=(grain_stretch, 1.0))
    fine = fbm(n, 1.0, aniso=(30.0, 1.0))
    alb = np.zeros((n, n, 3))
    h = np.zeros((n, n))
    rowh = n // rows
    pl = n // per_row
    plank_id = np.zeros((n, n))
    gp = max(1, int(gap / tile * n))
    for r in range(rows):
        off = RNG.integers(0, pl)
        ys = slice(r * rowh, (r + 1) * rowh)
        for p in range(per_row + 1):
            x0 = (off + p * pl) % n
            cols = (np.arange(pl) + x0) % n
            t = RNG.uniform(0.2, 0.8)
            col = lerp(c0, c1, np.full((rowh, pl), t))
            shift = RNG.integers(0, n)
            g = np.roll(grain, shift, 1)[ys][:, cols]
            fn = np.roll(fine, shift, 0)[ys][:, cols]
            alb[ys, cols] = col * (1 + 0.13 * g[..., None] + 0.05 * fn[..., None])
            plank_id[ys, cols] = r * 10 + p
            h[ys, cols] = 0.15 * fn
        # 행 이음
        h[r * rowh:r * rowh + gp, :] = -1.0
        alb[r * rowh:r * rowh + gp, :] *= 0.35
    # 판 끝 이음 (세로 홈)
    edges = np.abs(np.diff(plank_id, axis=1, append=plank_id[:, :1])) > 0
    for k in range(gp):
        e = np.roll(edges, k, 1)
        h[e] = -1.0
        alb[e] *= 0.4
    wear = norm01(fbm(n, 3.5))
    r = rough[0] + (rough[1] - rough[0]) * wear
    alb *= (1 - 0.06 * (wear - 0.5))[..., None]
    save(name, alb, r, 0, h, nstr, tile=(tile, tile))


def wood_veneer(name, c0, c1, tile=1.0, rough=0.45):
    g = fbm(beta=2.4, aniso=(18, 1))
    rings = np.sin(norm01(fbm(beta=3.5, aniso=(10, 1))) * 40) * 0.5 + 0.5
    t = norm01(g * 0.7 + rings * 0.6)
    alb = lerp(c0, c1, t)
    fine = fbm(beta=0.8, aniso=(40, 1))
    save(name, alb * (1 + 0.04 * fine[..., None]), rough + 0.08 * fine, 0, fine * 0.3 + g * 0.1, 1.5, tile=(tile, tile))


def ceiling_tex(name="ceiling_tex", tile=1.2):
    n = N
    alb = np.ones((n, n, 3)) * np.array([0.80, 0.79, 0.76])
    h = np.zeros((n, n))
    # 텍스 패널 2x2 + T바
    half = n // 2
    bar = max(2, int(0.016 / tile * n))
    for i in range(2):
        for j in range(2):
            alb[i * half:(i + 1) * half, j * half:(j + 1) * half] *= RNG.uniform(0.96, 1.01)
    pores = RNG.random((n, n)) < 0.018
    pores = Image.fromarray((pores * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    pores = np.asarray(pores) / 255.0
    fiss = norm01(fbm(beta=1.4, aniso=(1, 6))) > 0.82   # 텍스 특유의 균열 무늬
    h -= pores * 0.8 + fiss * 0.5
    alb *= (1 - 0.18 * pores[..., None] - 0.06 * fiss[..., None])
    rough = np.full((n, n), 0.93)
    metal = np.zeros((n, n))
    for k in (0, half):
        alb[k:k + bar, :] = [0.86, 0.86, 0.85]
        alb[:, k:k + bar] = [0.86, 0.86, 0.85]
        h[k:k + bar, :] = 0.6
        h[:, k:k + bar] = 0.6
        rough[k:k + bar, :] = 0.45
        rough[:, k:k + bar] = 0.45
        metal[k:k + bar, :] = 0.6
        metal[:, k:k + bar] = 0.6
    alb *= (1 + 0.03 * fbm(beta=3)[..., None])
    save(name, alb, rough, metal, h, 3.0, tile=(tile, tile))


def fabric(name, color, tile=0.5, weave=160, rough=0.95, pattern="plain"):
    n = N
    y, x = np.mgrid[0:n, 0:n] / n * weave * 2 * np.pi
    if pattern == "plain":
        wv = np.sin(x) * np.sign(np.sin(y / 2)) * 0.5 + np.sin(y) * np.sign(np.sin(x / 2)) * 0.5
    elif pattern == "mesh":
        wv = -((np.cos(x) * np.cos(y)) > 0.55).astype(float)
    elif pattern == "loop":
        wv = np.sin(x) * np.sin(y)
    else:
        wv = np.sin(x * 0.5 + y * 0.5)
    fz = fbm(beta=1.0)
    var = fbm(beta=3.0)
    alb = tint(color, var * 0.25 + 0.3 * wv, 0.12)
    if pattern == "mesh":
        alb *= (1 + 0.6 * wv[..., None])
    save(name, alb, rough - 0.05 * wv, 0, wv * 0.6 + fz * 0.2, 2.5, tile=(tile, tile), sheen=True)


def painted_metal(name, color, rough=0.45, metal=0.0, tile=1.0, peel=0.25, scratches=0.0):
    op = fbm(beta=1.2)
    var = fbm(beta=3.0)
    alb = tint(color, var * 0.6, 0.06)
    r = rough + 0.06 * var
    m = np.full((N, N), metal)
    if scratches:
        s = norm01(fbm(beta=1.6, aniso=(25, 1))) > (1 - scratches)
        alb[s] = np.array([0.55, 0.55, 0.55])
        m[s] = 1.0
        r[s] = 0.35
    save(name, alb, r, m, op * peel, 1.5, tile=(tile, tile))


def brushed(name, color, rough=0.32, tile=0.5):
    s = fbm(beta=1.0, aniso=(60, 1))
    alb = tint(color, s, 0.05)
    save(name, alb, rough + 0.06 * s, 1.0, s * 0.15, 1.0, tile=(tile, tile))


def plastic(name, color, rough=0.45, tile=0.5):
    tex = fbm(beta=0.9)
    sc = norm01(fbm(beta=1.6, aniso=(1, 20))) > 0.93
    var = fbm(beta=3)
    alb = tint(color, var * 0.4, 0.08)
    alb[sc] *= 1.35
    r = rough + 0.05 * tex
    r[sc] = rough + 0.15
    save(name, alb, r, 0, tex * 0.25, 1.0, tile=(tile, tile))


def simple(name, color, rough, metal=0.0, tile=1.0, var=0.06, h=0.2, beta=1.0, **kw):
    v = fbm(beta=2.8)
    t = fbm(beta=beta)
    alb = tint(color, v, var)
    save(name, alb, rough + 0.06 * v, metal, t * h, 1.5, tile=(tile, tile), **kw)


def ceramic_tiles(name, color, tile=1.2, count=4, grout=(0.22, 0.20, 0.18), glaze=0.25):
    n = N
    cell = n // count
    gw = max(2, int(0.004 / tile * n))
    alb = np.zeros((n, n, 3))
    h = np.zeros((n, n))
    speck = fbm(beta=0.3)
    for i in range(count):
        for j in range(count):
            c = np.array(color) * RNG.uniform(0.9, 1.08)
            alb[i * cell:(i + 1) * cell, j * cell:(j + 1) * cell] = c
    alb *= (1 + 0.08 * speck[..., None] + 0.05 * fbm(beta=2.5)[..., None])
    r = np.full((n, n), glaze) + 0.1 * norm01(fbm(beta=3.0))
    for k in range(count):
        for g in range(gw):
            alb[k * cell + g, :] = grout
            alb[:, k * cell + g] = grout
            h[k * cell + g, :] = -1
            h[:, k * cell + g] = -1
            r[k * cell + g, :] = 0.9
            r[:, k * cell + g] = 0.9
    dirt = norm01(fbm(beta=3.2))
    alb *= (1 - 0.12 * dirt)[..., None]
    save(name, alb, r, 0, h + speck * 0.05, 3.0, tile=(tile, tile))


def terrazzo(name, base=(0.55, 0.53, 0.5), tile=1.0):
    n = N
    alb = tint(base, fbm(beta=2.5), 0.06)
    chips = np.zeros((n, n))
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    for _ in range(9000):
        x, y = RNG.integers(0, n, 2)
        rr = RNG.uniform(1, 6) * n / 1024
        d.ellipse([x - rr, y - rr * RNG.uniform(0.6, 1.2), x + rr, y + rr], fill=int(RNG.uniform(60, 255)))
    chips = np.asarray(img) / 255.0
    alb = alb * (1 - chips[..., None] * 0.5) + chips[..., None] * np.array([0.25, 0.24, 0.22]) * (chips[..., None] > 0.6)
    save(name, alb, 0.35 + 0.2 * norm01(fbm(beta=3)), 0, chips * 0.1, 1.0, tile=(tile, tile))


def concrete(name, base=(0.45, 0.44, 0.42), tile=2.0, rough=0.85):
    a = fbm(beta=2.6)
    b = fbm(beta=1.2)
    pits = RNG.random((N, N)) < 0.004
    alb = tint(base, a * 0.7 + b * 0.2, 0.12)
    alb[pits] *= 0.5
    h = b * 0.3 - pits * 1.0
    save(name, alb, rough + 0.05 * a, 0, h, 2.0, tile=(tile, tile))


def cardboard(name="cardboard", tile=0.6):
    fib = fbm(beta=1.0, aniso=(1, 4))
    var = fbm(beta=3)
    alb = tint((0.50, 0.37, 0.24), var * 0.6 + fib * 0.2, 0.08)
    save(name, alb, 0.9, 0, fib * 0.3, 1.2, tile=(tile, tile))


def foam(name="acoustic_foam", tile=0.3):
    cells = fbm(beta=0.2)
    alb = tint((0.055, 0.06, 0.065), cells, 0.25)
    save(name, alb, 0.98, 0, cells * 0.6, 4.0, tile=(tile, tile))


# ------------------------------------------------------------------ decals (alpha)
def decal(name, fn, size=512):
    a = fn(size)
    Image.fromarray(a).save(DEC / f"{name}.png")
    print("  decal", name)


def dirt_strip(s):
    """걸레받이 위 벽 하단 오염 — 위로 갈수록 옅어짐. 가로로 타일링."""
    n = s
    v = norm01(fbm(n, 2.4, aniso=(4, 1)))
    yy = np.linspace(1, 0, n)[:, None]
    a = np.clip((yy ** 2.2) * (0.35 + 0.65 * v) * 0.75, 0, 1)
    rgb = np.ones((n, n, 3)) * np.array([60, 52, 44])
    return np.dstack([rgb, a * 255]).astype(np.uint8)


def hand_smudge(s):
    n = s
    yy, xx = np.mgrid[0:n, 0:n] / n
    a = np.zeros((n, n))
    for _ in range(9):
        cx, cy = RNG.uniform(0.3, 0.7), RNG.uniform(0.3, 0.7)
        rx, ry = RNG.uniform(0.04, 0.12), RNG.uniform(0.06, 0.16)
        a += np.exp(-(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)) * RNG.uniform(0.2, 0.5)
    a *= 0.6 + 0.4 * norm01(fbm(n, 1.4))
    a = np.clip(a, 0, 0.7)
    rgb = np.ones((n, n, 3)) * np.array([70, 60, 50])
    return np.dstack([rgb, a * 255]).astype(np.uint8)


def water_stain(s):
    n = s
    yy, xx = np.mgrid[0:n, 0:n] / n - 0.5
    rr = np.sqrt(xx ** 2 + yy ** 2) + 0.05 * fbm(n, 2.5)
    ring = np.exp(-((rr - 0.33) / 0.02) ** 2) * 0.7 + np.clip(0.33 - rr, 0, 1) * 0.6
    ring += np.exp(-((rr - 0.22) / 0.015) ** 2) * 0.35
    a = np.clip(ring * (rr < 0.45), 0, 0.8)
    rgb = np.ones((n, n, 3)) * np.array([120, 95, 60])
    return np.dstack([rgb, a * 255]).astype(np.uint8)


def floor_scuff(s):
    n = s
    a = norm01(fbm(n, 1.8, aniso=(8, 1)))
    a = np.clip((a - 0.6) * 1.5, 0, 0.5)
    yy, xx = np.mgrid[0:n, 0:n] / n - 0.5
    a *= np.clip(1 - (xx ** 2 + yy ** 2) * 4, 0, 1)
    rgb = np.ones((n, n, 3)) * np.array([25, 22, 20])
    return np.dstack([rgb, a * 255]).astype(np.uint8)


def tape_residue(s):
    n = s
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(4):
        x, y = RNG.integers(n // 5, 4 * n // 5, 2)
        w, h = RNG.integers(n // 8, n // 4), RNG.integers(n // 25, n // 15)
        d.rectangle([x, y, x + w, y + h], fill=(180, 170, 140, 70))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(1.5)))


def main():
    print("PBR textures:", N)
    wall_paint()
    wall_paint("wall_paint_ivory", (0.83, 0.79, 0.66), 2.0)                       # 상가 복도 아이보리
    planks("floor_decotile", (0.30, 0.20, 0.12), (0.48, 0.34, 0.21), size=2048)    # 우드 데코타일
    wood_veneer("walnut_veneer", (0.14, 0.085, 0.05), (0.30, 0.19, 0.11))
    wood_veneer("oak_laminate", (0.42, 0.30, 0.19), (0.60, 0.46, 0.31), rough=0.5)
    ceiling_tex()
    simple("melamine_offwhite", (0.74, 0.72, 0.68), 0.55, tile=1.0, var=0.03, h=0.05)
    fabric("sofa_fabric", (0.17, 0.19, 0.17), 0.3, 140)
    fabric("chair_mesh", (0.03, 0.03, 0.035), 0.15, 90, 0.75, "mesh")
    fabric("rug_wool", (0.26, 0.21, 0.17), 0.6, 120, 1.0, "loop")
    fabric("blanket_flannel", (0.42, 0.34, 0.26), 0.4, 60, 0.98, "twill")
    fabric("lampshade_linen", (0.80, 0.74, 0.62), 0.3, 120, 0.9)
    foam()
    brushed("brushed_aluminium", (0.66, 0.67, 0.68), 0.33)
    brushed("brushed_steel", (0.62, 0.62, 0.61), 0.28)
    brushed("anodized_dark", (0.12, 0.12, 0.13), 0.42)
    brushed("silver_faceplate", (0.70, 0.70, 0.68), 0.3, tile=0.3)
    painted_metal("powdercoat_black", (0.035, 0.035, 0.038), 0.5, 0.0, 0.5, 0.35, scratches=0.02)
    painted_metal("steel_door_paint", (0.46, 0.47, 0.46), 0.42, 0.0, 1.0, 0.3, scratches=0.03)
    painted_metal("steel_door_paint_green", (0.16, 0.30, 0.22), 0.45, 0.0, 1.0, 0.3, scratches=0.04)
    painted_metal("fire_red_paint", (0.55, 0.05, 0.04), 0.35, 0.0, 0.5, 0.2, scratches=0.02)
    plastic("abs_charcoal", (0.05, 0.05, 0.055), 0.45)
    plastic("abs_grey", (0.30, 0.30, 0.31), 0.48)
    plastic("abs_white", (0.82, 0.81, 0.78), 0.4)
    simple("paper", (0.88, 0.87, 0.82), 0.85, tile=0.3, var=0.03, h=0.1, beta=0.5)
    cardboard()
    simple("ceramic_glaze", (0.82, 0.80, 0.76), 0.18, tile=0.3, var=0.02, h=0.02)
    simple("rubber_black", (0.02, 0.02, 0.02), 0.82, tile=0.3, var=0.1, h=0.3, beta=0.6)
    simple("sill_stone", (0.62, 0.60, 0.56), 0.32, tile=0.8, var=0.1, h=0.03)
    simple("baseboard_pvc", (0.16, 0.15, 0.14), 0.5, tile=0.5, var=0.05, h=0.05)
    simple("leaf", (0.12, 0.20, 0.08), 0.55, tile=0.2, var=0.2, h=0.1)
    simple("soil", (0.08, 0.06, 0.04), 0.95, tile=0.2, var=0.3, h=0.6, beta=0.4)
    ceramic_tiles("corridor_floor_tile", (0.36, 0.27, 0.20), tile=1.2, count=4)
    ceramic_tiles("wall_tile_white", (0.84, 0.84, 0.82), tile=0.6, count=3, grout=(0.6, 0.6, 0.58), glaze=0.12)
    terrazzo("stair_terrazzo")
    concrete("concrete_wet", (0.10, 0.105, 0.11), 3.0, 0.35)
    concrete("concrete_paint", (0.62, 0.62, 0.6), 2.0, 0.8)
    print("decals:")
    decal("dirt_wall_bottom", dirt_strip)
    decal("smudge_hands", hand_smudge)
    decal("ceiling_water_stain", water_stain)
    decal("floor_scuff", floor_scuff)
    decal("tape_residue", tape_residue)
    (OUT / "materials.json").write_text(json.dumps(META, indent=1), "utf-8")
    print("->", OUT)


if __name__ == "__main__":
    main()
