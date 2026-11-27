"""1998년 복도식 아파트 (apt_) — Blender 5.3 빌드 스크립트 (요구사항 16 TAPE 01 · REF 05)

1층 외부 복도(남쪽이 난간 벽으로 트여 있음) + 동쪽 계단실(2층 참까지) + 현관 계단 + 단지 놀이터(그네)
한국 1990년대 복도식 아파트: 크림색 페인트 벽·연두빛 걸레받이 띠, 철제 현관문(호수판·우유 투입구), 가스계량기와 노란 가스관,
전기 계량기함, 방범창 달린 작은 부엌창, 원형 복도등, 소화전함. 일본·미국식 공간처럼 보이지 않게.

로컬 좌표(Blender, z 위): 복도 x 0~24, y 0(난간)~1.7(세대 벽), 바닥 z 0. 외부 지면 z -0.45.
Godot에서는 AptCorridor 노드(월드 (0, 0, 60))의 자식으로 배치된다.
실행: python3 tools/blender/build_apartment.py [--render]
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
T.PBR_DIR = ROOT / "game" / "assets" / "textures" / "pbr"
ATEX = ROOT / "game" / "assets" / "textures" / "apt"
BLEND = ROOT / "art" / "blender" / "environments" / "apartment_1998" / "apt_1998.blend"
GLB = ROOT / "game" / "assets" / "models" / "environments" / "apt_1998.gltf"
RENDERS = ROOT / "art" / "renders" / "apartment_1998"
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
R = T.RNG

L = 24.0            # 복도 길이
CW = 1.7            # 복도 폭
H = 2.55            # 층고(천장 슬래브 아래)
FLOOR_H = 2.8       # 층 간격
GROUND = -0.45
UNITS = [2.1, 6.3, 10.5, 14.7, 18.9]     # 현관문 중심 x (101~105호)
PILLARS = [0.0, 4.2, 8.4, 12.6, 16.8, 21.0, 24.0]


def signs():
    ATEX.mkdir(parents=True, exist_ok=True)
    f = FONT
    for k, x in enumerate(UNITS, 1):
        img = Image.new("RGB", (256, 128), (238, 232, 214))
        d = ImageDraw.Draw(img)
        d.rectangle([4, 4, 251, 123], outline=(120, 110, 90), width=4)
        d.text((40, 14), f"10{k}", font=ImageFont.truetype(f, 84, index=1), fill=(40, 40, 46))
        img.save(ATEX / f"apt_door_{k}.png")
    img = Image.new("RGB", (256, 128), (232, 226, 205))
    d = ImageDraw.Draw(img)
    d.text((40, 20), "우 유", font=ImageFont.truetype(f, 64, index=1), fill=(60, 60, 60))
    img.save(ATEX / "apt_milk.png")
    img = Image.new("RGB", (512, 512), (160, 20, 16))
    d = ImageDraw.Draw(img)
    d.text((70, 170), "소화전", font=ImageFont.truetype(f, 130, index=1), fill=(245, 240, 230))
    img.save(ATEX / "apt_hydrant.png")
    img = Image.new("RGB", (512, 256), (40, 90, 60))
    d = ImageDraw.Draw(img)
    d.text((40, 50), "새솔아파트 3동", font=ImageFont.truetype(f, 70, index=1), fill=(240, 240, 230))
    img.save(ATEX / "apt_sign.png")
    # 맞은편 동 외벽: 창문·난간 띠 (원경용, 1장 반복)
    img = Image.new("RGB", (1024, 1024), (214, 206, 186))
    d = ImageDraw.Draw(img)
    for fl in range(5):
        y0 = fl * 204
        d.rectangle([0, y0 + 120, 1024, y0 + 204], fill=(196, 188, 168))
        for u in range(6):
            x0 = 40 + u * 168
            lit = (R.random() < 0.15)
            d.rectangle([x0, y0 + 30, x0 + 110, y0 + 112], fill=(230, 200, 140) if lit else (70, 78, 84))
            d.line([x0 + 55, y0 + 30, x0 + 55, y0 + 112], fill=(150, 150, 150), width=4)
    img.save(ATEX / "apt_facade.png")


def materials():
    P = T.mat_pbr
    M = {}
    M["wall"] = P("apt_wall_cream", "wall_paint_ivory", tint=(1.02, 0.97, 0.86))
    M["band"] = P("apt_wall_band", "wall_paint_ivory", tint=(0.74, 0.86, 0.72))      # 연두빛 띠
    M["parapet"] = P("apt_parapet", "concrete_paint", tint=(1.05, 1.0, 0.9))
    M["floor"] = P("apt_floor", "concrete_paint", tint=(0.82, 0.82, 0.8))
    M["ceiling"] = P("apt_ceiling", "concrete_paint", tint=(1.1, 1.08, 1.02))
    M["stair"] = P("apt_stair", "stair_terrazzo")
    M["door"] = P("apt_door", "steel_door_paint", tint=(0.72, 0.55, 0.42))
    M["frame"] = P("apt_frame", "steel_door_paint_green", tint=(0.6, 0.62, 0.55))
    M["metal"] = P("apt_metal", "brushed_steel")
    M["alu"] = P("apt_alu", "brushed_aluminium")
    M["pipe_yellow"] = T.mat_basic("apt_gas_pipe", (0.78, 0.6, 0.08), 0.45, 0.2)
    M["meter"] = T.mat_basic("apt_meter_grey", (0.52, 0.52, 0.5), 0.5)
    M["glass"] = T.mat_basic("apt_window_pane_dark", (0.06, 0.075, 0.085), 0.12, 0.0)
    M["ground"] = P("apt_ground_earth", "concrete_paint", tint=(0.66, 0.6, 0.5))      # 다져진 흙바닥
    M["asphalt"] = P("apt_asphalt", "concrete_wet", tint=(0.55, 0.55, 0.56))
    M["sand"] = P("apt_sand", "concrete_paint", tint=(0.95, 0.85, 0.66))           # 놀이터 모래
    M["curb"] = P("apt_curb", "concrete_paint", tint=(0.85, 0.85, 0.82))
    M["swing_blue"] = T.mat_basic("apt_swing_frame", (0.16, 0.36, 0.52), 0.5, 0.3)
    M["seat_red"] = T.mat_basic("apt_swing_seat_red", (0.62, 0.1, 0.07), 0.55)
    M["seat_green"] = T.mat_basic("apt_swing_seat_green", (0.1, 0.42, 0.22), 0.55)
    M["chain"] = P("apt_chain", "brushed_steel")
    M["wood"] = P("apt_bench_wood", "oak_laminate", tint=(0.8, 0.62, 0.45))
    M["bark"] = T.mat_basic("apt_bark", (0.2, 0.15, 0.11), 0.9)
    M["leaf"] = P("apt_leaf", "leaf", tint=(0.9, 1.35, 0.7))
    M["hedge"] = P("apt_hedge", "leaf", tint=(0.75, 1.2, 0.6))
    M["red"] = P("apt_red", "fire_red_paint")
    M["lamp"] = T.mat_emission("apt_lamp_shade", (1.0, 0.95, 0.85), 1.5, (0.85, 0.83, 0.78))
    M["doors"] = [T.mat_image(f"apt_door_plate_{k}", str(ATEX / f"apt_door_{k}.png"), rough=0.4) for k in range(1, 6)]
    M["milk"] = T.mat_image("apt_milk_lbl", str(ATEX / "apt_milk.png"), rough=0.5)
    M["hydrant"] = T.mat_image("apt_hydrant_door", str(ATEX / "apt_hydrant.png"), rough=0.35)
    M["sign"] = T.mat_image("apt_sign", str(ATEX / "apt_sign.png"), rough=0.5)
    M["facade"] = T.mat_image("apt_facade", str(ATEX / "apt_facade.png"), rough=0.8)
    return M


def unit_door(M, col, k, x):
    y = CW
    T.box(f"apt_door_frame_{k}", (1.02, 0.12, 2.12), (x, y - 0.01, 1.06), M["frame"], 0.006, col=col)
    T.box(f"apt_door_leaf_{k}", (0.9, 0.05, 2.02), (x, y - 0.07, 1.02), M["door"], 0.004, col=col)
    T.box(f"apt_door_plate_{k}", (0.2, 0.006, 0.1), (x, y - 0.1, 1.78), M["doors"][k - 1], 0.001, col=col)
    T.cyl(f"apt_door_knob_{k}", 0.028, 0.06, (x + 0.34, y - 0.12, 1.0), M["metal"], rot=(math.pi / 2, 0, 0), col=col, verts=20)
    T.box(f"apt_door_keyhole_{k}", (0.05, 0.02, 0.09), (x + 0.34, y - 0.1, 1.12), M["metal"], 0.004, col=col)
    # 우유 투입구 (문 옆 벽의 작은 철제 함)
    T.box(f"apt_milk_box_{k}", (0.26, 0.12, 0.22), (x - 0.75, y - 0.06, 1.05), M["frame"], 0.006, col=col)
    T.box(f"apt_milk_lbl_{k}", (0.14, 0.004, 0.07), (x - 0.75, y - 0.122, 1.1), M["milk"], 0.001, col=col)
    # 가스계량기 + 노란 가스관 (문 반대편 위)
    T.box(f"apt_gas_meter_{k}", (0.24, 0.14, 0.3), (x + 0.82, y - 0.07, 1.65), M["meter"], 0.01, col=col)
    T.cyl(f"apt_gas_pipe_v_{k}", 0.014, 1.0, (x + 0.82, y - 0.04, 2.25), M["pipe_yellow"], col=col, verts=12)
    T.cyl(f"apt_gas_pipe_h_{k}", 0.014, 0.6, (x + 0.62, y - 0.04, 2.45), M["pipe_yellow"], rot=(0, math.pi / 2, 0), col=col, verts=12)
    # 전기 계량기함 (창 달린 회색 함)
    T.box(f"apt_elec_box_{k}", (0.3, 0.1, 0.4), (x + 0.85, y - 0.05, 1.12), M["meter"], 0.008, col=col)
    T.box(f"apt_elec_win_{k}", (0.16, 0.006, 0.12), (x + 0.85, y - 0.102, 1.2), M["glass"], 0.002, col=col)
    # 부엌 쪽 작은 창 + 방범창 살
    wx = x + 1.6
    T.box(f"apt_kwin_{k}", (0.9, 0.06, 0.6), (wx, y - 0.02, 1.75), M["glass"], 0.004, col=col)
    for b in range(6):
        T.cyl(f"apt_kwin_bar_{k}_{b}", 0.008, 0.66, (wx - 0.4 + b * 0.16, y - 0.1, 1.75), M["metal"], col=col, verts=8)
    T.box(f"apt_kwin_sill_{k}", (1.0, 0.14, 0.04), (wx, y - 0.08, 1.43), M["parapet"], 0.004, col=col)
    # 복도등 (원형 유리 갓)
    T.cyl(f"apt_lamp_base_{k}", 0.11, 0.03, (x, CW / 2, H - 0.015), M["parapet"], col=col, verts=24)
    T.cyl(f"apt_lamp_glass_{k}", 0.09, 0.06, (x, CW / 2, H - 0.06), M["lamp"], col=col, verts=24)


def building(M, col):
    # 1층 복도 바닥 슬래브 + 기초
    T.box("apt_corridor_floor", (L + 0.3, CW + 0.3, 0.3), (L / 2, CW / 2, -0.15), M["floor"], 0.005, col=col)
    T.box("apt_plinth", (L + 3.6, 0.3, -GROUND), (L / 2 + 1.5, -0.15, GROUND / 2), M["parapet"], 0.004, col=col)
    # 세대 벽 (북쪽) + 연두 띠
    T.box("apt_unit_wall", (L, 0.2, H), (L / 2, CW + 0.1, H / 2), M["wall"], 0.003, col=col)
    T.box("apt_unit_band", (L, 0.012, 0.9), (L / 2, CW - 0.006, 0.45), M["band"], 0.002, col=col)
    # 난간 벽 (남쪽) + 위 덮개
    T.box("apt_parapet", (L, 0.18, 1.05), (L / 2, 0.09, 0.525), M["parapet"], 0.004, col=col)
    T.box("apt_parapet_cap", (L + 0.05, 0.24, 0.06), (L / 2, 0.09, 1.08), M["parapet"], 0.008, col=col)
    T.box("apt_parapet_band", (L, 0.012, 0.35), (L / 2, 0.186, 0.175), M["band"], 0.002, col=col)
    for i, x in enumerate(PILLARS):
        T.box(f"apt_pillar_{i}", (0.36, 0.36, H), (x, 0.13, H / 2), M["parapet"], 0.008, col=col)
    # 위층들 (외관): 슬래브·난간 띠·기둥 4개 층 — 복도에서 위를 보면 2층 복도 바닥 슬래브
    for f in range(1, 5):
        z0 = f * FLOOR_H
        T.box(f"apt_slab_{f}", (L + 0.3, CW + 0.35, 0.25), (L / 2, CW / 2 - 0.02, z0 - 0.125), M["ceiling"], 0.004, col=col)
        T.box(f"apt_parapet_up_{f}", (L, 0.18, 1.05), (L / 2, 0.09, z0 + 0.525), M["parapet"], 0.004, col=col)
        T.box(f"apt_parapet_band_up_{f}", (L, 0.012, 0.35), (L / 2, -0.006, z0 + 0.175), M["band"], 0.002, col=col)
        T.box(f"apt_unit_wall_up_{f}", (L, 0.2, FLOOR_H), (L / 2, CW + 0.1, z0 + FLOOR_H / 2), M["wall"], 0.003, col=col)
        for k, x in enumerate(UNITS, 1):      # 위층 세대 현관문·부엌창 (원경용 단순형)
            T.box(f"apt_door_up_{f}_{k}", (0.9, 0.06, 2.0), (x, CW - 0.03, z0 + 1.0), M["door"], 0.004, col=col)
            T.box(f"apt_kwin_up_{f}_{k}", (0.9, 0.05, 0.6), (x + 1.6, CW - 0.02, z0 + 1.75), M["glass"], 0.003, col=col)
            T.box(f"apt_meter_up_{f}_{k}", (0.24, 0.12, 0.3), (x + 0.82, CW - 0.06, z0 + 1.65), M["meter"], 0.008, col=col)
        for i, x in enumerate(PILLARS):
            T.box(f"apt_pillar_up_{f}_{i}", (0.36, 0.36, FLOOR_H - 0.25), (x, 0.13, z0 + (FLOOR_H - 0.25) / 2), M["parapet"], 0.008, col=col)
    T.box("apt_roof", (L + 0.6, CW + 9.5, 0.3), (L / 2, 4.6, 5 * FLOOR_H), M["parapet"], 0.004, col=col)
    # 세대 몸통 (북쪽 깊이 8 m, 외벽만)
    T.box("apt_units_mass", (L, 8.0, 5 * FLOOR_H), (L / 2, CW + 0.2 + 4.0, 5 * FLOOR_H / 2 - 0.2), M["wall"], 0.003, col=col)
    # 서쪽 끝 벽 + 소화전함 + 작은 창
    T.box("apt_end_wall_w", (0.2, CW + 0.3, H), (-0.1, CW / 2, H / 2), M["wall"], 0.003, col=col)
    T.box("apt_hydrant_box", (0.12, 0.7, 0.9), (0.06, 1.1, 1.05), M["red"], 0.01, col=col)
    T.box("apt_hydrant_door", (0.006, 0.6, 0.78), (0.122, 1.1, 1.05), M["hydrant"], 0.002, col=col)
    T.box("apt_sign_plate", (0.9, 0.04, 0.45), (5.0, -0.12, 3.9), M["sign"], 0.004, col=col)
    T.box("apt_ceiling_1f", (L, CW, 0.02), (L / 2, CW / 2, H + 0.01), M["ceiling"], 0.0, col=col)
    for k, x in enumerate(UNITS, 1):
        unit_door(M, col, k, x)


def stairwell(M, col):
    """동쪽 계단실 x 24~27.4: 1층 → 참(z 1.4) → 2층(z 2.8). 남쪽 출입구(현관) + 바깥 계단 3단."""
    x0, x1, y0, y1 = L, L + 3.4, -0.2, 5.6
    T.box("apt_stair_floor", (x1 - x0, y1 - y0, 0.3), ((x0 + x1) / 2, (y0 + y1) / 2, -0.15), M["stair"], 0.004, col=col)
    T.box("apt_stair_wall_e", (0.2, y1 - y0, 2 * FLOOR_H + 1), (x1 + 0.1, (y0 + y1) / 2, FLOOR_H), M["wall"], 0.003, col=col)
    T.box("apt_stair_wall_n", (x1 - x0 + 0.4, 0.2, 2 * FLOOR_H + 1), ((x0 + x1) / 2, y1 + 0.1, FLOOR_H), M["wall"], 0.003, col=col)
    # 남쪽 벽: 현관 개구부 x 24.4~25.8 (1층), 위는 창
    T.box("apt_stair_wall_s_a", (0.4, 0.2, 2 * FLOOR_H + 1), (x0 + 0.2, y0 - 0.1, FLOOR_H), M["wall"], 0.003, col=col)
    T.box("apt_stair_wall_s_b", (x1 - 25.8, 0.2, 2 * FLOOR_H + 1), ((25.8 + x1) / 2, y0 - 0.1, FLOOR_H), M["wall"], 0.003, col=col)
    T.box("apt_stair_wall_s_top", (1.4, 0.2, 2 * FLOOR_H + 1 - 2.2), (25.1, y0 - 0.1, 2.2 + (2 * FLOOR_H + 1 - 2.2) / 2), M["wall"], 0.003, col=col)
    T.box("apt_stair_window", (1.0, 0.05, 1.0), (25.1, y0 - 0.12, 3.6), M["glass"], 0.003, col=col)
    # 계단실 서쪽 벽(복도와 경계) — 복도 쪽 개구부 y 0~1.7
    T.box("apt_stair_wall_w", (0.2, y1 - 1.9, 2 * FLOOR_H + 1), (x0 - 0.1, (1.9 + y1) / 2, FLOOR_H), M["wall"], 0.003, col=col)
    T.box("apt_stair_wall_w_top", (0.2, 2.1, 2 * FLOOR_H + 1 - H), (x0 - 0.1, 0.85, H + (2 * FLOOR_H + 1 - H) / 2), M["wall"], 0.003, col=col)
    # 1단: x 25.0~26.1, y 1.9 → 4.5 상승 (z 0 → 1.4), 참: y 4.5~5.6, 2단: x 26.2~27.3, y 4.5 → 1.9 (z 1.4 → 2.8)
    n = 9
    for i in range(n):
        z = (i + 1) * 1.4 / n
        y = 1.9 + i * (2.6 / n)
        T.box(f"apt_step_a_{i}", (1.15, 2.6 / n + 0.02, z), (25.55, y + 1.3 / n, z / 2), M["stair"], 0.003, col=col)
        z2 = 1.4 + (i + 1) * 1.4 / n
        y2 = 4.5 - i * (2.6 / n)
        T.box(f"apt_step_b_{i}", (1.15, 2.6 / n + 0.02, z2 - 1.4 + 0.2), (26.75, y2 - 1.3 / n, 1.4 + (z2 - 1.4 + 0.2) / 2 - 0.2), M["stair"], 0.003, col=col)
    T.box("apt_landing", (2.4, 1.1, 0.2), (26.15, 5.05, 1.3), M["stair"], 0.003, col=col)
    T.box("apt_floor2", (2.4, 1.9, 0.2), (26.15, 0.85, 2.7), M["stair"], 0.003, col=col)
    T.box("apt_stair_divider", (0.1, 2.6, 1.0), (26.15, 3.2, 0.5), M["wall"], 0.003, col=col)
    T.box("apt_handrail_a", (0.05, 2.9, 0.05), (25.0, 3.2, 1.6), M["metal"], 0.004, col=col, rot=(math.atan2(1.4, 2.6), 0, 0))
    # 2층 복도 입구는 방화문이 닫혀 있음 (이 챕터 범위 밖)
    T.box("apt_floor2_door", (0.06, 1.6, 2.1), (x0 + 0.05, 0.85, 2.8 + 1.05), M["frame"], 0.004, col=col)
    T.box("apt_stair_ceiling", (x1 - x0, y1 - y0, 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, 2 * FLOOR_H + 0.4), M["ceiling"], 0.0, col=col)
    T.cyl("apt_stair_lamp_glass", 0.09, 0.06, (26.15, 5.05, 2.6), M["lamp"], col=col, verts=24)
    # 현관 바깥 계단 3단 (z 0 → 지면 -0.45)
    for i in range(3):
        T.box(f"apt_entry_step_{i}", (1.6, 0.32, 0.15 * (3 - i)), (25.1, y0 - 0.36 - i * 0.32, GROUND + 0.075 * (3 - i)), M["curb"], 0.004, col=col)
    T.box("apt_entry_canopy", (2.0, 1.2, 0.12), (25.1, y0 - 0.6, 2.5), M["parapet"], 0.006, col=col)


def outside(M, col):
    T.box("apt_ground", (70, 46, 0.2), (12, -14, GROUND - 0.1), M["ground"], 0.0, col=col)
    T.box("apt_path", (3.0, 18, 0.04), (25.1, -9.5, GROUND + 0.02), M["asphalt"], 0.0, col=col)
    T.box("apt_road", (70, 6, 0.04), (12, -21, GROUND + 0.02), M["asphalt"], 0.0, col=col)
    # 화단 생울타리 (건물 앞)
    for i in range(6):
        T.box(f"apt_hedge_{i}", (3.4, 0.9, 0.75), (1.8 + i * 3.9, -0.95, GROUND + 0.375), M["hedge"], 0.08, col=col)
    # 놀이터 (모래, 경계석, 그네 2개, 벤치)
    px, py = 11.0, -10.0
    T.box("apt_sand", (10, 7, 0.06), (px, py, GROUND + 0.03), M["sand"], 0.0, col=col)
    for sx in (-1, 1):
        T.box(f"apt_curb_x{sx}", (10.3, 0.15, 0.18), (px, py + sx * 3.55, GROUND + 0.09), M["curb"], 0.01, col=col)
        T.box(f"apt_curb_y{sx}", (0.15, 7.1, 0.18), (px + sx * 5.1, py, GROUND + 0.09), M["curb"], 0.01, col=col)
    sw_x, sw_y, bar_z = px - 1.5, py + 0.5, GROUND + 2.3
    T.cyl("apt_swing_bar", 0.04, 3.4, (sw_x, sw_y, bar_z), M["swing_blue"], rot=(0, math.pi / 2, 0), col=col, verts=16)
    for ex in (-1.65, 1.65):
        for ey in (-1, 1):
            T.cyl(f"apt_swing_leg_{ex}_{ey}", 0.035, 2.45, (sw_x + ex, sw_y + ey * 0.42, GROUND + 1.15), M["swing_blue"],
                  rot=(ey * math.radians(-10), 0, 0), col=col, verts=12)
    for k, (dx, m) in enumerate(((-0.75, M["seat_red"]), (0.75, M["seat_green"]))):
        piv = T.empty(f"apt_swing_{k}", (sw_x + dx, sw_y, bar_z), col)
        T.keep(piv, "swing")
        for cx in (-0.2, 0.2):
            T.cyl(f"apt_swing_{k}_chain_{cx}", 0.008, 1.8, (cx, 0, -0.9), M["chain"], col=col, parent=piv, verts=8)
        T.box(f"apt_swing_{k}_seat", (0.48, 0.18, 0.04), (0, 0, -1.82), m, 0.01, col=col, parent=piv)
    for b in range(2):
        T.box(f"apt_bench_{b}_seat", (1.6, 0.38, 0.05), (px + 2.8, py - 2.5 + b * 4.6, GROUND + 0.45), M["wood"], 0.01, col=col)
        T.box(f"apt_bench_{b}_back", (1.6, 0.05, 0.35), (px + 2.8, py - 2.7 + b * 4.6 + (0.4 if b else 0), GROUND + 0.75), M["wood"], 0.01, col=col)
        for lx in (-0.7, 0.7):
            T.box(f"apt_bench_{b}_leg_{lx}", (0.06, 0.38, 0.45), (px + 2.8 + lx, py - 2.5 + b * 4.6, GROUND + 0.225), M["metal"], 0.004, col=col)
    # 나무 (단지 조경)
    for i, (tx, ty, s) in enumerate([(3, -5, 1.0), (19, -6, 1.2), (4, -15, 0.9), (20, -14, 1.1), (30, -4, 1.0), (-4, -8, 1.15)]):
        T.cyl(f"apt_tree_{i}_trunk", 0.14 * s, 3.2 * s, (tx, ty, GROUND + 1.6 * s), M["bark"], col=col, verts=10)
        for j in range(9):
            a = j * 2.4
            rr = (0.55 + 0.35 * R.random()) * s
            ring = 0.0 if j == 0 else (0.75 if j < 6 else 0.4) * s
            zz = GROUND + (3.5 + (0.0 if j == 0 else (0.2 if j < 6 else 1.1)) + R.uniform(-0.2, 0.2)) * s
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=rr * (1.6 if j == 0 else 1.0),
                                                  location=(tx + ring * math.cos(a), ty + ring * math.sin(a), zz))
            o = bpy.context.active_object
            o.name = f"apt_tree_{i}_leaf_{j}"
            o.data.materials.append(M["leaf"])
            tex = bpy.data.textures.new(f"apt_leafnoise_{i}_{j}", "CLOUDS")
            tex.noise_scale = 0.25
            dm = o.modifiers.new("disp", "DISPLACE")
            dm.texture = tex
            dm.strength = 0.22 * s
            o.data.shade_smooth()
            for c in o.users_collection:
                c.objects.unlink(o)
            col.objects.link(o)
    # 맞은편 동 (원경)
    T.box("apt_far_block", (44, 9, 15), (12, -31, GROUND + 7.5), M["facade"], 0.0, col=col)


def colliders(C):
    cc = C["col"]
    T.collider("apt_floor", (L + 0.3, CW + 0.3, 0.3), (L / 2, CW / 2, -0.15), cc)
    T.collider("apt_unit_wall", (L, 0.2, H), (L / 2, CW + 0.1, H / 2), cc)
    T.collider("apt_parapet", (L, 0.2, 1.1), (L / 2, 0.09, 0.55), cc)
    T.collider("apt_parapet_block", (L, 0.1, H - 1.1), (L / 2, 0.05, 1.1 + (H - 1.1) / 2), cc)   # 난간 위로 넘어가지 못하게 (보이지 않는 막)
    T.collider("apt_end_w", (0.2, CW + 0.4, H), (-0.1, CW / 2, H / 2), cc)
    T.collider("apt_ceiling", (L + 4, CW + 6, 0.2), (L / 2 + 2, CW / 2, H + 0.1), cc)
    T.collider("apt_stair_floor", (3.4, 5.8, 0.3), (L + 1.7, 2.7, -0.15), cc)
    T.collider("apt_stair_e", (0.2, 6.0, 6), (L + 3.5, 2.7, 3), cc)
    T.collider("apt_stair_n", (3.8, 0.2, 6), (L + 1.7, 5.7, 3), cc)
    T.collider("apt_stair_s_a", (0.4, 0.2, 6), (L + 0.2, -0.3, 3), cc)
    T.collider("apt_stair_s_b", (1.6, 0.2, 6), (26.6, -0.3, 3), cc)
    T.collider("apt_stair_w", (0.2, 3.7, 6), (L - 0.1, 3.75, 3), cc)
    T.collider("apt_stair_w_top", (0.2, 2.1, 3), (L - 0.1, 0.85, H + 1.5), cc)
    T.collider("apt_stair_divider", (0.1, 2.6, 2.8), (26.15, 3.2, 1.4), cc)
    # 계단 경사 (램프)
    ang = math.atan2(1.4, 2.6)
    T.collider("apt_ramp_a", (1.15, math.hypot(2.6, 1.4), 0.1), (25.55, 3.2, 0.7), cc, rot=(ang, 0, 0))
    T.collider("apt_ramp_b", (1.15, math.hypot(2.6, 1.4), 0.1), (26.75, 3.2, 2.1), cc, rot=(-ang, 0, 0))
    T.collider("apt_landing", (2.4, 1.1, 0.2), (26.15, 5.05, 1.3), cc)
    T.collider("apt_floor2", (2.4, 1.9, 0.2), (26.15, 0.85, 2.7), cc)
    T.collider("apt_floor2_door", (0.1, 1.7, 2.2), (L + 0.05, 0.85, 3.9), cc)
    T.collider("apt_entry_ramp", (1.6, 1.1, 0.1), (25.1, -0.75, GROUND / 2), cc, rot=(math.atan2(0.45, 1.0), 0, 0))
    T.collider("apt_ground", (70, 46, 0.2), (12, -14, GROUND - 0.1), cc)
    T.collider("apt_plinth", (L + 0.4, 0.3, -GROUND), (L / 2 - 0.2, -0.15, GROUND / 2), cc)
    # 단지 경계 (보이지 않는 막) — 놀이터·현관 주변만 다닐 수 있게
    for nm, dims, loc in [("apt_bound_s", (40, 0.3, 4), (12, -17.5, 1)), ("apt_bound_w", (0.3, 18, 4), (-2.5, -8.5, 1)),
                          ("apt_bound_e", (0.3, 18, 4), (29.5, -8.5, 1))]:
        T.collider(nm, dims, loc, cc)
    for i in range(6):
        T.collider(f"apt_hedge_{i}", (3.4, 0.9, 0.8), (1.8 + i * 3.9, -0.95, GROUND + 0.4), cc)
    T.collider("apt_swing_frame", (3.5, 1.0, 0.3), (9.5, -9.5, GROUND + 2.3), cc)


def markers(C):
    m = C["props"]
    T.empty("apt_spawn", (3.0, 0.85, 0.0), m, rot=(0, 0, -math.pi / 2))          # 서쪽에서 동쪽을 바라봄
    T.empty("apt_frag_1", (12.6, -9.2, GROUND + 0.05), m)                          # 놀이터 그네 옆 모래 위
    T.empty("apt_frag_2", (26.15, 5.0, 1.42), m)                                   # 계단 참
    T.empty("apt_frag_3", (14.0, 0.25, 1.12), m)                                   # 104호 앞 난간 위
    T.empty("apt_soeun_end", (23.4, 0.95, 0.0), m)                                  # 복도 동쪽 끝 (계단실 앞)
    T.empty("apt_steps_up", (26.75, 2.2, 2.9), m)                                   # 2층 쪽 발소리
    for o in m.objects:
        if o.type == "EMPTY":
            o["tuv_marker"] = 1


def main():
    args = sys.argv[1:]
    T.reset_scene()
    signs()
    C = {k: T.collection(v) for k, v in {"arch": "apt_architecture", "props": "apt_props", "col": "apt_collision", "cams": "apt_cameras"}.items()}
    M = materials()
    building(M, C["arch"])
    stairwell(M, C["arch"])
    outside(M, C["arch"])
    colliders(C)
    markers(C)
    w = bpy.data.worlds.new("apt_world")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.6, 0.66, 1)
    bpy.context.scene.world = w
    cams = {
        "corridor": T.camera("CAM_apt_corridor", (2.0, 0.85, 1.64), (22.0, 0.9, 1.2), fov_v=62, col=C["cams"]),
        "playground": T.camera("CAM_apt_play", (18.0, -4.0, 1.2), (9.5, -10.0, 0.5), fov_v=62, col=C["cams"]),
        "facade": T.camera("CAM_apt_facade", (12.0, -14.0, 1.4), (12.0, 0.0, 4.0), fov_v=62, col=C["cams"]),
        "stairs": T.camera("CAM_apt_stairs", (25.4, 1.2, 1.64), (26.0, 5.0, 1.8), fov_v=62, col=C["cams"]),
    }
    C["col"].hide_render = True
    BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    print(f"[apt] saved {BLEND}")
    if "--render" in args:
        RENDERS.mkdir(parents=True, exist_ok=True)
        sun = bpy.data.lights.new("apt_sun", "SUN")
        sun.energy = 3.0
        so = bpy.data.objects.new("apt_sun", sun)
        so.rotation_euler = (math.radians(55), 0, math.radians(-30))
        bpy.context.scene.collection.objects.link(so)
        T.setup_render(24, (960, 540), exposure=0.0)
        for name, cam in cams.items():
            T.render(cam, str(RENDERS / f"apt_{name}.png"))
            print("[apt] rendered", name)
    merged, kept, src = T.export_optimized(str(GLB), [C["arch"], C["props"]], C["col"], "apt", flatten_basic=True)
    print(f"[apt] GLB: source meshes={src} -> merged static={merged} + kept={kept}")


if __name__ == "__main__":
    main()
