#!/usr/bin/env python3
"""주요 오브젝트용 텍스처 (자체 생성): 카세트 라벨 1~7, 손글씨 메모, 운송장(발신인 없음), 선반 카세트 인서트 아틀라스.
출력: game/assets/textures/props/*.png
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "textures" / "props"
OUT.mkdir(parents=True, exist_ok=True)
SANS = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
HAND = "/usr/share/fonts/opentype/noto/NotoSansCJK-Light.ttc"
SERIF = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc"
R = random.Random(28)


def font(path, size, idx=1):
    try:
        return ImageFont.truetype(path, size, index=idx)
    except OSError:
        return ImageFont.truetype(path, size)


def handwrite(img, xy, text, size, ink=(28, 32, 58), jitter=1.0, path=HAND, slant=-7):
    """글자마다 크기·기울기·기준선·굵기를 흔들어 손글씨처럼 쓴다 (필압 번짐 포함)."""
    x, y = xy
    for ch in text:
        if ch == " ":
            x += size * R.uniform(0.32, 0.42)
            continue
        s = int(size * R.uniform(0.9, 1.08))
        f = font(path, s)
        g = Image.new("L", (s * 2, s * 2), 0)
        d = ImageDraw.Draw(g)
        d.text((s * 0.3, s * 0.15), ch, font=f, fill=255)
        g = g.rotate(slant + R.uniform(-5, 5) * jitter, resample=Image.BICUBIC, expand=False)
        g = g.filter(ImageFilter.GaussianBlur(0.6))
        a = np.asarray(g).astype(np.float32) / 255.0 * R.uniform(0.82, 1.0)
        col = Image.new("RGBA", g.size, (*ink, 0))
        col.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
        img.alpha_composite(col, (int(x - s * 0.3), int(y + R.uniform(-5, 5) * jitter - s * 0.15)))
        bb = f.getbbox(ch)
        x += (bb[2] - bb[0]) + s * R.uniform(0.04, 0.12)
    return x


def paper_bg(w, h, base=(236, 232, 220), lines=None, aged=0.0):
    a = np.ones((h, w, 3)) * np.array(base, dtype=np.float32)
    rng = np.random.default_rng(R.randint(0, 9999))
    a += rng.normal(0, 3.0, (h, w, 1))
    yy, xx = np.mgrid[0:h, 0:w]
    a *= (1 - aged * (((xx - w / 2) / w) ** 2 + ((yy - h / 2) / h) ** 2))[..., None]
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")
    if lines:
        d = ImageDraw.Draw(img)
        for ly in range(lines[0], h, lines[1]):
            d.line([(0, ly), (w, ly)], fill=(170, 190, 210, 255), width=2)
    return img


def tape_labels():
    """테이프 7개 라벨 — 같은 사람이 쓴 숫자. A/B면 표시. 일곱 번째는 B면 칸이 비어 있음."""
    for n in range(1, 8):
        W, H = 1024, 512
        img = paper_bg(W, H, (238, 233, 214), aged=0.25)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, W, 70], fill=(196, 72, 48, 255))
        d.rectangle([0, 70, W, 78], fill=(60, 50, 45, 255))
        d.text((30, 14), "C-60", font=font(SANS, 40), fill=(250, 240, 230, 255))
        d.text((W - 150, 14), "A", font=font(SANS, 44), fill=(250, 240, 230, 255))
        for ly in (190, 290, 390):
            d.line([(40, ly), (W - 40, ly)], fill=(160, 150, 140, 255), width=2)
        handwrite(img, (70, 110), f"{n}", 120, jitter=1.4)
        img = img.filter(ImageFilter.GaussianBlur(0.4))
        img.convert("RGB").save(OUT / f"prop_tape_label_{n}.png")


def memo():
    W, H = 900, 1300
    img = paper_bg(W, H, (241, 238, 228), lines=(170, 92), aged=0.15)
    y = 190
    for line in ["잡음을 제거하지", "말아 주세요.", "", "그 안에", "목소리가 있습니다."]:
        if line:
            handwrite(img, (70, y - 70), line, 62, jitter=1.2)
        y += 184
    # 접힌 자국
    d = ImageDraw.Draw(img)
    d.line([(0, H // 2), (W, H // 2 + 6)], fill=(205, 200, 190, 255), width=3)
    img.convert("RGB").save(OUT / "prop_memo.png")


def waybill():
    """운송장 — 보내는 분 칸이 비어 있다. 실존 택배사 로고·서식 사용하지 않음."""
    W, H = 1024, 640
    img = paper_bg(W, H, (246, 246, 242))
    d = ImageDraw.Draw(img)
    f, fb = font(SANS, 30), font(SANS, 34)
    d.rectangle([10, 10, W - 10, H - 10], outline=(40, 40, 40, 255), width=3)
    d.text((30, 24), "택배 운송장", font=font(SANS, 44), fill=(30, 30, 30, 255))
    rng = np.random.default_rng(3)
    x = 520
    for i in range(70):
        w = int(rng.integers(2, 6))
        if rng.random() > 0.4:
            d.rectangle([x, 28, x + w, 100], fill=(20, 20, 20, 255))
        x += w + 2
    d.line([(10, 120), (W - 10, 120)], fill=(40, 40, 40, 255), width=2)
    d.text((30, 140), "받는 분", font=fb, fill=(30, 30, 30, 255))
    d.text((200, 140), "서정우 님", font=fb, fill=(20, 20, 20, 255))
    d.text((200, 190), "○○시 ○○구 ○○로 ○○, ○○상가 3층 304호", font=f, fill=(40, 40, 40, 255))
    d.line([(10, 250), (W - 10, 250)], fill=(40, 40, 40, 255), width=2)
    d.text((30, 270), "보내는 분", font=fb, fill=(30, 30, 30, 255))
    d.text((200, 270), "", font=fb, fill=(20, 20, 20, 255))
    d.line([(10, 340), (W - 10, 340)], fill=(40, 40, 40, 255), width=2)
    d.text((30, 360), "품명", font=fb, fill=(30, 30, 30, 255))
    d.text((200, 360), "", font=f, fill=(40, 40, 40, 255))
    d.text((30, 440), "중량 1kg 미만    수량 1", font=f, fill=(60, 60, 60, 255))
    d.text((30, 560), "※ 취급 주의", font=f, fill=(150, 40, 30, 255))
    # 빗물 얼룩
    a = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    for _ in range(3):
        cx, cy, r = rng.integers(0, W), rng.integers(0, H), rng.integers(40, 110)
        m = np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / r ** 2)) * 0.08
        a[..., :3] *= (1 - m)[..., None]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGB").save(OUT / "prop_waybill.png")


def insert_atlas():
    """선반 카세트 등(spine) 아틀라스 8칸 — 512x128 한 칸. 가로 = 등 길이 방향.
    실제 테이프 선반처럼 어두운 케이스·인쇄 띠·손글씨 라벨이 섞이게."""
    designs = [((24, 24, 26), (200, 60, 45), "인터뷰 1"), ((236, 230, 214), (40, 70, 140), "녹취 0412"),
               ((30, 44, 78), (230, 200, 90), "현장음 A"), ((150, 40, 32), (240, 236, 226), "재판 녹취"),
               ((210, 205, 190), (60, 60, 60), "가족 테이프"), ((40, 72, 52), (236, 226, 200), "라디오 97"),
               ((92, 64, 44), (236, 220, 190), "의뢰 #212"), ((60, 60, 64), (210, 120, 50), "원본-보관")]
    atlas = Image.new("RGB", (512, 128 * 8))
    for i, (bg, band, text) in enumerate(designs):
        cell = Image.new("RGBA", (512, 128), (*bg, 255))
        d = ImageDraw.Draw(cell)
        d.rectangle([0, 0, 46, 128], fill=(*band, 255))
        d.rectangle([466, 0, 512, 128], fill=(*band, 255))
        lab = (242, 238, 226) if sum(bg) < 300 else bg
        if sum(bg) < 300:
            d.rectangle([70, 22, 440, 106], fill=(*lab, 255))
        handwrite(cell, (90, 30), text, 56, ink=(26, 30, 60) if sum(lab) > 400 else (240, 240, 240), jitter=1.0)
        atlas.paste(cell.convert("RGB"), (0, i * 128))
    atlas.save(OUT / "prop_cassette_spine_atlas.png")


if __name__ == "__main__":
    tape_labels()
    memo()
    waybill()
    insert_atlas()
    print("->", OUT)
