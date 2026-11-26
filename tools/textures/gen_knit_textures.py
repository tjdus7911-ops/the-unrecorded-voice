"""서정우 카디건 소매용 니트 텍스처 (타일링, 원본 제작).

- chr_knit_*  : 메리야스(저지) 뜨기 — V자 코 (한 타일 = 5 cm, 코 12 x 행 15)
- chr_rib_*   : 2x2 고무단 (소맷부리) — 세로 골 (한 타일 = 5 cm)
출력: game/assets/textures/chr/<name>_{albedo,orm,normal}.png
usage: python3 tools/textures/gen_knit_textures.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/textures/chr"
N = 1024
rng = np.random.default_rng(37)


def fbm(beta=2.0, aniso=(1.0, 1.0), lo=2.0):
    """타일링 가능한 1/f^beta 잡음 (FFT)."""
    fy = np.fft.fftfreq(N)[:, None] * N / aniso[1]
    fx = np.fft.fftfreq(N)[None, :] * N / aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1
    amp = 1.0 / np.maximum(f, lo) ** (beta / 2.0)
    amp[0, 0] = 0
    ph = rng.uniform(0, 2 * np.pi, (N, N))
    h = np.real(np.fft.ifft2(amp * np.exp(1j * ph)))
    return (h - h.mean()) / (h.std() + 1e-9)


def normal_png(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)          # OpenGL(+Y) 규약
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(name, albedo, rough, height, nstr, ao):
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8)).save(OUT / f"{name}_albedo.png")
    orm = np.stack([np.clip(ao, 0, 1), np.clip(rough, 0, 1), np.zeros_like(rough)], -1)
    Image.fromarray((orm * 255).astype(np.uint8)).save(OUT / f"{name}_orm.png")
    Image.fromarray((normal_png(height, nstr) * 255).astype(np.uint8)).save(OUT / f"{name}_normal.png")
    print(" ", name)


def v_stitch(u, v):
    """한 코(셀 좌표 0..1) 안의 V자 두 갈래 높이. u: 가로, v: 세로(아래→위)."""
    h = np.zeros_like(u)
    for side in (-1, 1):
        # 각 갈래: 기울어진 타원 (실 한 가닥이 휘어 올라가는 모양)
        cx = 0.5 + side * 0.21
        a = -np.deg2rad(30) * side            # 위로 벌어지는 V (아래에서 두 갈래가 만남)
        x = (u - cx) * np.cos(a) + (v - 0.5) * np.sin(a)
        y = -(u - cx) * np.sin(a) + (v - 0.5) * np.cos(a)
        r = (x / 0.2) ** 2 + (y / 0.52) ** 2
        lobe = np.sqrt(np.clip(1 - r, 0, 1))
        # 실 꼬임(플라이) 결
        twist = 0.5 + 0.5 * np.sin((y * 26 + x * 9) * np.pi)
        h = np.maximum(h, lobe * (0.82 + 0.18 * twist))
    return h


def main():
    yy, xx = np.mgrid[0:N, 0:N] / N
    fuzz = fbm(beta=1.2, lo=60)
    heather = fbm(beta=2.4, lo=3)
    fiber = fbm(beta=1.0, aniso=(1.0, 6.0), lo=40)

    # ---- 메리야스 저지 (몸판·소매)
    cols, rows = 12, 15
    u = (xx * cols) % 1.0
    v = 1.0 - (yy * rows) % 1.0
    # 행마다 코가 약간씩 어긋나고 크기가 다름 — 손뜨개 같은 불균일 (공장 기계편물 수준으로 작게)
    jit = fbm(beta=2.8, lo=2) * 0.03
    h = v_stitch((u + jit) % 1.0, v)
    h = h + 0.10 * fuzz + 0.05 * fiber
    gap = np.clip(1 - h * 1.4, 0, 1)                         # 코 사이 그늘
    base = np.array([0.060, 0.061, 0.066])                   # 다크 그레이 (선형≈ sRGB 70)
    alb = base[None, None, :] * (0.88 + 0.12 * heather[..., None] * 0.6)
    # 섞인 밝은 섬유(헤더 그레이)
    fleck = np.clip(fbm(beta=0.6, lo=200) - 2.2, 0, 1)[..., None]
    alb = alb + fleck * 0.05
    alb = alb * (1 - 0.45 * gap[..., None])
    alb = alb ** (1 / 2.2)                                   # 선형 → sRGB 저장
    rough = 0.86 + 0.08 * gap + 0.03 * fuzz
    save("chr_knit", alb, rough, h * 6.0, 1.0, 1 - 0.35 * gap)

    # ---- 2x2 고무단 (소맷부리)
    ribs = 10                                                # 5 cm에 골 10개 (겉뜨기 2 + 안뜨기 2 반복)
    ph = (xx * ribs) % 1.0
    knit_col = ph < 0.5                                      # 겉뜨기 기둥(솟음) / 안뜨기(들어감)
    uu = (ph * 2) % 1.0
    vv = 1.0 - (yy * 18) % 1.0
    hk = v_stitch(uu, vv)
    purl = 0.35 * (0.5 + 0.5 * np.cos((yy * 18 * 2) * 2 * np.pi)) * np.sin(uu * np.pi)
    edge = np.clip(np.minimum(np.abs(ph - 0.0), np.minimum(np.abs(ph - 0.5), np.abs(ph - 1.0))) / 0.06, 0, 1)
    hr = np.where(knit_col, 0.55 + 0.45 * hk, 0.1 + purl)
    hr = hr * (0.35 + 0.65 * edge) + 0.25 * (1 - edge)      # 겉뜨기/안뜨기 경계를 둥글게
    hr = hr + 0.08 * fuzz
    gapr = np.clip(1 - hr * 1.2, 0, 1)
    albr = base[None, None, :] * 0.92 * (0.9 + 0.1 * heather[..., None]) * (1 - 0.5 * gapr[..., None])
    albr = albr + fleck * 0.04
    save("chr_rib", albr ** (1 / 2.2), 0.88 + 0.07 * gapr, hr * 7.0, 1.0, 1 - 0.4 * gapr)


if __name__ == "__main__":
    main()
