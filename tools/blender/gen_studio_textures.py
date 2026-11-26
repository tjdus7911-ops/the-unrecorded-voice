#!/usr/bin/env python3
"""작업실용 자체 제작 텍스처 생성 (외부 이미지 사용 없음).

- 모니터 화면: 음성 복원 소프트웨어 UI (파형·스펙트로그램) — 가상의 프로그램, 실존 제품 UI 복제 아님
- 벽시계 문자판, 카세트 인덱스 카드, 달력, 보관 상자 라벨
출력: art/textures_source/stu/*.png
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[2] / "art" / "textures_source" / "stu"
OUT.mkdir(parents=True, exist_ok=True)
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
R = random.Random(1998)


def font(size, bold=False):
    path = FONT.replace("Regular", "Bold") if bold else FONT
    try:
        return ImageFont.truetype(path, size, index=1)  # KR
    except OSError:
        return ImageFont.load_default()


def monitor_screen():
    W, H = 3440, 1440
    img = Image.new("RGB", (W, H), (22, 24, 27))
    d = ImageDraw.Draw(img)
    f = font(26)
    # 상단 메뉴바
    d.rectangle([0, 0, W, 46], fill=(34, 36, 40))
    x = 20
    for t in ["파일", "편집", "보기", "복원", "분석", "트랙", "도움말"]:
        d.text((x, 8), t, font=f, fill=(170, 172, 176))
        x += 110
    d.text((W - 640, 8), "VOICEREST  —  case_2026_1126.vrp", font=f, fill=(140, 142, 146))
    # 좌측 패널 (파일 목록)
    d.rectangle([0, 46, 420, H], fill=(28, 30, 34))
    d.text((20, 70), "소스", font=font(24, True), fill=(200, 200, 200))
    for i, t in enumerate(["interview_0412.wav", "tape_A_side1.wav", "tape_A_side2.wav",
                           "room_tone.wav", "ref_noise_print.wav", "export_v3.wav"]):
        y = 120 + i * 46
        if i == 1:
            d.rectangle([8, y - 6, 412, y + 34], fill=(52, 58, 66))
        d.text((24, y), t, font=f, fill=(185, 188, 192))
    # 파형 트랙 2개
    rng = np.random.default_rng(7)
    for tr in range(2):
        top = 110 + tr * 430
        d.rectangle([440, top, W - 20, top + 400], fill=(17, 19, 22), outline=(48, 50, 56))
        d.text((456, top + 8), f"CH{tr + 1}", font=f, fill=(120, 124, 130))
        mid = top + 200
        n = W - 480
        env = np.abs(np.convolve(rng.standard_normal(n), np.ones(120) / 120, "same")) * 6
        env *= 0.35 + 0.65 * (np.sin(np.linspace(0, 23, n)) ** 2)
        hiss = np.abs(rng.standard_normal(n)) * 0.06
        amp = np.clip(env + hiss, 0, 1) * 180
        col = (214, 192, 140) if tr == 0 else (150, 182, 196)
        for i in range(0, n, 2):
            a = amp[i] * (0.7 + 0.3 * rng.random())
            d.line([(460 + i, mid - a), (460 + i, mid + a)], fill=col)
        d.line([(460, mid), (W - 20, mid)], fill=(70, 72, 76))
    # 선택 영역
    sel = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sel)
    ds.rectangle([1860, 110, 2240, 940], fill=(120, 150, 180, 40))
    img = Image.alpha_composite(img.convert("RGBA"), sel).convert("RGB")
    d = ImageDraw.Draw(img)
    # 스펙트로그램
    top = 980
    spec = np.zeros((420, W - 480))
    for k in range(420):
        spec[k] = np.clip(np.abs(np.convolve(rng.standard_normal(W - 480), np.ones(30) / 30, "same")) * 3
                          * math.exp(-k / 140), 0, 1)
    spec_img = (np.stack([spec * 230, spec * 180, spec * 90 + 10], -1)).astype(np.uint8)
    img.paste(Image.fromarray(spec_img[::-1]), (460, top))
    d.rectangle([440, top - 10, W - 20, H - 20], outline=(48, 50, 56))
    # 재생 헤드
    d.line([(2050, 100), (2050, H - 20)], fill=(230, 90, 70), width=3)
    d.text((W - 520, H - 70), "00:14:32.118   48 kHz / 24 bit", font=f, fill=(150, 150, 150))
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(OUT / "stu_monitor_screen.png")


def clock_face():
    S = 1024
    img = Image.new("RGB", (S, S), (236, 232, 222))
    d = ImageDraw.Draw(img)
    c = S / 2
    d.ellipse([20, 20, S - 20, S - 20], outline=(40, 40, 40), width=10)
    for i in range(60):
        a = math.radians(i * 6)
        r0 = c - 60 if i % 5 == 0 else c - 40
        w = 12 if i % 5 == 0 else 4
        d.line([(c + math.sin(a) * r0, c - math.cos(a) * r0),
                (c + math.sin(a) * (c - 28), c - math.cos(a) * (c - 28))], fill=(30, 30, 30), width=w)
    f = font(96, True)
    for h in range(1, 13):
        a = math.radians(h * 30)
        x, y = c + math.sin(a) * (c - 140), c - math.cos(a) * (c - 140)
        t = str(h)
        bb = d.textbbox((0, 0), t, font=f)
        d.text((x - (bb[2] - bb[0]) / 2, y - (bb[3] - bb[1]) / 2 - 18), t, font=f, fill=(25, 25, 25))
    d.text((c - 80, c + 150), "QUARTZ", font=font(36), fill=(90, 90, 90))
    # 오래된 시계 — 미세 황변
    arr = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:S, 0:S]
    vign = 1 - 0.12 * (((xx - c) ** 2 + (yy - c) ** 2) / c ** 2)
    arr *= vign[..., None]
    arr[..., 2] *= 0.95
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(OUT / "stu_clock_face.png")


def index_cards():
    """카세트 케이스 인서트 (등 부분 포함) — 손글씨 느낌의 다양한 라벨 8종."""
    labels = ["인터뷰 1", "녹취 0412", "현장음 A", "재판 녹취", "가족 테이프", "라디오 97",
              "노이즈 샘플", "의뢰 #212", "B면 복원", "회의 녹음", "원본-보관", "1994 결혼식"]
    colors = [(235, 228, 210), (222, 232, 238), (240, 236, 220), (236, 222, 205), (225, 228, 222), (245, 240, 228)]
    for i in range(8):
        W, H = 512, 256
        bg = colors[i % len(colors)]
        img = Image.new("RGB", (W, H), bg)
        d = ImageDraw.Draw(img)
        stripe = R.choice([(180, 50, 40), (40, 70, 140), (60, 60, 60), (200, 140, 40), (60, 110, 80)])
        d.rectangle([0, 0, W, 34], fill=stripe)
        d.rectangle([0, H - 54, W, H], fill=tuple(int(c * 0.96) for c in bg))
        f = font(42)
        d.text((20, 60), R.choice(labels), font=f, fill=(30, 30, 70))
        d.text((20, 120), f"{R.randint(1988, 2019)}.{R.randint(1, 12):02d}  {R.choice(['A', 'B', 'A/B'])}",
               font=font(32), fill=(60, 60, 80))
        for k in range(3):
            y = 170 + k * 22
            d.line([(20, y), (W - 20, y)], fill=(180, 190, 200), width=2)
        img = img.filter(ImageFilter.GaussianBlur(0.5))
        img.save(OUT / f"stu_cassette_insert_{i + 1:02d}.png")


def archive_label():
    img = Image.new("RGB", (512, 256), (176, 138, 96))
    d = ImageDraw.Draw(img)
    d.rectangle([60, 50, 452, 200], fill=(238, 234, 224))
    d.text((90, 80), "보관 2019~2021", font=font(44, True), fill=(40, 40, 40))
    d.text((90, 140), "의뢰 원본 테이프", font=font(32), fill=(70, 70, 70))
    arr = np.asarray(img).astype(np.int16) + np.random.default_rng(3).integers(-8, 8, (256, 512, 3))
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(OUT / "stu_archive_box_label.png")


def calendar():
    img = Image.new("RGB", (600, 840), (244, 242, 236))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 600, 360], fill=(120, 130, 120))
    d.text((40, 390), "2026  11", font=font(64, True), fill=(40, 40, 40))
    days = "일 월 화 수 목 금 토".split()
    for i, t in enumerate(days):
        d.text((40 + i * 78, 480), t, font=font(28), fill=(200, 60, 50) if i == 0 else (60, 60, 60))
    day = 1
    for w in range(5):
        for k in range(7):
            if w == 0 and k < 0:
                continue
            if day > 30:
                break
            d.text((44 + k * 78, 530 + w * 58), str(day), font=font(30),
                   fill=(200, 60, 50) if k == 0 else (50, 50, 50))
            if day == 26:
                d.ellipse([34 + k * 78, 524 + w * 58, 92 + k * 78, 572 + w * 58], outline=(30, 60, 160), width=3)
            day += 1
    img.save(OUT / "stu_calendar.png")


if __name__ == "__main__":
    monitor_screen()
    clock_face()
    index_cards()
    archive_label()
    calendar()
    print("textures ->", OUT)
