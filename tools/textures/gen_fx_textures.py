#!/usr/bin/env python3
"""효과용 텍스처: 손전등 빛 패턴(프로젝터).
요구사항 17 §09: 반사판 링(여러 겹의 하얀 원처럼 보이던 원인)을 없애고, 밝은 중심 → 가장자리로 매끄럽게 어두워지는 단일 빔.
가장자리는 smoothstep으로 부드럽게 0이 되어 경계선이 생기지 않는다. 아주 약한 불균일(렌즈 얼룩)만 남긴다."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "textures" / "fx"
OUT.mkdir(parents=True, exist_ok=True)
N = 512
y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
r = np.sqrt(x ** 2 + y ** 2)
rng = np.random.default_rng(21)
hot = np.exp(-(r / 0.30) ** 2) * 0.55                       # 밝은 중심 (넓고 부드럽게)
body = np.exp(-(r / 0.62) ** 2) * 0.45                       # 주변광 (가우시안 — 링 없음)
edge = 1 - np.clip((r - 0.70) / 0.30, 0, 1)                   # 바깥 30%에서 0으로
edge = edge * edge * (3 - 2 * edge)                           # smoothstep
blot = 1 + 0.03 * (rng.standard_normal((N, N)))
img = np.clip((hot + body) * edge, 0, 1)
im = Image.fromarray((img * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
img = np.asarray(im).astype(float) / 255 * np.asarray(Image.fromarray(np.clip(blot * 127, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(24))).astype(float) / 127
img = np.clip(img / img.max(), 0, 1)
rgb = np.stack([img, img * 0.98, img * 0.93], -1)
Image.fromarray((rgb * 255).astype(np.uint8)).save(OUT / "flashlight_cookie.png")
print("->", OUT / "flashlight_cookie.png")
