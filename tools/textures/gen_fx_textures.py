#!/usr/bin/env python3
"""효과용 텍스처: 손전등 빛 패턴(프로젝터) — 중앙 핫스폿 + 반사판 링 + 부드러운 감쇠 (REF 21)."""
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "textures" / "fx"
OUT.mkdir(parents=True, exist_ok=True)
N = 512
y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
r = np.sqrt(x ** 2 + y ** 2)
rng = np.random.default_rng(21)
hot = np.exp(-(r / 0.22) ** 2) * 1.0
body = np.clip(1 - (r / 0.95) ** 2.2, 0, 1) * 0.55
ring = np.exp(-((r - 0.5) / 0.05) ** 2) * 0.12 + np.exp(-((r - 0.78) / 0.04) ** 2) * 0.08
dark_ring = -np.exp(-((r - 0.35) / 0.03) ** 2) * 0.08          # 반사판 이음 자국
th = np.arctan2(y, x)
streak = 1 + 0.04 * np.sin(th * 9 + rng.uniform(0, 6)) * (r > 0.3)
img = np.clip((hot + body + ring + dark_ring) * streak, 0, 1) * (r < 1.0)
img = img / img.max()
rgb = np.stack([img, img * 0.97, img * 0.9], -1)
Image.fromarray((rgb * 255).astype(np.uint8)).save(OUT / "flashlight_cookie.png")
print("->", OUT / "flashlight_cookie.png")
