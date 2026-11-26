"""작업실 외부 상가 복도 (cor_) — Blender 5.3 빌드 스크립트  (REF 03)

작업실과 같은 월드 좌표를 쓴다 → Godot에서 두 GLB를 함께 배치하면 출입문으로 끊김 없이 이어진다.
  복도: x -5.0 ~ 13.0, y -2.0 ~ -0.2 (폭 1.8 m), 천장 2.5 m. 북쪽 벽 = 303 / 304(작업실) / 305호
  남쪽: 308호 문 · 셔터 내린 점포 · 306호 문    서쪽 끝: 엘리베이터    동쪽 끝: 계단실(상·하행)
실행: python3 tools/blender/build_corridor.py [--render] [--samples N] [--res WxH]
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402

import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
T.PBR_DIR = ROOT / "game" / "assets" / "textures" / "pbr"
DECALS = ROOT / "game" / "assets" / "textures" / "decals"
CTEX = ROOT / "game" / "assets" / "textures" / "cor"
BLEND = ROOT / "art" / "blender" / "environments" / "studio_corridor" / "cor_corridor.blend"
GLB = ROOT / "game" / "assets" / "models" / "environments" / "cor_corridor.gltf"
RENDERS = ROOT / "art" / "renders" / "corridor"
R = T.RNG

X0, X1 = -5.0, 13.0          # 복도 길이
YN, YS = -0.2, -2.0          # 북쪽 벽면, 남쪽 벽면
H = 2.5                      # 천장고
WT = 0.2
STU_DOOR_X, DOOR_W = 0.95, 0.9


def signs():
    """호실 번호판·비상구 표지·안내문 텍스처 (자체 제작)."""
    from PIL import Image, ImageDraw, ImageFont
    CTEX.mkdir(parents=True, exist_ok=True)
    f = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
    for num in ("303", "304", "305", "306", "308"):
        img = Image.new("RGB", (512, 256), (22, 22, 24))
        d = ImageDraw.Draw(img)
        d.text((60, 40), num, font=ImageFont.truetype(f, 150, index=1), fill=(236, 236, 232))
        d.text((330, 150), "호", font=ImageFont.truetype(f, 70, index=1), fill=(200, 200, 196))
        img.save(CTEX / f"cor_room_{num}.png")
    # 비상구 (녹색 바탕, 달리는 사람과 문 — 자체 그림)
    img = Image.new("RGB", (768, 256), (24, 140, 70))
    d = ImageDraw.Draw(img)
    d.rectangle([520, 40, 640, 216], outline=(240, 250, 240), width=12)
    cx, cy = 300, 128
    d.ellipse([cx + 40, 30, cx + 80, 70], fill=(240, 250, 240))
    d.line([(cx + 55, 75), (cx + 20, 150)], fill=(240, 250, 240), width=24)
    d.line([(cx + 20, 150), (cx + 70, 215)], fill=(240, 250, 240), width=20)
    d.line([(cx + 20, 150), (cx - 40, 200)], fill=(240, 250, 240), width=20)
    d.line([(cx + 50, 95), (cx + 110, 120)], fill=(240, 250, 240), width=18)
    d.line([(cx + 50, 95), (cx - 10, 90)], fill=(240, 250, 240), width=18)
    d.polygon([(140, 128), (210, 80), (210, 176)], fill=(240, 250, 240))
    d.rectangle([60, 112, 150, 144], fill=(240, 250, 240))
    d.text((660, 90), "", font=ImageFont.truetype(f, 40, index=1), fill=(240, 250, 240))
    img.save(CTEX / "cor_exit_sign.png")
    # 안내문 (A4, 테이프로 붙임)
    img = Image.new("RGB", (620, 877), (244, 243, 238))
    d = ImageDraw.Draw(img)
    d.text((60, 70), "정기 소독 안내", font=ImageFont.truetype(f, 64, index=1), fill=(30, 30, 30))
    fr = ImageFont.truetype(f.replace("Bold", "Regular"), 30, index=1)
    for k, t in enumerate(["일시: 매월 첫째 주 수요일", "대상: 3층 전 호실", "", "부재 시 관리실로", "연락 바랍니다.", "", "관리사무소"]):
        d.text((60, 200 + k * 60), t, font=fr, fill=(50, 50, 50))
    img.save(CTEX / "cor_notice.png")
    # 소화전 문 글씨
    img = Image.new("RGB", (512, 512), (150, 18, 14))
    d = ImageDraw.Draw(img)
    d.text((90, 160), "소화전", font=ImageFont.truetype(f, 120, index=1), fill=(245, 240, 235))
    img.save(CTEX / "cor_hydrant.png")
    # 엘리베이터 층 표시
    img = Image.new("RGB", (256, 128), (8, 8, 8))
    d = ImageDraw.Draw(img)
    d.text((90, 10), "3", font=ImageFont.truetype(f, 96, index=1), fill=(255, 90, 40))
    img.save(CTEX / "cor_elev_floor.png")


def build_materials():
    P = T.mat_pbr
    M = {}
    M["wall"] = P("cor_wall_ivory", "wall_paint_ivory")
    M["wall_low"] = P("cor_wall_wainscot", "wall_paint_ivory", tint=(0.78, 0.72, 0.6))
    M["floor"] = P("cor_floor_tile", "corridor_floor_tile")
    M["ceiling"] = P("cor_ceiling_tex", "ceiling_tex")
    M["stair"] = P("cor_stair_terrazzo", "stair_terrazzo")
    M["stair_wall"] = P("cor_stair_wall_paint", "concrete_paint")
    M["door"] = P("cor_steel_door", "steel_door_paint")
    M["door_green"] = P("cor_steel_door_green", "steel_door_paint_green")
    M["chrome"] = P("cor_brushed_steel", "brushed_steel")
    M["alu"] = P("cor_aluminium", "brushed_aluminium")
    M["black"] = P("cor_powdercoat_black", "powdercoat_black")
    M["red"] = P("cor_fire_red", "fire_red_paint")
    M["baseboard"] = P("cor_baseboard", "baseboard_pvc")
    M["plastic_white"] = P("cor_abs_white", "abs_white")
    M["rubber"] = P("cor_rubber", "rubber_black")
    M["cardboard"] = P("cor_cardboard", "cardboard")
    M["paper"] = P("cor_paper", "paper")
    M["ceramic"] = P("cor_ceramic", "ceramic_glaze")
    M["soil"] = P("cor_soil", "soil")
    M["leaf"] = P("cor_leaf_dry", "leaf", tint=(1.6, 1.2, 0.6))
    M["tube"] = T.mat_emission("cor_fluorescent_tube", (0.92, 0.97, 1.0), 6.0, (0.9, 0.9, 0.9))
    M["exit"] = T.mat_image("cor_exit_sign", str(CTEX / "cor_exit_sign.png"), emission=2.5, rough=0.3)
    M["notice"] = T.mat_image("cor_notice", str(CTEX / "cor_notice.png"), rough=0.8)
    M["hydrant"] = T.mat_image("cor_hydrant_door", str(CTEX / "cor_hydrant.png"), rough=0.35)
    M["elev_floor"] = T.mat_image("cor_elev_floor", str(CTEX / "cor_elev_floor.png"), emission=2.0, rough=0.2)
    M["led_red"] = T.mat_emission("cor_led_red", (1.0, 0.25, 0.08), 3.0)
    M["rooms"] = {n: T.mat_image(f"cor_room_{n}", str(CTEX / f"cor_room_{n}.png"), rough=0.25) for n in ("303", "304", "305", "306", "308")}
    M["d_dirt"] = T.mat_decal("cor_decal_dirt_wall", DECALS / "dirt_wall_bottom.png")
    M["d_smudge"] = T.mat_decal("cor_decal_smudge", DECALS / "smudge_hands.png")
    M["d_scuff"] = T.mat_decal("cor_decal_floor_scuff", DECALS / "floor_scuff.png", rough=0.5)
    M["d_tape"] = T.mat_decal("cor_decal_tape_residue", DECALS / "tape_residue.png", rough=0.4)
    M["d_stain"] = T.mat_decal("cor_decal_ceiling_stain", DECALS / "ceiling_water_stain.png")
    return M


def wall_with_openings(M, col, name, axis, fixed, a0, a1, side, openings, z0=0.0, z1=H, low=1.0):
    """axis='x': y=fixed 에 놓인 벽(두께 방향 y). 개구부 [(a_from, a_to, top_z)]. side=+1/-1 은 복도 쪽 면 방향.
    하부(0~low m)는 진한 징두리 페인트, 위는 아이보리."""
    cuts = sorted(openings)
    segs, cur = [], a0
    for (o0, o1, top) in cuts:
        if o0 > cur:
            segs.append((cur, o0, z0, z1))
        segs.append((o0, o1, top, z1))       # 개구부 위 인방
        cur = o1
    if cur < a1:
        segs.append((cur, a1, z0, z1))
    t = 0.04   # 복도 쪽 마감층 두께(구조벽은 작업실 GLB 또는 아래 구조체)
    n = 0
    for (s0, s1, zb, zt) in segs:
        if s1 - s0 < 1e-3 or zt - zb < 1e-3:
            continue
        for (lo, hi, mat) in ((zb, min(zt, low), M["wall_low"]), (max(zb, low), zt, M["wall"])):
            if hi - lo < 1e-3:
                continue
            c = (s0 + s1) / 2
            dims = (s1 - s0, t, hi - lo) if axis == "x" else (t, s1 - s0, hi - lo)
            loc = (c, fixed - side * t / 2, (lo + hi) / 2) if axis == "x" else (fixed - side * t / 2, c, (lo + hi) / 2)
            T.box(f"{name}_{n}", dims, loc, mat, 0.002, col=col)
            n += 1
    # 징두리 몰딩 + 걸레받이
    for (s0, s1, zb, zt) in segs:
        if zb > 0.01 or s1 - s0 < 1e-3:
            continue
        c = (s0 + s1) / 2
        for nm, dz, th, mat in (("rail", low, 0.03, M["baseboard"]), ("base", 0.05, 0.1, M["baseboard"])):
            dims = (s1 - s0, 0.015, th) if axis == "x" else (0.015, s1 - s0, th)
            loc = (c, fixed - side * 0.047, dz) if axis == "x" else (fixed - side * 0.047, c, dz)
            T.box(f"{name}_{nm}_{n}", dims, loc, mat, 0.003, col=col)
            n += 1


def steel_door(M, col, name, x, y_face, facing, num, mat=None, wood=False):
    """다른 호실의 철문 (닫힘, 상호작용 없음 — 잠김). facing: +1 = 문 앞면이 +Y."""
    r = T.empty(name, (x, y_face, 0), col, rot=(0, 0, 0 if facing > 0 else math.pi))
    m = mat or M["door"]
    T.box(f"{name}_frame_l", (0.06, 0.1, 2.13), (-0.48, -0.05, 1.065), m, 0.004, col=col, parent=r)
    T.box(f"{name}_frame_r", (0.06, 0.1, 2.13), (0.48, -0.05, 1.065), m, 0.004, col=col, parent=r)
    T.box(f"{name}_frame_t", (1.02, 0.1, 0.06), (0, -0.05, 2.1), m, 0.004, col=col, parent=r)
    T.box(f"{name}_leaf", (0.9, 0.045, 2.07), (0, -0.04, 1.035), m, 0.003, col=col, parent=r)
    for z in (0.55, 1.45):
        T.box(f"{name}_press_{z}", (0.7, 0.004, 0.6), (0, -0.016, z), m, 0.006, col=col, parent=r)
    T.cyl(f"{name}_rose", 0.028, 0.012, (0.36, -0.012, 1.0), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=r)
    T.box(f"{name}_lever", (0.13, 0.018, 0.018), (0.3, 0.008, 1.0), M["chrome"], 0.006, col=col, parent=r)
    T.cyl(f"{name}_lock", 0.016, 0.014, (0.36, -0.012, 1.12), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=r)
    T.cyl(f"{name}_viewer", 0.008, 0.02, (0, -0.012, 1.55), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=r)
    # 호실 번호판 (문 옆 벽)
    T.box(f"{name}_plate", (0.2, 0.008, 0.1), (0.68, -0.004, 1.65), M["rooms"][num], 0.002, col=col, parent=r)
    T.box(f"{name}_threshold", (0.9, 0.12, 0.012), (0, 0.0, 0.006), M["chrome"], 0.002, col=col, parent=r)
    return r


def build_corridor(M, C):
    col = C["arch"]
    L = X1 - X0
    T.box("cor_floor", (L + 0.4, YN - YS, 0.05), ((X0 + X1) / 2, (YN + YS) / 2, -0.025), M["floor"], 0, col=col)
    T.box("cor_ceiling", (L, YN - YS, 0.03), ((X0 + X1) / 2, (YN + YS) / 2, H + 0.015), M["ceiling"], 0, col=col)
    # 남벽 구조체 + 마감 (308호 문 x=2.0, 셔터 x 4.3~6.5, 306호 문 x=9.5)
    T.box("cor_wall_south_struct", (L + 0.4, WT, H), ((X0 + X1) / 2, YS - WT / 2 - 0.04, H / 2), M["wall"], 0, col=col)
    wall_with_openings(M, col, "cor_wall_s", "x", YS, X0, X1, -1,
                       [(1.53, 2.47, 2.1), (4.3, 6.5, 2.35), (9.03, 9.97, 2.1)])
    # 북벽 마감: 303호(x -2.6), 304호=작업실 문(x 0.95), 305호(x 9.0)
    wall_with_openings(M, col, "cor_wall_n", "x", YN, X0, X1, 1,
                       [(-3.07, -2.13, 2.1), (STU_DOOR_X - 0.5, STU_DOOR_X + 0.5, 2.15), (8.53, 9.47, 2.1)])
    T.box("cor_wall_north_struct_w", (X0 * -1 - 0.2, WT, H), ((X0 - 0.2) / 2, YN + WT / 2, H / 2), M["wall"], 0, col=col)
    T.box("cor_wall_north_struct_e", (X1 - 6.2, WT, H), ((6.2 + X1) / 2, YN + WT / 2, H / 2), M["wall"], 0, col=col)
    # 작업실 문 쪽 문틀·번호판 (작업실 GLB의 문짝과 짝)
    T.box("cor_304_plate", (0.2, 0.008, 0.1), (STU_DOOR_X + 0.68, YN - 0.044, 1.65), M["rooms"]["304"], 0.002, col=col)
    # 다른 호실 문
    steel_door(M, col, "cor_door_303", -2.6, YN - 0.04, -1, "303")
    steel_door(M, col, "cor_door_305", 9.0, YN - 0.04, -1, "305", M["door_green"])
    steel_door(M, col, "cor_door_308", 2.0, YS + 0.04, 1, "308")
    steel_door(M, col, "cor_door_306", 9.5, YS + 0.04, 1, "306")
    # 셔터 내린 점포 (가로 골판 슬랫)
    sh = T.empty("cor_shutter", (5.4, YS + 0.06, 0), col)
    slat = T.box("cor_shutter_slat_src", (2.2, 0.03, 0.075), (0, 0, 0.04), M["alu"], 0.012, 3, col=col, parent=sh)
    for k in range(1, 31):
        T.linked_copy(slat, f"cor_shutter_slat_{k:02d}", (0, 0.004 * (k % 2), 0.04 + k * 0.076), col=col, parent=sh)
    T.box("cor_shutter_box", (2.3, 0.3, 0.2), (0, -0.1, 2.42), M["alu"], 0.01, col=col, parent=sh)
    T.box("cor_shutter_bottom", (2.2, 0.05, 0.04), (0, 0, 0.02), M["black"], 0.006, col=col, parent=sh)
    T.box("cor_shutter_lock", (0.06, 0.04, 0.08), (0.6, 0.03, 0.06), M["chrome"], 0.005, col=col, parent=sh)
    # 서쪽 끝 엘리베이터
    ew = T.empty("cor_elevator", (X0 + 0.02, (YN + YS) / 2, 0), col, rot=(0, 0, -math.pi / 2))
    T.box("cor_elev_back", (YN - YS, 0.05, H), (0, 0.03, H / 2), M["wall"], 0, col=col, parent=ew)
    T.box("cor_elev_jamb", (1.2, 0.06, 2.25), (0, -0.01, 1.125), M["chrome"], 0.004, col=col, parent=ew)
    for sx in (-1, 1):
        T.box(f"cor_elev_door_{sx}", (0.5, 0.02, 2.1), (sx * 0.25, -0.05, 1.05), M["chrome"], 0.002, col=col, parent=ew)
    T.box("cor_elev_indicator", (0.18, 0.02, 0.09), (0, -0.05, 2.36), M["elev_floor"], 0.003, col=col, parent=ew)
    T.box("cor_elev_callpanel", (0.08, 0.015, 0.16), (0.78, -0.02, 1.15), M["chrome"], 0.003, col=col, parent=ew)
    for k, z in enumerate((1.19, 1.11)):
        T.cyl(f"cor_elev_btn_{k}", 0.015, 0.01, (0.78, -0.03, z), M["led_red"] if k else M["plastic_white"],
              rot=(math.pi / 2, 0, 0), col=col, parent=ew)
    T.box("cor_wall_west_end", (WT, YN - YS + 0.4, H), (X0 - WT / 2, (YN + YS) / 2, H / 2), M["wall"], 0, col=col)
    # 소화기 (작업실 문 서쪽) + 받침
    fx = T.empty("cor_extinguisher", (0.15, YN - 0.2, 0), col)
    T.lathe("cor_extinguisher_body", [(0.0, 0.0), (0.075, 0.0), (0.08, 0.02), (0.08, 0.42), (0.06, 0.48), (0.022, 0.5), (0.0, 0.5)], 40,
            (0, 0, 0.03), mat=M["red"], col=col, parent=fx)
    T.box("cor_extinguisher_valve", (0.03, 0.06, 0.05), (0, 0, 0.555), M["chrome"], 0.004, col=col, parent=fx)
    T.box("cor_extinguisher_handle", (0.02, 0.12, 0.012), (0, 0.02, 0.59), M["black"], 0.003, col=col, parent=fx,
          rot=(math.radians(12), 0, 0))
    T.cyl("cor_extinguisher_gauge", 0.012, 0.01, (0, -0.032, 0.55), M["plastic_white"], rot=(math.pi / 2, 0, 0), col=col, parent=fx)
    T.curve_tube("cor_extinguisher_hose", [(0.0, 0.03, 0.55), (0.06, 0.07, 0.45), (0.08, 0.06, 0.2), (0.06, 0.03, 0.12)], 0.007,
                 M["rubber"], col=col, parent=fx)
    T.box("cor_extinguisher_stand", (0.2, 0.2, 0.03), (0, 0, 0.015), M["red"], 0.004, col=col, parent=fx)
    T.box("cor_extinguisher_sign", (0.2, 0.006, 0.25), (0.0, 0.17, 1.2), M["red"], 0.003, col=col, parent=fx)
    # 소화전함 (남벽)
    T.box("cor_hydrant_cabinet", (0.75, 0.18, 1.1), (7.5, YS + 0.13, 1.25), M["red"], 0.006, col=col)
    T.box("cor_hydrant_door_label", (0.4, 0.004, 0.4), (7.5, YS + 0.222, 1.45), M["hydrant"], 0.002, col=col)
    T.box("cor_hydrant_handle", (0.02, 0.03, 0.1), (7.8, YS + 0.235, 1.2), M["chrome"], 0.004, col=col)
    # 분전함(전기 패널) 북벽
    T.box("cor_electric_panel", (0.5, 0.08, 0.7), (4.6, YN - 0.08, 1.6), M["door"], 0.004, col=col)
    T.box("cor_electric_panel_lock", (0.03, 0.02, 0.06), (4.8, YN - 0.125, 1.6), M["chrome"], 0.003, col=col)
    # 안내문 + 테이프 자국
    T.box("cor_notice", (0.21, 0.002, 0.297), (3.6, YN - 0.042, 1.5), M["notice"], 0, col=col)
    T.decal_plane("cor_decal_tape_notice", 0.36, 0.42, (3.6, YN - 0.0412, 1.5), (math.pi / 2, 0, math.pi), M["d_tape"], col)
    # 308호 앞 납작한 택배 상자 더미 · 시든 화분
    for k in range(3):
        T.box(f"cor_flat_boxes_{k}", (0.6, 0.02, 0.45), (3.0, YS + 0.12 + k * 0.025, 0.24), M["cardboard"], 0.003, col=col,
              rot=(math.radians(-8 + k * 2), 0, 0))
    T.lathe("cor_plant_pot", [(0.0, 0.0), (0.13, 0.0), (0.17, 0.34), (0.16, 0.34), (0.0, 0.32)], 32, (11.2, YS + 0.3, 0),
            mat=M["ceramic"], col=col)
    T.cyl("cor_plant_soil", 0.155, 0.02, (11.2, YS + 0.3, 0.32), M["soil"], col=col)
    for k in range(9):
        a = k / 9 * math.tau
        lf = T.box(f"cor_plant_leaf_{k}", (0.03, 0.32, 0.002), (11.2 + math.cos(a) * 0.05, YS + 0.3 + math.sin(a) * 0.05, 0.48),
                   M["leaf"], 0, col=col, rot=(math.radians(R.uniform(40, 85)), 0, a + math.pi / 2))
        lf.modifiers.new("Bend", "SIMPLE_DEFORM").deform_method = "BEND"


def fluorescent(M, col, name, loc, lights, energy=55, state="NORMAL", length=1.25):
    """노출형 형광등 기구 (REF 10) — 금속 받침 + 튜브 2개. 광원 마커는 Godot에서 LightFixture로 재구성."""
    r = T.empty(name, loc, col)
    T.box(f"{name}_base", (length, 0.12, 0.05), (0, 0, -0.025), M["plastic_white"], 0.006, col=col, parent=r)
    for k, y in enumerate((-0.03, 0.03)):
        tube = T.cyl(f"{name}_tube_{k}", 0.013, length - 0.08, (0, y, -0.07), M["tube"], rot=(0, math.pi / 2, 0), col=col,
                     parent=r, verts=16)
        T.keep(tube, "light_emitter")
        for sx in (-1, 1):
            T.box(f"{name}_cap_{k}_{sx}", (0.03, 0.03, 0.04), (sx * (length / 2 - 0.03), y, -0.06), M["plastic_white"], 0.004,
                  col=col, parent=r)
    ld = bpy.data.lights.new(f"{name}_light", "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = length - 0.1, 0.06
    ld.energy = energy
    ld.color = (0.9, 0.95, 1.0)
    lo = bpy.data.objects.new(f"{name}_light", ld)
    lo.location = (loc[0], loc[1], loc[2] - 0.09)
    lo["tuv_light_state"] = state
    lo.hide_render = state in ("DEAD", "STORY_OFF")
    T._link(lo, C_["lights"])
    lights.append(lo)
    return r


def build_stairwell(M, C):
    """동쪽 끝 계단실: x 13.0~15.6. 하행(x 13.15~14.3)·상행(x 14.45~15.45) 계단, 은색 원형 난간 (REF 03)."""
    col = C["arch"]
    xa, xb = X1, X1 + 2.6
    ya, yb = YS, 3.4
    T.box("cor_stair_landing", (xb - xa, YN - YS, 0.05), ((xa + xb) / 2, (YN + YS) / 2, -0.025), M["stair"], 0, col=col)
    # 계단실 벽 (도장 콘크리트)
    for nm, dims, loc in (("e", (WT, yb - ya + 0.4, 6.0), (xb + WT / 2, (ya + yb) / 2, 0.5)),
                          ("n", (xb - xa + 0.4, WT, 6.0), ((xa + xb) / 2, yb + WT / 2, 0.5)),
                          ("w", (WT, yb - YN, 6.0), (xa - WT / 2, (YN + yb) / 2, 0.5)),
                          ("s", (xb - xa + 0.4, WT, 6.0), ((xa + xb) / 2, ya - WT / 2, 0.5))):
        T.box(f"cor_stairwell_wall_{nm}", dims, loc, M["stair_wall"], 0.002, col=col)
    T.box("cor_stairwell_ceiling", (xb - xa, yb - ya, 0.1), ((xa + xb) / 2, (ya + yb) / 2, 3.5), M["stair_wall"], 0, col=col)
    rise, run, n = 0.17, 0.28, 10
    # 하행 계단 (y -0.2 → +2.6, z 0 → -1.7)
    for k in range(n):
        z = -(k + 1) * rise
        y = YN + k * run
        T.box(f"cor_stair_down_{k}", (1.15, run + 0.02, 0.05), (13.73, y + run / 2, z + rise - 0.025), M["stair"], 0.004, col=col)
        T.box(f"cor_stair_down_riser_{k}", (1.15, 0.03, rise), (13.73, y + run, z + rise / 2), M["stair_wall"], 0, col=col)
        T.box(f"cor_stair_down_nosing_{k}", (1.15, 0.03, 0.012), (13.73, y + 0.015, z + rise + 0.006), M["alu"], 0.002, col=col)
    T.box("cor_stair_down_slab", (1.15, n * run, 0.15), (13.73, YN + n * run / 2, -0.95), M["stair_wall"], 0, col=col,
          rot=(-math.atan2(n * rise, n * run), 0, 0))
    T.box("cor_stair_down_landing", (1.3, 0.9, 0.08), (13.73, YN + n * run + 0.45, -n * rise - 0.04), M["stair"], 0, col=col)
    # 상행 계단 (z 0 → +1.7)
    for k in range(n):
        z = k * rise
        y = YN + k * run
        T.box(f"cor_stair_up_{k}", (1.0, run + 0.02, z + rise), (14.95, y + run / 2, (z + rise) / 2), M["stair"], 0.004, col=col)
        T.box(f"cor_stair_up_nosing_{k}", (1.0, 0.03, 0.012), (14.95, y + 0.015, z + rise + 0.006), M["alu"], 0.002, col=col)
    T.box("cor_stair_up_landing", (1.1, 0.9, n * rise), (14.95, YN + n * run + 0.45, n * rise / 2), M["stair"], 0, col=col)
    # 난간 (원형 파이프)
    T.curve_tube("cor_rail_center_top", [(14.37, YN - 0.05, 0.95), (14.37, YN + n * run, 0.95 + n * rise)], 0.022, M["chrome"], col)
    T.curve_tube("cor_rail_center_bottom", [(14.37, YN - 0.05, 0.95), (14.37, YN + n * run, 0.95 - n * rise)], 0.022, M["chrome"], col)
    for k in range(0, n + 1, 2):
        T.cyl(f"cor_rail_post_up_{k}", 0.012, 0.95, (14.37, YN + k * run, k * rise + 0.475), M["chrome"], col=col, verts=12)
        T.cyl(f"cor_rail_post_dn_{k}", 0.012, 0.95, (14.37, YN + k * run, -k * rise + 0.475), M["chrome"], col=col, verts=12)
    T.curve_tube("cor_rail_wall", [(15.55, YN, 0.9), (15.55, YN + n * run, 0.9 + n * rise)], 0.02, M["chrome"], col)
    # 비상구 유도등 (계단 입구 위)
    T.box("cor_exit_sign_stair", (0.36, 0.06, 0.12), (X1 - 0.03, (YN + YS) / 2, 2.3), M["exit"], 0.004, col=col, rot=(0, 0, math.pi / 2))
    return ya, yb


def build_colliders(C):
    cc = C["col"]
    T.collider("cor_floor", (X1 - X0 + 0.4, YN - YS + 0.4, 0.2), ((X0 + X1) / 2, (YN + YS) / 2, -0.1), cc)
    T.collider("cor_ceiling", (X1 - X0 + 3, YN - YS + 0.4, 0.2), ((X0 + X1) / 2 + 1, (YN + YS) / 2, H + 0.1), cc)
    T.collider("cor_wall_s", (X1 - X0 + 3, 0.2, H), ((X0 + X1) / 2 + 1, YS - 0.1, H / 2), cc)
    T.collider("cor_wall_n_w", (X0 * -1 - 0.2, 0.2, H), ((X0 - 0.2) / 2, YN + 0.1, H / 2), cc)
    T.collider("cor_wall_n_e", (X1 - 6.2, 0.2, H), ((6.2 + X1) / 2, YN + 0.1, H / 2), cc)
    T.collider("cor_wall_w", (0.2, 2.2, H), (X0 - 0.1, (YN + YS) / 2, H / 2), cc)
    T.collider("cor_landing", (2.6, YN - YS, 0.2), (X1 + 1.3, (YN + YS) / 2, -0.1), cc)
    T.collider("cor_stairwell_e", (0.2, 6, 5), (X1 + 2.7, 0.7, 0.5), cc)
    T.collider("cor_stairwell_n", (3, 0.2, 5), (X1 + 1.3, 3.5, 0.5), cc)
    T.collider("cor_stairwell_w", (0.2, 3.6, 5), (X1 - 0.1, 1.6, 0.5), cc)
    n, rise, run = 10, 0.17, 0.28
    ang = math.atan2(n * rise, n * run)
    ln = math.hypot(n * rise, n * run)
    T.collider("cor_ramp_down", (1.15, ln, 0.1), (13.73, YN + n * run / 2, -n * rise / 2 - 0.05), cc, rot=(-ang, 0, 0))
    T.collider("cor_ramp_up", (1.0, ln, 0.1), (14.95, YN + n * run / 2, n * rise / 2 - 0.05), cc, rot=(ang, 0, 0))
    T.collider("cor_landing_down", (1.3, 0.9, 0.1), (13.73, YN + n * run + 0.45, -n * rise - 0.05), cc)
    T.collider("cor_landing_up", (1.1, 0.9, 0.1), (14.95, YN + n * run + 0.45, n * rise - 0.05), cc)
    T.collider("cor_rail_divider", (0.06, n * run + 0.3, 2.6), (14.37, YN + n * run / 2, 0.3), cc)
    T.collider("cor_hydrant", (0.75, 0.2, 1.1), (7.5, YS + 0.12, 1.25), cc, kind="convcolonly")
    T.collider("cor_extinguisher", (0.25, 0.25, 0.65), (0.15, YN - 0.2, 0.32), cc, kind="convcolonly")
    T.collider("cor_plant", (0.36, 0.36, 0.6), (11.2, YS + 0.3, 0.3), cc, kind="convcolonly")
    T.collider("cor_flat_boxes", (0.65, 0.15, 0.5), (3.0, YS + 0.15, 0.25), cc, kind="convcolonly")


def build_decals(M, C):
    col = C["props"]
    for i in range(12):
        x = X0 + 0.75 + i * 1.5
        if abs(x - STU_DOOR_X) > 0.8:
            T.decal_plane(f"cor_decal_dirt_n_{i}", 1.5, 0.28, (x, YN - 0.0415, 0.25), (math.pi / 2, 0, math.pi), M["d_dirt"], col)
        T.decal_plane(f"cor_decal_dirt_s_{i}", 1.5, 0.28, (x, YS + 0.0415, 0.25), (math.pi / 2, 0, 0), M["d_dirt"], col)
    for x in (-2.6, STU_DOOR_X, 2.0, 9.0, 9.5):
        y = YS + 0.6 if x in (2.0, 9.5) else YN - 0.6
        T.decal_plane(f"cor_decal_scuff_{x}", 1.0, 1.0, (x, y, 0.0015), (0, 0, R.uniform(0, 3)), M["d_scuff"], col)
    T.decal_plane("cor_decal_smudge_304", 0.25, 0.45, (STU_DOOR_X + 0.62, YN - 0.0425, 1.05), (math.pi / 2, 0, math.pi), M["d_smudge"], col)
    T.decal_plane("cor_decal_ceiling_stain", 0.9, 0.9, (7.0, -1.2, H - 0.0018), (math.pi, 0, 0.7), M["d_stain"], col)


C_ = {}


def main():
    args = sys.argv[1:]
    samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 40
    res = tuple(int(v) for v in args[args.index("--res") + 1].split("x")) if "--res" in args else (1280, 720)
    T.reset_scene()
    signs()
    C = {k: T.collection(v) for k, v in {"arch": "cor_architecture", "props": "cor_props", "lights": "cor_lights",
                                          "col": "cor_collision", "cams": "cor_cameras"}.items()}
    C_.update(C)
    M = build_materials()
    lights = []
    build_corridor(M, C)
    build_stairwell(M, C)
    for i, x in enumerate([-3.5, -0.5, 2.5, 5.5, 8.5, 11.5]):
        fluorescent(M, C["arch"], f"cor_fluorescent_{i}", (x, (YN + YS) / 2, H), lights, state="FLICKER" if i == 4 else "NORMAL")
    fluorescent(M, C["arch"], "cor_fluorescent_stair_down", (13.73, 2.9, 0.3), lights, state="DEAD", length=0.65)
    fluorescent(M, C["arch"], "cor_fluorescent_stair_up", (14.95, 2.9, 3.45), lights, length=0.65)
    build_colliders(C)
    build_decals(M, C)
    T.empty("cor_spawn_clue_dark_landing", (13.6, 2.85, -1.7), C["props"], rot=(0, 0, 0.7))
    w = bpy.data.worlds.new("cor_world")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.004, 0.005, 1)
    bpy.context.scene.world = w
    cams = {
        "entry": T.camera("CAM_cor_entry", (STU_DOOR_X, -0.45, 1.62), (8.0, -1.2, 1.2), fov_v=62, col=C["cams"]),
        "west": T.camera("CAM_cor_west", (11.5, -1.1, 1.62), (-5.0, -1.1, 1.0), fov_v=62, col=C["cams"]),
        "stairs": T.camera("CAM_cor_stairs", (12.0, -1.5, 1.62), (14.4, 2.0, 0.2), fov_v=62, col=C["cams"]),
        "door304": T.camera("CAM_cor_door304", (2.6, -1.75, 1.62), (STU_DOOR_X, -0.2, 1.0), fov_v=62, col=C["cams"]),
    }
    C["col"].hide_render = True
    BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    print(f"[cor] saved {BLEND}")
    if "--render" in args:
        RENDERS.mkdir(parents=True, exist_ok=True)
        T.setup_render(samples, res, exposure=1.0)
        # 렌더에서는 작업실 셸도 함께 (같은 좌표) — 작업실 .blend의 건축 컬렉션을 붙여 넣음
        stu = ROOT / "art" / "blender" / "environments" / "studio" / "stu_studio.blend"
        if stu.exists():
            with bpy.data.libraries.load(str(stu), link=False) as (src, dst):
                dst.collections = [c for c in src.collections if c in ("stu_architecture",)]
            for c in dst.collections:
                bpy.context.scene.collection.children.link(c)
        for name, cam in cams.items():
            T.render(cam, str(RENDERS / f"cor_{name}.png"))
            print("[cor] rendered", name)
    merged, kept, src = T.export_optimized(str(GLB), [C["arch"], C["props"]], C["col"], "cor")
    print(f"[cor] GLB: source meshes={src} -> merged static={merged} + kept={kept}")


if __name__ == "__main__":
    main()
