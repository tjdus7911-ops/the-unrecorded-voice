"""현대 음성 복원 작업실 (stu_) — Blender 5.3 빌드 스크립트

설계: docs/design/space_studio.md  (내부 6.0 × 5.0 m, 천장 2.65 m, 원점 = 남서쪽 바닥 모서리)
실행: python3 tools/blender/build_studio.py [--render] [--views entry,front,...] [--samples 48]
출력: art/blender/environments/studio/stu_studio.blend
      game/assets/models/environments/stu_studio.glb
      art/renders/studio/*.png (--render)
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
T.PBR_DIR = ROOT / "game" / "assets" / "textures" / "pbr"
DECALS = ROOT / "game" / "assets" / "textures" / "decals"
PROPS_BLEND = ROOT / "art" / "blender" / "props"
CASSETTE_JSON = ROOT / "game" / "data" / "levels" / "stu_cassettes.json"
CASSETTE_GLB = ROOT / "game" / "assets" / "models" / "props" / "prop_cassette_shelf.gltf"
TEX = ROOT / "game" / "assets" / "textures" / "stu"
BLEND = ROOT / "art" / "blender" / "environments" / "studio" / "stu_studio.blend"
GLB = ROOT / "game" / "assets" / "models" / "environments" / "stu_studio.gltf"
RENDERS = ROOT / "art" / "renders" / "studio"

W, D, H = 6.0, 5.0, 2.65          # 실내 폭(x), 깊이(y), 천장고
WT = 0.2                          # 벽 두께
DOOR_X, DOOR_W, DOOR_H = 0.95, 0.9, 2.1
WIN_X0, WIN_X1, WIN_Z0, WIN_Z1 = 1.3, 4.7, 0.85, 2.25
R = T.RNG


# ======================================================================= materials
def build_materials():
    P = T.mat_pbr
    M = {}
    M["wall"] = P("stu_wall_paint", "wall_paint")
    M["floor"] = P("stu_floor_decotile", "floor_decotile")
    M["ceiling"] = P("stu_ceiling_tex", "ceiling_tex")
    M["baseboard"] = P("stu_baseboard_pvc", "baseboard_pvc")
    M["alu"] = P("stu_aluminium", "brushed_aluminium")
    M["alu_dark"] = P("stu_anodized_dark", "anodized_dark")
    M["steel_door"] = P("stu_steel_door_paint", "steel_door_paint")
    M["chrome"] = P("stu_brushed_steel", "brushed_steel")
    M["black_metal"] = P("stu_powdercoat_black", "powdercoat_black")
    M["walnut"] = P("stu_walnut_veneer", "walnut_veneer")
    M["oak"] = P("stu_oak_laminate", "oak_laminate")
    M["shelf_white"] = P("stu_melamine_offwhite", "melamine_offwhite")
    M["glass"] = T.mat_glass("stu_window_glass")
    M["glass_clean"] = T.mat_glass("stu_glass_clean", 0.02, rain=False)
    M["plastic_dark"] = P("stu_abs_charcoal", "abs_charcoal")
    M["plastic_grey"] = P("stu_abs_grey", "abs_grey")
    M["plastic_white"] = P("stu_abs_white", "abs_white")
    M["blind"] = P("stu_blind_slat_painted", "abs_white", rough_mul=0.8)   # 도장 알루미늄 블라인드 (확산 반사)
    M["silver_panel"] = P("stu_silver_faceplate", "silver_faceplate")
    M["rubber"] = P("stu_rubber", "rubber_black")
    M["foam"] = P("stu_acoustic_foam", "acoustic_foam")
    M["sofa"] = P("stu_sofa_fabric", "sofa_fabric")
    M["chair_mesh"] = P("stu_chair_mesh", "chair_mesh")
    M["rug"] = P("stu_rug_wool", "rug_wool")
    M["blanket"] = P("stu_blanket_flannel", "blanket_flannel")
    M["lampshade"] = P("stu_lampshade_linen", "lampshade_linen")
    M["paper"] = P("stu_paper", "paper")
    M["cardboard"] = P("stu_cardboard", "cardboard")
    M["ceramic"] = P("stu_ceramic_glaze", "ceramic_glaze")
    M["sill"] = P("stu_sill_stone", "sill_stone")
    M["cone"] = P("stu_speaker_cone", "rubber_black", rough_mul=0.9)
    M["leaf"] = P("stu_plant_leaf", "leaf")
    M["soil"] = P("stu_soil", "soil")
    M["binder"] = [P(f"stu_binder_{i}", "abs_grey", tint=c) for i, c in enumerate([(0.35, 0.6, 1.2), (0.5, 0.5, 0.5), (1.4, 0.4, 0.3)])]
    M["book"] = [P(f"stu_book_{i}", "paper", tint=c) for i, c in enumerate([(0.55, 0.15, 0.1), (0.12, 0.18, 0.3), (0.85, 0.8, 0.7),
                                                                           (0.2, 0.3, 0.2), (0.15, 0.15, 0.15)])]
    M["screen"] = T.mat_image("stu_monitor_screen", str(TEX / "stu_monitor_screen.png"), emission=1.1, rough=0.25)
    M["screen_off"] = T.mat_basic("stu_screen_off", (0.01, 0.01, 0.012), 0.15)
    M["clock_face"] = T.mat_image("stu_clock_face", str(TEX / "stu_clock_face.png"), rough=0.5)
    M["calendar"] = T.mat_image("stu_calendar", str(TEX / "stu_calendar.png"), rough=0.8)
    M["archive"] = T.mat_image("stu_archive_label", str(TEX / "stu_archive_box_label.png"), rough=0.85)
    M["spine_atlas"] = T.mat_image("stu_cassette_spine_atlas", str(ROOT / "game/assets/textures/props/prop_cassette_spine_atlas.png"), rough=0.6)
    M["spine_atlas"]["fit"] = False
    M["inserts"] = [T.mat_image(f"stu_cassette_insert_{i:02d}", str(TEX / f"stu_cassette_insert_{i:02d}.png"), rough=0.6)
                    for i in range(1, 9)]
    M["cassette_shell"] = T.mat_basic("stu_cassette_case", (0.22, 0.23, 0.25), 0.18, 0, 0.02, 40, 0.0)   # 반투명 스모크 케이스 느낌
    M["vu"] = T.mat_emission("stu_vu_meter", (1.0, 0.62, 0.25), 1.6, (0.9, 0.8, 0.6))
    M["led_red"] = T.mat_emission("stu_led_red", (1.0, 0.08, 0.04), 6.0)
    M["led_green"] = T.mat_emission("stu_led_green", (0.25, 1.0, 0.35), 3.0)
    M["bulb_warm"] = T.mat_emission("stu_bulb_warm", (1.0, 0.70, 0.40), 30.0, (0.9, 0.85, 0.8))
    M["led_panel_off"] = P("stu_led_panel_diffuser", "abs_white")
    M["city_bldg"] = [T.mat_city_windows(f"ext_city_bldg_{i}", i) for i in range(4)]
    M["ext_concrete"] = P("ext_concrete_wet", "concrete_wet")
    M["sticky"] = T.mat_basic("stu_sticky_note", (0.95, 0.85, 0.35), 0.7)
    M["d_dirt"] = T.mat_decal("stu_decal_dirt_wall", DECALS / "dirt_wall_bottom.png")
    M["d_smudge"] = T.mat_decal("stu_decal_smudge", DECALS / "smudge_hands.png")
    M["d_stain"] = T.mat_decal("stu_decal_ceiling_stain", DECALS / "ceiling_water_stain.png")
    M["d_scuff"] = T.mat_decal("stu_decal_floor_scuff", DECALS / "floor_scuff.png", rough=0.5)
    M["d_tape"] = T.mat_decal("stu_decal_tape_residue", DECALS / "tape_residue.png", rough=0.4)
    return M


# ======================================================================= architecture
def build_shell(M, C):
    col = C["arch"]
    # 바닥 / 천장
    T.box("stu_floor", (W, D, 0.05), (W / 2, D / 2, -0.025), M["floor"], 0, col=col)
    ceil = T.box("stu_ceiling", (W, D, 0.03), (W / 2, D / 2, H + 0.015), M["ceiling"], 0, col=col)
    ceil["tuv_ceiling"] = True
    # 서·동 벽
    T.box("stu_wall_west", (WT, D + 2 * WT, H), (-WT / 2, D / 2, H / 2), M["wall"], 0.003, col=col)
    T.box("stu_wall_east", (WT, D + 2 * WT, H), (W + WT / 2, D / 2, H / 2), M["wall"], 0.003, col=col)
    # 남벽 (출입문 개구부)
    d0, d1 = DOOR_X - DOOR_W / 2 - 0.05, DOOR_X + DOOR_W / 2 + 0.05
    T.box("stu_wall_south_a", (d0 + WT, WT, H), ((d0 - WT) / 2, -WT / 2, H / 2), M["wall"], 0.003, col=col)
    T.box("stu_wall_south_b", (W + WT - d1, WT, H), ((d1 + W + WT) / 2, -WT / 2, H / 2), M["wall"], 0.003, col=col)
    T.box("stu_wall_south_head", (d1 - d0, WT, H - DOOR_H - 0.05),
          ((d0 + d1) / 2, -WT / 2, (H + DOOR_H + 0.05) / 2), M["wall"], 0.003, col=col)
    # 북벽 (창 개구부)
    T.box("stu_wall_north_a", (WIN_X0 + WT, WT, H), ((WIN_X0 - WT) / 2, D + WT / 2, H / 2), M["wall"], 0.003, col=col)
    T.box("stu_wall_north_b", (W + WT - WIN_X1, WT, H), ((WIN_X1 + W + WT) / 2, D + WT / 2, H / 2), M["wall"], 0.003, col=col)
    T.box("stu_wall_north_sill", (WIN_X1 - WIN_X0, WT, WIN_Z0), ((WIN_X0 + WIN_X1) / 2, D + WT / 2, WIN_Z0 / 2), M["wall"], 0.003, col=col)
    T.box("stu_wall_north_head", (WIN_X1 - WIN_X0, WT, H - WIN_Z1), ((WIN_X0 + WIN_X1) / 2, D + WT / 2, (H + WIN_Z1) / 2), M["wall"], 0.003, col=col)
    # 걸레받이
    bb = M["baseboard"]
    T.box("stu_baseboard_w", (0.012, D, 0.08), (0.006, D / 2, 0.04), bb, 0.002, col=col)
    T.box("stu_baseboard_e", (0.012, D, 0.08), (W - 0.006, D / 2, 0.04), bb, 0.002, col=col)
    T.box("stu_baseboard_n", (W, 0.012, 0.08), (W / 2, D - 0.006, 0.04), bb, 0.002, col=col)
    T.box("stu_baseboard_s", (W - d1, 0.012, 0.08), ((W + d1) / 2, 0.006, 0.04), bb, 0.002, col=col)
    T.box("stu_baseboard_s2", (d0, 0.012, 0.08), (d0 / 2, 0.006, 0.04), bb, 0.002, col=col)
    # 천장 몰딩 (갭 숨김)
    for nm, dims, loc in [("n", (W, 0.025, 0.04), (W / 2, D - 0.012, H - 0.02)),
                          ("s", (W, 0.025, 0.04), (W / 2, 0.012, H - 0.02)),
                          ("w", (0.025, D, 0.04), (0.012, D / 2, H - 0.02)),
                          ("e", (0.025, D, 0.04), (W - 0.012, D / 2, H - 0.02))]:
        T.box(f"stu_ceiling_trim_{nm}", dims, loc, M["alu"], 0.002, col=col)

    # 충돌체 (Godot)
    cc = C["col"]
    T.collider("stu_floor", (W + 0.4, D + 0.4, 0.2), (W / 2, D / 2, -0.1), cc)
    T.collider("stu_ceiling", (W + 0.4, D + 0.4, 0.2), (W / 2, D / 2, H + 0.1), cc)
    T.collider("stu_wall_w", (WT, D + 0.4, H), (-WT / 2, D / 2, H / 2), cc)
    T.collider("stu_wall_e", (WT, D + 0.4, H), (W + WT / 2, D / 2, H / 2), cc)
    T.collider("stu_wall_n", (W + 0.4, WT, H), (W / 2, D + WT / 2, H / 2), cc)
    T.collider("stu_wall_s_a", (d0 + WT, WT, H), ((d0 - WT) / 2, -WT / 2, H / 2), cc)
    T.collider("stu_wall_s_b", (W + WT - d1, WT, H), ((d1 + W + WT) / 2, -WT / 2, H / 2), cc)
    T.collider("stu_wall_s_head", (d1 - d0, WT, H - DOOR_H), ((d0 + d1) / 2, -WT / 2, (H + DOOR_H) / 2), cc)


def build_window(M, C):
    col = C["arch"]
    alu, glass = M["alu"], M["glass"]
    cx, wy = (WIN_X0 + WIN_X1) / 2, D + 0.13           # 창틀은 벽 중간보다 바깥쪽
    ww, wh = WIN_X1 - WIN_X0, WIN_Z1 - WIN_Z0
    root = T.empty("stu_window", (cx, wy, WIN_Z0), col)
    f = 0.05
    T.box("stu_window_frame_bottom", (ww, 0.1, f), (0, 0, f / 2), alu, 0.003, col=col, parent=root)
    T.box("stu_window_frame_top", (ww, 0.1, f), (0, 0, wh - f / 2), alu, 0.003, col=col, parent=root)
    T.box("stu_window_frame_l", (f, 0.1, wh), (-ww / 2 + f / 2, 0, wh / 2), alu, 0.003, col=col, parent=root)
    T.box("stu_window_frame_r", (f, 0.1, wh), (ww / 2 - f / 2, 0, wh / 2), alu, 0.003, col=col, parent=root)
    # 미서기 창 2짝 (서로 다른 레일)
    sw = (ww - 2 * f) / 2 + 0.04
    for i, (x, y) in enumerate([(-sw / 2 + 0.02 - 0.0, -0.022), (sw / 2 - 0.02, 0.022)]):
        s = T.empty(f"stu_window_sash_{i}", (x, y, f), col, parent=root)
        sh = wh - 2 * f
        sf = 0.035
        T.box(f"stu_window_sash_{i}_b", (sw, 0.035, sf), (0, 0, sf / 2), alu, 0.002, col=col, parent=s)
        T.box(f"stu_window_sash_{i}_t", (sw, 0.035, sf), (0, 0, sh - sf / 2), alu, 0.002, col=col, parent=s)
        T.box(f"stu_window_sash_{i}_l", (sf, 0.035, sh), (-sw / 2 + sf / 2, 0, sh / 2), alu, 0.002, col=col, parent=s)
        T.box(f"stu_window_sash_{i}_r", (sf, 0.035, sh), (sw / 2 - sf / 2, 0, sh / 2), alu, 0.002, col=col, parent=s)
        T.keep(T.box(f"stu_window_sash_{i}_glass", (sw - 2 * sf, 0.006, sh - 2 * sf), (0, 0, sh / 2), glass, 0, col=col, parent=s), "rain_glass")
        # 손잡이 (크레센트)
        hx = sw / 2 - 0.05 if i == 0 else -sw / 2 + 0.05
        T.box(f"stu_window_sash_{i}_latch", (0.02, 0.03, 0.07), (hx, -0.03, sh * 0.5), M["chrome"], 0.004, col=col, parent=s)
    # 내부 창대 (인조대리석)
    T.box("stu_window_sill", (ww + 0.1, 0.18, 0.025), (cx, D + 0.05, WIN_Z0 - 0.012),
          M["sill"], 0.004, col=col)
    # 알루미늄 블라인드 2개 — 절반 정도 내려오고 살이 기울어짐 (창밖이 틈으로 보임)
    for i, bx in enumerate([WIN_X0 + ww * 0.25, WIN_X0 + ww * 0.75]):
        bw = ww / 2 - 0.04
        b = T.empty(f"stu_blind_{i}", (bx, D - 0.05, WIN_Z1 - 0.02), col)
        T.box(f"stu_blind_{i}_headrail", (bw, 0.05, 0.04), (0, 0, 0), M["alu"], 0.004, col=col, parent=b)
        drop = 0.95 if i == 0 else 0.55
        n = int(drop / 0.022)
        slat = T.box(f"stu_blind_{i}_slat_src", (bw - 0.01, 0.025, 0.0012), (0, 0, -0.04),
                     M["blind"], 0, col=col, parent=b,
                     rot=(math.radians(38), 0, 0))
        for k in range(1, n):
            T.linked_copy(slat, f"stu_blind_{i}_slat_{k:02d}", (0, 0, -0.04 - k * 0.022),
                          (math.radians(38 + R.uniform(-3, 3)), 0, math.radians(R.uniform(-0.6, 0.6))), col, b)
        T.box(f"stu_blind_{i}_bottomrail", (bw, 0.03, 0.012), (0, 0, -0.06 - n * 0.022), M["alu"], 0.003, col=col, parent=b)
        T.cyl(f"stu_blind_{i}_wand", 0.005, 0.6, (bw / 2 - 0.03, -0.03, -0.32), M["glass_clean"], col=col, parent=b, verts=8)


def build_door(M, C):
    col = C["arch"]
    st = M["steel_door"]
    # 문틀 (철재 케이싱)
    x0, x1 = DOOR_X - DOOR_W / 2, DOOR_X + DOOR_W / 2
    for nm, dims, loc in [("l", (0.06, WT + 0.02, DOOR_H + 0.06), (x0 - 0.03, -WT / 2, (DOOR_H + 0.06) / 2)),
                          ("r", (0.06, WT + 0.02, DOOR_H + 0.06), (x1 + 0.03, -WT / 2, (DOOR_H + 0.06) / 2)),
                          ("t", (DOOR_W + 0.12, WT + 0.02, 0.06), (DOOR_X, -WT / 2, DOOR_H + 0.03))]:
        T.box(f"stu_doorframe_{nm}", dims, loc, st, 0.004, col=col)
    T.box("stu_door_threshold", (DOOR_W, WT, 0.012), (DOOR_X, -WT / 2, 0.006), M["chrome"], 0.002, col=col)
    # 문짝 — 원점 = 경첩 축 (서쪽, 실내 쪽). 안쪽(+Y)으로 열림.
    hinge = T.empty("stu_door", (x0 + 0.005, -0.03, 0.0), col)
    hinge["tuv_anim"] = "door_hinge_z"
    T.keep(hinge, "door")
    leaf = T.box("stu_door_leaf", (DOOR_W - 0.01, 0.045, DOOR_H - 0.01), (0, 0, 0.005), st, 0.003,
                 col=col, parent=hinge, pivot=(-0.5, 0, -0.5))
    # 문짝 패널 라인 (프레스 철문 디테일)
    for z in (0.55, 1.45):
        T.box(f"stu_door_press_{z}", (DOOR_W - 0.2, 0.004, 0.6), ((DOOR_W - 0.01) / 2, 0.0235, z), st, 0.006, col=col, parent=hinge)
    # 레버 손잡이 양면 + 도어락(아날로그 열쇠 실린더)
    hx = DOOR_W - 0.08
    for side, y in (("in", 0.032), ("out", -0.032)):
        T.cyl(f"stu_door_rose_{side}", 0.028, 0.01, (hx, y, 1.0), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=hinge)
        T.box(f"stu_door_lever_{side}", (0.13, 0.018, 0.018), (hx - 0.06, y * 1.6, 1.0), M["chrome"], 0.006, col=col, parent=hinge)
        T.cyl(f"stu_door_lock_{side}", 0.016, 0.012, (hx, y, 1.12), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=hinge)
    T.cyl("stu_door_viewer", 0.008, 0.05, (DOOR_W / 2, 0, 1.55), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=hinge)
    # 도어클로저 (실내 상단)
    T.box("stu_door_closer_body", (0.26, 0.055, 0.06), (0.3, 0.05, DOOR_H - 0.09), M["alu"], 0.008, col=col, parent=hinge)
    T.box("stu_door_closer_arm", (0.28, 0.015, 0.015), (0.45, 0.1, DOOR_H - 0.06), M["black_metal"], 0.003, col=col, parent=hinge,
          rot=(0, 0, math.radians(-12)))
    leaf["tuv_interact"] = "door"
    # 문 충돌체는 Godot에서 경첩에 붙는 AnimatableBody3D로 생성 (열고 닫을 때 함께 회전)


def build_ceiling_fixtures(M, C, lights):
    col = C["arch"]
    for i, x in enumerate([2.1, 4.5]):
        p = T.empty(f"stu_ceiling_panel_{i}", (x, 2.7, H - 0.005), col)
        T.box(f"stu_ceiling_panel_{i}_frame", (0.6, 0.6, 0.012), (0, 0, -0.006), M["alu"], 0.002, col=col, parent=p)
        T.keep(T.box(f"stu_ceiling_panel_{i}_diffuser", (0.57, 0.57, 0.004), (0, 0, -0.013), M["led_panel_off"], 0, col=col, parent=p), "light_emitter")
        ld = bpy.data.lights.new(f"stu_light_ceiling_{i}", "AREA")
        ld.shape = "SQUARE"
        ld.size = 0.55
        ld.energy = 140
        ld.color = (0.93, 0.96, 1.0)
        lo = bpy.data.objects.new(f"stu_light_ceiling_{i}", ld)
        lo.location = (x, 2.7, H - 0.03)
        lo.hide_render = True                    # SCENE 02: 꺼진 상태
        lo["tuv_light_state"] = "STORY_OFF"
        T._link(lo, C["lights"])
        lights.append(lo)


# ======================================================================= furniture
def build_desk(M, C):
    col = C["furn"]
    root = T.empty("stu_desk", (3.0, 4.43, 0), col)
    top_z = 0.74
    T.box("stu_desk_top", (2.2, 0.75, 0.028), (0, 0, top_z - 0.014), M["walnut"], 0.003, col=col, parent=root)
    T.box("stu_desk_top_edge", (2.2, 0.004, 0.028), (0, -0.377, top_z - 0.014), M["black_metal"], 0.001, col=col, parent=root)
    # 철제 프레임 다리 (사각 파이프) + 앞뒤 프레임
    for sx in (-1, 1):
        x = sx * 1.05
        for sy in (-1, 1):
            T.box(f"stu_desk_leg_{sx}_{sy}", (0.04, 0.04, top_z - 0.03), (x, sy * 0.32, (top_z - 0.03) / 2),
                  M["black_metal"], 0.004, col=col, parent=root)
        T.box(f"stu_desk_rail_side_{sx}", (0.03, 0.6, 0.04), (x, 0, top_z - 0.05), M["black_metal"], 0.003, col=col, parent=root)
        T.box(f"stu_desk_foot_{sx}", (0.05, 0.7, 0.02), (x, 0, 0.01), M["black_metal"], 0.003, col=col, parent=root)
    T.box("stu_desk_rail_back", (2.06, 0.03, 0.05), (0, 0.32, top_z - 0.055), M["black_metal"], 0.003, col=col, parent=root)
    # 서랍 페데스탈 (우측) — 서랍 3개는 개별 오브젝트, 원점 = 서랍 앞면 중앙, -Y로 인출
    ped = T.empty("stu_desk_pedestal", (0.79, 0.0, 0), col, parent=root)
    T.box("stu_desk_ped_body", (0.42, 0.66, top_z - 0.05), (0, 0.02, (top_z - 0.05) / 2), M["walnut"], 0.003, col=col, parent=ped)
    hz = [0.58, 0.40, 0.17]
    hh = [0.14, 0.18, 0.26]
    for i, (z, h) in enumerate(zip(hz, hh)):
        dr = T.empty(f"stu_desk_drawer_{i}", (0, -0.312, z), col, parent=ped)
        dr["tuv_anim"] = "drawer_slide_-y"
        T.keep(dr, "drawer")
        dr["tuv_interact"] = "drawer"
        T.box(f"stu_desk_drawer_{i}_front", (0.40, 0.018, h - 0.008), (0, -0.009, 0), M["walnut"], 0.003, col=col, parent=dr)
        # 요구사항 20: 속이 빈 서랍 (바닥판 + 옆판 2 + 뒤판). 예전엔 꽉 찬 상자라 안의 손전등이 묻혀 보이지 않았다
        bh, t, bz = h - 0.04, 0.012, -0.01
        T.box(f"stu_desk_drawer_{i}_bottom", (0.36, 0.56, 0.01), (0, 0.28, bz - bh / 2 + 0.005), M["oak"], 0.001, col=col, parent=dr)
        for sx in (-1, 1):
            T.box(f"stu_desk_drawer_{i}_side_{sx}", (t, 0.56, bh), (sx * (0.18 - t / 2), 0.28, bz), M["oak"], 0.002, col=col, parent=dr)
        T.box(f"stu_desk_drawer_{i}_back", (0.36 - 2 * t, t, bh), (0, 0.56 - t / 2, bz), M["oak"], 0.002, col=col, parent=dr)
        T.box(f"stu_desk_drawer_{i}_inner_front", (0.36 - 2 * t, t, bh), (0, t / 2, bz), M["oak"], 0.002, col=col, parent=dr)
        T.box(f"stu_desk_drawer_{i}_pull", (0.14, 0.02, 0.012), (0, -0.025, h / 2 - 0.03), M["chrome"], 0.004, col=col, parent=dr)
    # 상판 두께만 충돌 (0.6 m 위) — 몸은 막히고, 책상 아래(EVENT 07 테이프)는 시선·조사 광선이 닿는다
    T.collider("stu_desk", (2.2, 0.75, top_z - 0.6), (3.0, 4.43, (top_z + 0.6) / 2), C["col"], kind="convcolonly")


def build_chair(M, C):
    col = C["furn"]
    root = T.empty("stu_chair", (2.95, 3.6, 0), col, rot=(0, 0, math.radians(172)))   # 등받이가 책상 반대쪽(앉은 사람 뒤)
    T.keep(root)          # 스토리: 시야 밖에서 의자 방향이 바뀐다 (요구사항 11 EVENT 05)
    # 5발 베이스 + 캐스터
    for i in range(5):
        a = i / 5 * math.tau
        T.box(f"stu_chair_spoke_{i}", (0.3, 0.045, 0.03), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.085),
              M["plastic_dark"], 0.01, 3, col=col, parent=root, rot=(0, math.radians(-4), a))
        T.cyl(f"stu_chair_caster_{i}", 0.025, 0.022, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.03), M["plastic_dark"],
              rot=(math.pi / 2, 0, a + math.pi / 2), col=col, parent=root, verts=16)
    T.cyl("stu_chair_hub", 0.05, 0.06, (0, 0, 0.09), M["plastic_dark"], col=col, parent=root)
    T.cyl("stu_chair_gaslift", 0.025, 0.3, (0, 0, 0.26), M["chrome"], col=col, parent=root)
    T.cyl("stu_chair_gas_sleeve", 0.032, 0.14, (0, 0, 0.17), M["plastic_dark"], col=col, parent=root)
    T.box("stu_chair_mech", (0.24, 0.24, 0.05), (0, 0, 0.43), M["black_metal"], 0.01, col=col, parent=root)
    seat = T.box("stu_chair_seat", (0.5, 0.48, 0.08), (0, 0, 0.49), M["chair_mesh"], 0.03, 4, col=col, parent=root)
    T.wrinkle(seat, 0.004, 0.05, 2)
    # 등받이 프레임 + 메쉬
    T.box("stu_chair_back_spine", (0.06, 0.03, 0.32), (0, 0.27, 0.62), M["plastic_dark"], 0.01, col=col, parent=root,
          rot=(math.radians(-8), 0, 0))
    back = T.box("stu_chair_back", (0.46, 0.05, 0.52), (0, 0.3, 0.92), M["chair_mesh"], 0.025, 4, col=col, parent=root,
                 rot=(math.radians(-12), 0, 0))
    T.wrinkle(back, 0.003, 0.06, 2, seed=1)
    for sx in (-1, 1):
        T.box(f"stu_chair_arm_post_{sx}", (0.03, 0.05, 0.2), (sx * 0.27, 0.05, 0.56), M["plastic_dark"], 0.008, col=col, parent=root)
        T.box(f"stu_chair_arm_pad_{sx}", (0.07, 0.24, 0.025), (sx * 0.27, 0.02, 0.67), M["rubber"], 0.01, 3, col=col, parent=root)
    T.collider("stu_chair", (0.6, 0.6, 1.0), (2.95, 3.6, 0.5), C["col"], kind="convcolonly")


def build_sofa(M, C):
    col = C["furn"]
    root = T.empty("stu_sofa", (5.55, 2.0, 0), col, rot=(0, 0, math.radians(90)))   # 서쪽(-X)을 바라봄
    L, Dp = 1.95, 0.88
    for sx in (-1, 1):
        for sy in (-1, 1):
            T.cyl(f"stu_sofa_leg_{sx}{sy}", 0.022, 0.1, (sx * (L / 2 - 0.08), sy * (Dp / 2 - 0.08), 0.05), M["walnut"],
                  col=col, parent=root, r2=0.016, verts=12)
    T.box("stu_sofa_base", (L, Dp, 0.22), (0, 0, 0.21), M["sofa"], 0.02, 3, col=col, parent=root)
    for sx in (-1, 1):
        a = T.box(f"stu_sofa_arm_{sx}", (0.16, Dp, 0.36), (sx * (L / 2 - 0.08), 0, 0.42), M["sofa"], 0.05, 4, col=col, parent=root)
        T.wrinkle(a, 0.004, 0.08, 2, seed=sx + 5)
    for i, x in enumerate((-0.41, 0.41)):
        s = T.box(f"stu_sofa_seat_cushion_{i}", (0.8, 0.62, 0.15), (x, -0.08, 0.39 - i * 0.008), M["sofa"], 0.05, 4,
                  col=col, parent=root, rot=(0, math.radians(R.uniform(-1, 1)), 0))
        T.wrinkle(s, 0.007, 0.07, 2, seed=i)
        # 앉았던 자국: 쿠션 가운데가 살짝 꺼짐
        sag = s.modifiers.new("Sag", "SIMPLE_DEFORM")
        sag.deform_method = "BEND"
        sag.angle = math.radians(4 + 3 * i)
        sag.deform_axis = "Y"
        b = T.box(f"stu_sofa_back_cushion_{i}", (0.8, 0.2, 0.46), (x, 0.31, 0.64), M["sofa"], 0.06, 4,
                  col=col, parent=root, rot=(math.radians(-14 - i * 3), 0, math.radians(R.uniform(-2, 2))))
        T.wrinkle(b, 0.008, 0.07, 2, seed=i + 2)
    T.box("stu_sofa_backframe", (L, 0.14, 0.42), (0, 0.38, 0.53), M["sofa"], 0.03, 3, col=col, parent=root)
    # 던져 둔 담요
    bl = T.box("stu_sofa_blanket", (0.55, 0.62, 0.05), (0.55, -0.05, 0.49), M["blanket"],
               0.024, 4, col=col, parent=root, rot=(0.05, 0.08, 0.3))
    T.wrinkle(bl, 0.018, 0.05, 2, seed=9)
    T.collider("stu_sofa", (Dp, L, 0.8), (5.55, 2.0, 0.4), C["col"], kind="convcolonly")


def build_coffee_table(M, C):
    col = C["furn"]
    root = T.empty("stu_coffee_table", (4.45, 1.95, 0), col)
    T.box("stu_rug", (1.7, 2.3, 0.012), (0.35, 0.05, 0.006), M["rug"], 0.004, col=col, parent=root)
    T.box("stu_coffee_top", (0.55, 1.0, 0.03), (0, 0, 0.41), M["oak"], 0.004, col=col, parent=root)
    T.box("stu_coffee_shelf", (0.48, 0.92, 0.018), (0, 0, 0.12), M["oak"], 0.003, col=col, parent=root)
    for sx in (-1, 1):
        for sy in (-1, 1):
            T.box(f"stu_coffee_leg_{sx}{sy}", (0.03, 0.03, 0.4), (sx * 0.24, sy * 0.46, 0.2), M["black_metal"], 0.003,
                  col=col, parent=root)
    T.collider("stu_coffee_table", (0.55, 1.0, 0.43), (4.45, 1.95, 0.215), C["col"], kind="convcolonly")
    return root


CASS = []   # (matrix_world, insert_idx) — Godot MultiMesh 데이터


def _spine_src(i, M, col):
    sp = T.box(f"stu_cassette_spine_src_{i}", (0.0008, 0.0145, 0.104), (0, 0, -10), M["spine_atlas"], 0, col=col)
    me = sp.data
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    y0, y1, z0, z1 = min(ys), max(ys), min(zs), max(zs)
    uv = me.uv_layers[0].data
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = ((co.z - z0) / (z1 - z0), 1 - (i + 1) / 8 + (co.y - y0) / (y1 - y0) / 8)
    if "uv_m" in me.uv_layers:
        me.uv_layers.remove(me.uv_layers["uv_m"])
    return sp


def build_shelves(M, C):
    col = C["furn"]
    ccol = C["cass"]
    # 카세트 케이스 원본 (세워 꽂힘: 등이 +X 방향) — 게임에서는 MultiMesh 인스턴스
    src_case = T.box("stu_cassette_case_src", (0.069, 0.0165, 0.108), (0, 0, -10), M["cassette_shell"], 0.0012, col=ccol)
    spines = [_spine_src(i, M, ccol) for i in range(8)]
    n_case = 0
    for u, y0 in enumerate([1.95, 3.33]):
        root = T.empty(f"stu_shelf_{u}", (0.0, y0, 0), col)
        L, Dp, Hh = 1.35, 0.32, 2.0
        mt = M["shelf_white"]
        T.box(f"stu_shelf_{u}_side_a", (Dp, 0.018, Hh), (Dp / 2, 0.009, Hh / 2), mt, 0.002, col=col, parent=root)
        T.box(f"stu_shelf_{u}_side_b", (Dp, 0.018, Hh), (Dp / 2, L - 0.009, Hh / 2), mt, 0.002, col=col, parent=root)
        T.box(f"stu_shelf_{u}_back", (0.006, L, Hh), (0.003, L / 2, Hh / 2), mt, 0, col=col, parent=root)
        T.box(f"stu_shelf_{u}_kick", (0.018, L - 0.036, 0.07), (Dp - 0.02, L / 2, 0.035), mt, 0.002, col=col, parent=root)
        levels = [0.07, 0.42, 0.77, 1.12, 1.47, 1.82, Hh - 0.018]
        for k, z in enumerate(levels):
            T.box(f"stu_shelf_{u}_board_{k}", (Dp - 0.01, L - 0.036, 0.018), (Dp / 2 + 0.005, L / 2, z + 0.009), mt, 0.002,
                  col=col, parent=root)
        # 칸 채우기
        for k, z in enumerate(levels[:-1]):
            zb = z + 0.018
            if (u, k) in [(0, 0), (1, 0)]:
                # 맨 아래: 보관 상자
                for b in range(3):
                    bx = T.box(f"stu_shelf_{u}_archive_{b}", (0.3, 0.4, 0.28), (0.16, 0.05 + b * 0.43 + 0.2, zb + 0.14),
                               [M["cardboard"], M["archive"]], 0.006, col=col, parent=root,
                               rot=(0, 0, math.radians(R.uniform(-2, 2))))
                    # 앞면에만 라벨 재질
                    for p in bx.data.polygons:
                        p.material_index = 1 if p.normal.x > 0.9 else 0
                    T.fit_uvs(bx)
                continue
            if (u, k) in [(1, 5)]:
                # 서류 바인더
                for b in range(14):
                    T.box(f"stu_shelf_{u}_binder_{b}", (0.28, 0.055, 0.31), (0.15, 0.06 + b * 0.06, zb + 0.155),
                          M["binder"][b % 3],
                          0.004, col=col, parent=root, rot=(0, 0, 0) if b < 11 else (math.radians(14), 0, 0))
                continue
            y = 0.03
            fill = R.uniform(0.62, 0.96)
            rows = 2 if k in (2, 3, 4) else 1   # 깊은 칸은 앞뒤 2열
            while y < (L - 0.04) * fill:
                if R.random() < 0.06:
                    y += R.uniform(0.02, 0.06)   # 빈 자리
                    continue
                for r in range(rows):
                    x = Dp - 0.06 - r * 0.115
                    tilt = math.radians(R.uniform(-1.2, 1.2))
                    idx = R.randrange(8)
                    cc = T.linked_copy(src_case, f"stu_cassette_{n_case:04d}", (x, y + 0.009, zb + 0.054 + 0.0005),
                                       (0, tilt, 0), ccol, root)
                    T.linked_copy(spines[idx], f"stu_cassette_spine_{n_case:04d}", (x + 0.0349, y + 0.009, zb + 0.054),
                                  (0, tilt, 0), ccol, root)
                    CASS.append((cc, idx, (0.0349, 0, -0.0005)))
                    n_case += 1
                y += 0.0175
            # 가끔 위에 눕혀 둔 테이프
            if R.random() < 0.5:
                for s in range(R.randint(1, 3)):
                    cc = T.linked_copy(src_case, f"stu_cassette_{n_case:04d}", (Dp - 0.1, L - 0.25 + R.uniform(-0.05, 0.05),
                                       zb + 0.009 + s * 0.017),
                                       (math.pi / 2, 0, math.radians(R.uniform(-20, 20))), ccol, root)
                    CASS.append((cc, -1, None))
                    n_case += 1
        T.collider(f"stu_shelf_{u}", (Dp, L, Hh), (Dp / 2, y0 + L / 2, Hh / 2), C["col"], kind="convcolonly")
    for o in [src_case] + spines:
        o.hide_render = True
    return n_case


def export_cassette_instances(C):
    """선반 카세트 → Godot MultiMesh용 JSON (+ 원본 메시 GLB)."""
    import json
    bpy.context.view_layer.update()
    cases, sp = [], []
    for obj, idx, _ in CASS:
        x = T.blender_to_godot_xform(obj.matrix_world)
        cases.append(x)
        if idx >= 0:
            spn = bpy.data.objects.get(obj.name.replace("stu_cassette_", "stu_cassette_spine_"))
            if spn:
                s_ = T.blender_to_godot_xform(spn.matrix_world)
                s_["atlas"] = idx
                sp.append(s_)
    CASSETTE_JSON.parent.mkdir(parents=True, exist_ok=True)
    CASSETTE_JSON.write_text(json.dumps({"_doc": "build_studio.py 생성 — 선반 카세트 인스턴스 (Godot 좌표)",
                                         "cases": cases, "spines": sp}), "utf-8")
    # 원본 메시 (원점에 둔 케이스 1개 + 등 라벨 1개)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    src = bpy.data.objects["stu_cassette_case_src"]
    sp0 = bpy.data.objects["stu_cassette_spine_src_0"]
    for o in (src, sp0):
        o.location = (0, 0, 0)
        o.hide_render = False
        o.select_set(True)
    T.gltf_export(str(CASSETTE_GLB))
    return len(cases), len(sp)


def build_south_cabinet(M, C):
    col = C["furn"]
    root = T.empty("stu_cabinet", (2.35, 0.0, 0), col)
    T.box("stu_cabinet_body", (1.2, 0.4, 0.8), (0, 0.21, 0.42), M["oak"], 0.003, col=col, parent=root)
    T.box("stu_cabinet_plinth", (1.16, 0.36, 0.02), (0, 0.21, 0.01), M["black_metal"], 0.002, col=col, parent=root)
    for i, x in enumerate((-0.3, 0.3)):
        dr = T.empty(f"stu_cabinet_door_{i}", (x + (-0.295 if i == 0 else 0.295), 0.412, 0.42), col, parent=root)
        dr["tuv_anim"] = "door_hinge_z"
        T.keep(dr, "cabinet_door")
        T.box(f"stu_cabinet_door_{i}_panel", (0.59, 0.018, 0.74), (0.295 if i == 0 else -0.295, 0, 0), M["oak"], 0.003,
              col=col, parent=dr)
        T.box(f"stu_cabinet_door_{i}_knob", (0.012, 0.02, 0.1), (0.55 if i == 0 else -0.55, 0.015, 0.25), M["black_metal"], 0.004,
              col=col, parent=dr)
    # 위: 책, 공유기, 작은 화분
    x = -0.55
    for b in range(9):
        h = R.uniform(0.2, 0.27)
        w = R.uniform(0.022, 0.045)
        T.box(f"stu_cabinet_book_{b}", (w, 0.17, h), (x + w / 2, 0.22, 0.82 + h / 2),
              M["book"][b % 5], 0.002, col=col, parent=root)
        x += w + 0.002
    T.box("stu_cabinet_bookend", (0.012, 0.12, 0.15), (x + 0.01, 0.22, 0.895), M["black_metal"], 0.002, col=col, parent=root)
    T.box("stu_router", (0.18, 0.12, 0.03), (0.35, 0.25, 0.835), M["plastic_dark"], 0.006, col=col, parent=root)
    for i in range(4):
        T.box(f"stu_router_led_{i}", (0.004, 0.002, 0.003), (0.29 + i * 0.012, 0.189, 0.835), M["led_green"], 0, col=col, parent=root)
    pot = T.cyl("stu_plant_pot", 0.07, 0.13, (0.05, 0.25, 0.885), M["ceramic"], col=col, parent=root, r2=0.085)
    T.cyl("stu_plant_soil", 0.078, 0.01, (0.05, 0.25, 0.94), M["soil"], col=col, parent=root)
    for i in range(7):
        a = i / 7 * math.tau + R.uniform(-0.3, 0.3)
        lf = T.box(f"stu_plant_leaf_{i}", (0.03, 0.16, 0.002), (0.05 + math.cos(a) * 0.05, 0.25 + math.sin(a) * 0.05, 1.0),
                   M["leaf"], 0, col=col, parent=root, rot=(math.radians(R.uniform(30, 70)), 0, a + math.pi / 2))
        lf.modifiers.new("Bend", "SIMPLE_DEFORM").deform_method = "BEND"
    T.empty("stu_spawn_prop_flashlight", (-0.18, 0.24, 0.82), col, parent=root, rot=(0, 0, math.radians(-70)))
    T.collider("stu_cabinet", (1.2, 0.42, 0.82), (2.35, 0.21, 0.41), C["col"], kind="convcolonly")


# ======================================================================= equipment
def build_cassette_deck(M, col, parent, name, loc, w=0.43, d=0.3, h=0.13, wood=True):
    root = T.empty(name, loc, col, parent=parent)
    T.box(f"{name}_chassis", (w - (0.04 if wood else 0), d, h), (0, 0, h / 2), M["silver_panel"], 0.003, col=col, parent=root)
    if wood:
        for sx in (-1, 1):
            T.box(f"{name}_side_{sx}", (0.02, d, h + 0.004), (sx * (w / 2 - 0.01), 0, h / 2), M["walnut"], 0.003, col=col, parent=root)
    fy = -d / 2 - 0.002
    # 카세트 도어 창
    T.box(f"{name}_tapedoor", (0.15, 0.006, 0.075), (-w * 0.22, fy, h * 0.55), M["plastic_dark"], 0.003, col=col, parent=root)
    T.box(f"{name}_tapewindow", (0.09, 0.002, 0.025), (-w * 0.22, fy - 0.004, h * 0.6), M["glass_clean"], 0, col=col, parent=root)
    # VU 미터 2개
    for i in range(2):
        T.box(f"{name}_vu_{i}", (0.05, 0.003, 0.03), (w * 0.08 + i * 0.06, fy, h * 0.64), M["vu"], 0.002, col=col, parent=root)
    # 조작 버튼 열
    for i in range(6):
        T.box(f"{name}_btn_{i}", (0.022, 0.012, 0.012), (-w * 0.36 + i * 0.026, fy - 0.003, h * 0.2), M["silver_panel"], 0.002,
              col=col, parent=root)
    # 노브
    for i in range(3):
        T.cyl(f"{name}_knob_{i}", 0.013, 0.016, (w * 0.06 + i * 0.05, fy - 0.006, h * 0.25), M["chrome"],
              rot=(math.pi / 2, 0, 0), col=col, parent=root, verts=24)
    T.box(f"{name}_power_led", (0.004, 0.002, 0.004), (w * 0.38, fy, h * 0.3), M["led_red"], 0, col=col, parent=root)
    return root


def build_recorder(M, col, parent, loc, rot):
    """소은의 녹음기와 같은 계열의 휴대용 카세트 녹음기 — 작업실용 (REF 10). 정밀 프롭은 prop_ 단계에서."""
    root = T.empty("stu_portable_recorder", loc, col, parent=parent, rot=rot)
    root["tuv_interact"] = "recorder"
    body = T.box("stu_recorder_body", (0.115, 0.072, 0.032), (0, 0, 0.016), M["plastic_grey"], 0.006, 3, col=col, parent=root)
    T.box("stu_recorder_lcd", (0.04, 0.02, 0.001), (0.02, 0.015, 0.0325), M["screen_off"], 0.001, col=col, parent=root)
    T.box("stu_recorder_window", (0.05, 0.03, 0.001), (-0.025, -0.01, 0.0325), M["glass_clean"], 0.001, col=col, parent=root)
    for i in range(5):
        b = T.box(f"stu_recorder_btn_{i}", (0.012, 0.007, 0.004), (-0.036 + i * 0.016, 0.03, 0.033), M["plastic_dark"], 0.0015,
                  col=col, parent=root)
        b["tuv_anim"] = "button_press_-z"
    T.box("stu_recorder_rec_led", (0.003, 0.003, 0.001), (0.05, 0.03, 0.033), M["led_red"], 0, col=col, parent=root)
    T.box("stu_recorder_grille", (0.03, 0.025, 0.0006), (0.035, -0.015, 0.0322), M["black_metal"], 0, col=col, parent=root)
    return root


def build_desk_items(M, C, lights):
    col = C["props"]
    top = 0.74
    # 울트라와이드 모니터
    mon = T.empty("stu_monitor", (3.0, 4.62, top), col)
    T.box("stu_monitor_base", (0.28, 0.2, 0.012), (0, 0.0, 0.006), M["black_metal"], 0.004, col=col, parent=mon)
    T.box("stu_monitor_neck", (0.05, 0.03, 0.36), (0, 0.03, 0.19), M["black_metal"], 0.006, col=col, parent=mon)
    T.box("stu_monitor_panel", (0.82, 0.03, 0.37), (0, -0.005, 0.32), M["plastic_dark"], 0.006, col=col, parent=mon)
    T.keep(T.box("stu_monitor_screen", (0.8, 0.002, 0.345), (0, -0.0215, 0.325), M["screen"], 0, col=col, parent=mon), "screen")
    # 키보드 (키캡 개별)
    kb = T.empty("stu_keyboard", (2.95, 4.2, top), col, rot=(0, 0, math.radians(2)))
    T.box("stu_keyboard_case", (0.44, 0.14, 0.022), (0, 0, 0.011), M["plastic_dark"], 0.004, col=col, parent=kb)
    key = T.box("stu_key_src", (0.0165, 0.0165, 0.008), (0, 0, -5), M["plastic_grey"], 0.0018, col=col, parent=kb)
    for r in range(5):
        for c in range(22):
            if r == 4 and 4 < c < 12:
                if c == 5:
                    T.linked_copy(key, f"stu_key_space", (-0.2 + 0.019 * 8.5, -0.045 + 0.0, 0.025), col=col, parent=kb).scale = (7, 1, 1)
                continue
            T.linked_copy(key, f"stu_key_{r}_{c}", (-0.2 + c * 0.019, 0.05 - r * 0.023, 0.025), col=col, parent=kb)
    key.hide_render = True
    T.box("stu_mouse", (0.06, 0.11, 0.035), (3.33, 4.19, top + 0.017), M["plastic_dark"], 0.014, 4, col=col)
    T.box("stu_mousepad", (0.3, 0.25, 0.003), (3.35, 4.2, top + 0.0015), M["rubber"], 0.002, col=col)
    # 카세트 데크·녹음기·손전등은 독립 프롭(prop_*.glb) — 여기서는 배치 마커만 둔다
    T.empty("stu_spawn_prop_tape_deck", (2.2, 4.6, top), col)
    # 오디오 인터페이스
    ai = T.box("stu_audio_interface", (0.18, 0.11, 0.045), (2.62, 4.5, top + 0.0225), M["alu_dark"], 0.005, col=col)
    for i in range(4):
        T.cyl(f"stu_ai_knob_{i}", 0.008, 0.012, (2.56 + i * 0.035, 4.442, top + 0.025), M["chrome"], rot=(math.pi / 2, 0, 0),
              col=col, verts=16)
    T.box("stu_ai_led", (0.06, 0.001, 0.004), (2.62, 4.444, top + 0.038), M["led_green"], 0, col=col)
    T.empty("stu_spawn_prop_recorder", (2.45, 4.23, top), col, rot=(0, 0, math.radians(-14)))
    # 헤드폰
    hp = T.empty("stu_headphones", (3.62, 4.32, top + 0.045), col, rot=(math.radians(85), 0, math.radians(30)))
    for sx in (-1, 1):
        T.cyl(f"stu_hp_cup_{sx}", 0.045, 0.035, (sx * 0.085, 0, 0), M["plastic_dark"], rot=(0, math.pi / 2, 0), col=col, parent=hp, verts=24)
        T.cyl(f"stu_hp_pad_{sx}", 0.047, 0.02, (sx * 0.06, 0, 0), M["rubber"], rot=(0, math.pi / 2, 0), col=col, parent=hp, verts=24)
    T.torus("stu_hp_band", 0.09, 0.008, (0, 0, 0.02), M["black_metal"], rot=(math.pi / 2, 0, 0), col=col, parent=hp, arc=0.5)
    # 스탠드 조명 (좌측 끝) — 따뜻한 스팟
    lp = T.empty("stu_desk_lamp", (1.98, 4.68, top), col)
    T.cyl("stu_lamp_base", 0.075, 0.025, (0, 0, 0.0125), M["black_metal"], col=col, parent=lp)
    a1 = T.box("stu_lamp_arm_1", (0.018, 0.018, 0.42), (0, 0, 0.21), M["black_metal"], 0.004, col=col, parent=lp,
               rot=(math.radians(20), 0, 0), pivot=(0, 0, -0.5))
    a1.location = (0, 0, 0.02)
    T.box("stu_lamp_arm_2", (0.016, 0.016, 0.36), (0, -0.14, 0.41), M["black_metal"], 0.004, col=col, parent=lp,
          rot=(math.radians(-62), 0, 0), pivot=(0, 0, -0.5))
    T.cyl("stu_lamp_shade", 0.075, 0.13, (0, -0.46, 0.52), M["black_metal"], rot=(math.radians(-50), 0, 0), col=col, parent=lp,
          r2=0.03, cap=False, verts=32)
    T.keep(T.cyl("stu_lamp_bulb", 0.022, 0.03, (0, -0.44, 0.5), M["bulb_warm"], rot=(math.radians(-50), 0, 0), col=col, parent=lp),
           "light_emitter")
    ld = bpy.data.lights.new("stu_light_desk_lamp", "SPOT")
    ld.energy = 55
    ld.color = (1.0, 0.74, 0.46)
    ld.spot_size = math.radians(95)
    ld.spot_blend = 0.6
    ld.shadow_soft_size = 0.02
    lo = bpy.data.objects.new("stu_light_desk_lamp", ld)
    lo.location = (1.98, 4.68 - 0.47, top + 0.49)
    lo.rotation_euler = (math.radians(38), 0, math.radians(-14))
    lo["tuv_light_state"] = "NORMAL"
    T._link(lo, C["lights"])
    lights.append(lo)
    # 종이·서류·머그·펜
    for i in range(7):
        T.box(f"stu_paper_{i}", (0.21, 0.297, 0.0006), (2.45 + R.uniform(-0.1, 0.35), 4.33 + R.uniform(-0.05, 0.05),
                                                       top + 0.001 + i * 0.0007),
              M["paper"], 0, col=col, rot=(0, 0, math.radians(R.uniform(-25, 25))))
    T.box("stu_doc_stack", (0.22, 0.3, 0.035), (1.72 + 0.32, 4.28, top + 0.0175), M["paper"], 0.002, col=col,
          rot=(0, 0, math.radians(6)))
    mug = T.cyl("stu_mug", 0.042, 0.095, (3.82, 4.55, top + 0.0475), M["ceramic"], col=col, verts=32)
    T.torus("stu_mug_handle", 0.028, 0.007, (3.866, 4.55, top + 0.05), M["ceramic"], rot=(math.pi / 2, 0, 0), col=col)
    T.cyl("stu_mug_coffee", 0.038, 0.002, (3.82, 4.55, top + 0.08), T.mat_basic("stu_coffee", (0.05, 0.025, 0.01), 0.05), col=col)
    T.cyl("stu_pen", 0.004, 0.14, (2.7, 4.2, top + 0.004), M["plastic_dark"], rot=(0, math.pi / 2, math.radians(30)), col=col, verts=8)
    # 책상 위 낱개 카세트 + 인덱스 카드
    for i in range(3):
        T.box(f"stu_desk_cassette_{i}", (0.108, 0.069, 0.0165), (2.62 + i * 0.03, 4.28 + i * 0.01, top + 0.0083 + i * 0.0166),
              [M["cassette_shell"]], 0.0012, col=col, rot=(0, 0, math.radians(R.uniform(-20, 20))))
    T.box("stu_index_card", (0.1, 0.065, 0.0005), (2.8, 4.36, top + 0.001), M["inserts"][3], 0, col=col, rot=(0, 0, math.radians(-12)))
    # 케이블 (모니터 → 책상 아래)
    for i, (x, c) in enumerate([(2.95, M["rubber"]), (3.05, M["rubber"]), (2.2, M["rubber"])]):
        cu = bpy.data.curves.new(f"stu_cable_{i}", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.003
        cu.bevel_resolution = 2
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(2)
        pts = [(x, 4.68, top + 0.15), (x + 0.05, 4.76, top + 0.01), (x + 0.1, 4.78, 0.02)]
        for bp, p in zip(sp.bezier_points, pts):
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new(f"stu_cable_{i}", cu)
        ob.data.materials.append(c)
        T._link(ob, col)
    # 멀티탭
    T.box("stu_power_strip", (0.35, 0.06, 0.04), (3.3, 4.75, 0.02), M["ceramic"], 0.006, col=col)


def build_speakers_rack(M, C):
    col = C["furn"]
    # 장비 랙 (책상 동쪽)
    rk = T.empty("stu_rack", (4.83, 4.45, 0), col)
    T.box("stu_rack_top", (0.56, 0.6, 0.02), (0, 0, 1.15), M["black_metal"], 0.003, col=col, parent=rk)
    T.box("stu_rack_bottom", (0.56, 0.6, 0.03), (0, 0, 0.06), M["black_metal"], 0.003, col=col, parent=rk)
    for sx in (-1, 1):
        T.box(f"stu_rack_side_{sx}", (0.02, 0.6, 1.1), (sx * 0.27, 0, 0.6), M["black_metal"], 0.003, col=col, parent=rk)
        for sy in (-1, 1):
            T.cyl(f"stu_rack_caster_{sx}{sy}", 0.025, 0.02, (sx * 0.23, sy * 0.25, 0.025), M["rubber"], rot=(math.pi / 2, 0, 0),
                  col=col, parent=rk, verts=12)
    units = [(0.98, 2, "deck"), (0.86, 1, "eq"), (0.78, 1, "eq"), (0.68, 2, "amp"), (0.5, 1, "power")]
    U = 0.0445
    for i, (z, n, kind) in enumerate(units):
        h = n * U - 0.002
        T.box(f"stu_rack_unit_{i}", (0.483, 0.35, h), (0, 0.0, z), M["alu_dark"] if kind != "deck" else M["silver_panel"],
              0.002, col=col, parent=rk)
        fy = -0.176
        if kind == "deck":
            for j in range(2):
                T.box(f"stu_rack_deck_door_{j}", (0.13, 0.004, 0.06), (-0.12 + j * 0.16, fy, z + 0.008), M["plastic_dark"], 0.003,
                      col=col, parent=rk)
            T.box("stu_rack_deck_vu", (0.08, 0.003, 0.025), (0.18, fy, z + 0.01), M["vu"], 0.002, col=col, parent=rk)
        elif kind == "eq":
            for j in range(10):
                T.box(f"stu_rack_eq_{i}_{j}", (0.006, 0.01, 0.022), (-0.17 + j * 0.035, fy - 0.004, z + R.uniform(-0.008, 0.008)),
                      M["chrome"], 0.001, col=col, parent=rk)
        elif kind == "amp":
            for j in range(2):
                T.cyl(f"stu_rack_amp_knob_{j}", 0.022, 0.02, (-0.1 + j * 0.2, fy - 0.01, z), M["chrome"],
                      rot=(math.pi / 2, 0, 0), col=col, parent=rk, verts=24)
        else:
            for j in range(8):
                T.box(f"stu_rack_pwr_led_{j}", (0.004, 0.002, 0.004), (-0.15 + j * 0.04, fy, z), M["led_green"], 0, col=col, parent=rk)
        for sx in (-1, 1):
            T.box(f"stu_rack_ear_{i}_{sx}", (0.02, 0.004, h), (sx * 0.252, fy + 0.002, z), M["alu_dark"], 0.001, col=col, parent=rk)
    # 스피커 2개: 좌측 스탠드 / 우측 랙 위
    for side, loc, rotz in (("l", (1.55, 4.62, 0.95), math.radians(-12)), ("r", (4.83, 4.5, 1.16), math.radians(14))):
        sp = T.empty(f"stu_speaker_{side}", loc, col, rot=(0, 0, rotz))
        T.box(f"stu_speaker_{side}_cab", (0.2, 0.25, 0.32), (0, 0, 0.16), M["walnut"], 0.006, col=col, parent=sp)
        T.box(f"stu_speaker_{side}_baffle", (0.19, 0.004, 0.31), (0, -0.126, 0.16), M["plastic_dark"], 0.003, col=col, parent=sp)
        T.cyl(f"stu_speaker_{side}_woofer", 0.07, 0.02, (0, -0.13, 0.12), M["cone"], rot=(math.pi / 2, 0, 0), col=col, parent=sp, r2=0.05)
        T.cyl(f"stu_speaker_{side}_tweeter", 0.022, 0.012, (0, -0.13, 0.25), M["chrome"], rot=(math.pi / 2, 0, 0), col=col, parent=sp)
        T.cyl(f"stu_speaker_{side}_port", 0.016, 0.01, (0, -0.13, 0.035), M["rubber"], rot=(math.pi / 2, 0, 0), col=col, parent=sp)
    st = T.empty("stu_speaker_stand_l", (1.55, 4.62, 0), col)
    T.box("stu_speaker_stand_plate", (0.28, 0.28, 0.012), (0, 0, 0.006), M["black_metal"], 0.003, col=col, parent=st)
    T.box("stu_speaker_stand_post", (0.05, 0.05, 0.93), (0, 0, 0.475), M["black_metal"], 0.004, col=col, parent=st)
    T.box("stu_speaker_stand_top", (0.2, 0.2, 0.01), (0, 0, 0.945), M["black_metal"], 0.003, col=col, parent=st)
    T.collider("stu_rack", (0.56, 0.6, 1.5), (4.83, 4.45, 0.75), C["col"], kind="convcolonly")
    T.collider("stu_speaker_stand", (0.3, 0.3, 1.3), (1.55, 4.62, 0.65), C["col"], kind="convcolonly")


def build_walls_misc(M, C, lights):
    col = C["props"]
    # 흡음재 (웨지 폼 패널 600×600) — 북벽 창 양옆 / 동벽 소파 위
    def wedge_u(u, v):
        a = (u * 6) % 1.0
        return 0.022 * (1 - abs(a * 2 - 1))

    def wedge_v(u, v):
        return wedge_u(v, u)
    srcs = []
    for k, fn in enumerate((wedge_u, wedge_v)):
        s_ = T.heightfield(f"stu_foam_tile_src_{k}", 0.6, 0.6, 72 if k == 0 else 6, 6 if k == 0 else 72, fn, (0, 0, -20),
                           mat=M["foam"], col=col)
        T.solidify(s_, 0.025)
        srcs.append(s_)
    tiles = []
    # 북벽: 법선 -Y  → rot (90°,0,0) / 동벽: 법선 -X → rot (90°,0,-90°)
    for x in [0.75, 5.3]:
        for j, z in enumerate([1.3, 1.9]):
            tiles.append(((x, D - 0.03, z), (math.pi / 2, 0, 0), j % 2))
    for k, y in enumerate([1.4, 2.0, 2.6]):
        tiles.append(((W - 0.03, y, 1.55), (math.pi / 2, 0, -math.pi / 2), k % 2))
    for n, (loc, rot, which) in enumerate(tiles):
        T.linked_copy(srcs[which], f"stu_foam_tile_{n:02d}", loc, rot, col)
    src = srcs[0]
    srcs[1].hide_render = srcs[1].hide_viewport = True
    src.hide_render = src.hide_viewport = True
    # 벽시계 (남벽, 책상에서 돌아보면 보임) — 바늘 개별 오브젝트, 원점 = 중심
    ck = T.empty("stu_wall_clock", (2.35, 0.03, 2.02), col, rot=(math.pi / 2, 0, 0))
    T.cyl("stu_clock_rim", 0.16, 0.04, (0, 0, 0), M["plastic_dark"], col=col, parent=ck, verts=48)
    face = T.cyl("stu_clock_face", 0.148, 0.002, (0, 0, 0.0205), M["clock_face"], col=col, parent=ck, verts=48)
    # 문자판 UV: 평면 투영
    for loop in face.data.loops:
        pass
    me = face.data
    uv = me.uv_layers.active
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (co.x / 0.296 + 0.5, co.y / 0.296 + 0.5)
    T.cyl("stu_clock_glass", 0.15, 0.004, (0, 0, 0.028), M["glass_clean"], col=col, parent=ck, verts=48)
    hh, mm, ss = 11, 47, 8
    for nm, ln, wd, ang, zz in (("hour", 0.075, 0.008, (hh % 12 + mm / 60) / 12, 0.022),
                                ("minute", 0.115, 0.005, mm / 60, 0.023),
                                ("second", 0.125, 0.0015, ss / 60, 0.024)):
        hand_root = T.empty(f"stu_clock_hand_{nm}", (0, 0, zz), col, parent=ck, rot=(0, 0, -ang * math.tau))
        hand_root["tuv_anim"] = "clock_hand_z"
        T.keep(hand_root, "clock_hand")
        T.box(f"stu_clock_hand_{nm}_mesh", (wd, ln, 0.0012), (0, ln * 0.4, 0),
              M["led_red"] if nm == "second" else M["black_metal"], 0, col=col, parent=hand_root)
    # 달력 (서벽 문 근처)
    T.box("stu_calendar", (0.003, 0.3, 0.42), (0.003, 1.2, 1.55), M["calendar"], 0, col=col)
    # 벽걸이 냉난방기 (서벽 상부, 선반 위)
    ac = T.empty("stu_aircon", (0.12, 2.65, 2.27), col)
    T.box("stu_aircon_body", (0.22, 0.95, 0.3), (0, 0, 0), M["ceramic"], 0.03, 4, col=col, parent=ac)
    T.box("stu_aircon_vane", (0.06, 0.88, 0.012), (0.1, 0, -0.13), M["ceramic"], 0.004, col=col, parent=ac,
          rot=(0, math.radians(30), 0))
    T.box("stu_aircon_display", (0.002, 0.05, 0.015), (0.111, 0.3, 0.05), M["led_green"], 0, col=col, parent=ac)
    # 플로어 스탠드 (소파 남쪽 끝)
    fl = T.empty("stu_floor_lamp", (5.62, 0.62, 0), col)
    T.cyl("stu_floorlamp_base", 0.14, 0.02, (0, 0, 0.01), M["black_metal"], col=col, parent=fl)
    T.cyl("stu_floorlamp_pole", 0.012, 1.45, (0, 0, 0.74), M["black_metal"], col=col, parent=fl, verts=12)
    shade = T.cyl("stu_floorlamp_shade", 0.2, 0.28, (0, 0, 1.5), M["lampshade"], col=col, parent=fl, r2=0.15, cap=False, verts=40)
    T.solidify(shade, 0.003)
    ld = bpy.data.lights.new("stu_light_floor_lamp", "POINT")
    ld.energy = 60
    ld.color = (1.0, 0.68, 0.38)
    ld.shadow_soft_size = 0.06
    lo = bpy.data.objects.new("stu_light_floor_lamp", ld)
    lo.location = (5.62, 0.62, 1.48)
    lo["tuv_light_state"] = "NORMAL"
    T._link(lo, C["lights"])
    lights.append(lo)
    T.collider("stu_floor_lamp", (0.3, 0.3, 1.7), (5.62, 0.62, 0.85), C["col"], kind="convcolonly")
    # 쓰레기통 (책상 옆)
    bin_ = T.cyl("stu_trash_bin", 0.13, 0.32, (1.75, 4.25, 0.16), M["plastic_grey"], col=col, cap=True, r2=0.15)
    T.solidify(bin_, 0.003)
    for i in range(3):
        T.box(f"stu_crumpled_{i}", (0.06, 0.05, 0.05), (1.72 + R.uniform(-0.05, 0.05), 4.26 + R.uniform(-0.05, 0.05), 0.3 + i * 0.01),
              M["paper"], 0.02, 3, col=col, rot=(R.random(), R.random(), R.random()))
    # 바닥 서류 더미 (선반 앞)
    for i in range(4):
        T.box(f"stu_floor_docs_{i}", (0.24, 0.32, 0.018), (0.55, 4.25, 0.009 + i * 0.018), M["paper"] if i % 2 else M["cardboard"],
              0.002, col=col, rot=(0, 0, math.radians(R.uniform(-8, 8))))
    # 테이블 위 물건
    T.box("stu_table_laptop", (0.33, 0.23, 0.018), (4.42, 2.15, 0.434), M["alu"], 0.006, col=col, rot=(0, 0, math.radians(80)))
    T.cyl("stu_table_cup", 0.04, 0.1, (4.5, 1.65, 0.475), T.mat_basic("stu_paper_cup", (0.85, 0.82, 0.75), 0.6), col=col, r2=0.03)
    for i in range(3):
        T.box(f"stu_table_paper_{i}", (0.21, 0.297, 0.0006), (4.4 + R.uniform(-0.05, 0.05), 1.9, 0.426 + i * 0.0007), M["paper"], 0,
              col=col, rot=(0, 0, math.radians(R.uniform(60, 110))))


def build_exterior(M, C, lights):
    """창밖: 비 내리는 도시. 맞은편 상가 + 원경 빌딩. 차가운 청회색 계열."""
    col = C["ext"]
    T.box("ext_street", (200, 120, 0.1), (3, 70, -9.0), M["ext_concrete"], 0, col=col)
    # 맞은편 건물 (가까움)
    for i, (x, w, h) in enumerate([(-6, 14, 22), (9.5, 12, 30), (24, 13, 18)]):
        T.box(f"ext_bldg_near_{i}", (w, 10, h), (x, 24 + i * 1.5, -9 + h / 2), M["city_bldg"][i % 4], 0, col=col)
    for i in range(28):
        x = R.uniform(-90, 100)
        y = R.uniform(45, 170)
        w = R.uniform(10, 26)
        h = R.uniform(15, 75)
        T.box(f"ext_bldg_far_{i}", (w, R.uniform(10, 22), h), (x, y, -9 + h / 2), M["city_bldg"][i % 4], 0, col=col)
    # 창밖에서 들어오는 차가운 환경광
    ld = bpy.data.lights.new("stu_light_window_fill", "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = 3.4, 1.4
    ld.energy = 30
    ld.color = (0.58, 0.68, 0.86)
    lo = bpy.data.objects.new("stu_light_window_fill", ld)
    lo.location = ((WIN_X0 + WIN_X1) / 2, D + 0.6, 1.6)
    lo.rotation_euler = (math.radians(-95), 0, 0)
    lo.visible_camera = False          # 창밖 풍경이 보이도록 광원 자체는 카메라에 안 보임
    lo.visible_transmission = False
    lo["tuv_light_state"] = "NORMAL"
    T._link(lo, C["lights"])
    lights.append(lo)
    # 월드
    w = bpy.data.worlds.new("stu_world_night_rain")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.012, 0.016, 0.024, 1)
    bg.inputs["Strength"].default_value = 1.0
    bpy.context.scene.world = w


# ======================================================================= details (2차)
def outlet(M, col, name, loc, rot):
    """한국형 벽 콘센트 2구 (접지형 원형 소켓) — 120x70 mm 플레이트."""
    r = T.empty(name, loc, col, rot=rot)
    T.box(f"{name}_plate", (0.07, 0.008, 0.12), (0, 0, 0), M["plastic_white"], 0.003, 3, col=col, parent=r)
    for k, z in enumerate((0.028, -0.028)):
        T.cyl(f"{name}_socket_{k}", 0.019, 0.004, (0, -0.005, z), M["plastic_white"], rot=(math.pi / 2, 0, 0), col=col, parent=r, verts=24)
        for hx in (-0.0095, 0.0095):
            T.cyl(f"{name}_hole_{k}_{hx > 0}", 0.0024, 0.0045, (hx, -0.0062, z), M["plastic_dark"], rot=(math.pi / 2, 0, 0),
                  col=col, parent=r, verts=10)
    return r


def build_details(M, C):
    col = C["props"]
    # 벽 콘센트
    outlet(M, col, "stu_outlet_n", (3.35, D - 0.004, 0.3), (0, 0, 0))
    outlet(M, col, "stu_outlet_e", (W - 0.004, 3.25, 0.3), (0, 0, math.pi / 2))
    outlet(M, col, "stu_outlet_w", (0.004, 1.55, 0.3), (0, 0, -math.pi / 2))
    outlet(M, col, "stu_outlet_s", (3.4, 0.004, 0.3), (0, 0, math.pi))
    # 전등 스위치 (문 옆, 2구 로커) — 상호작용: 천장 LED 패널 2개
    sw = T.empty("stu_light_switch", (1.62, 0.004, 1.25), C["arch"], rot=(0, 0, math.pi))
    T.keep(sw, "light_switch")
    T.box("stu_light_switch_plate", (0.07, 0.008, 0.12), (0, 0, 0), M["plastic_white"], 0.003, 3, col=C["arch"], parent=sw)
    for k, x in enumerate((-0.016, 0.016)):
        rk = T.empty(f"stu_light_switch_rocker_{k}", (x, -0.006, 0), C["arch"], parent=sw)
        rk["tuv_anim"] = "rocker_x_8"
        T.box(f"stu_light_switch_rocker_{k}_cap", (0.026, 0.006, 0.08), (0, 0, 0), M["plastic_white"], 0.003, 3, col=C["arch"], parent=rk)
    T.box("stu_light_switch_led", (0.004, 0.002, 0.004), (0, -0.0045, 0.05), M["led_green"], 0, col=C["arch"], parent=sw)
    # 멀티탭 + 플러그 + 전선
    ms = T.empty("stu_power_strip", (3.3, 4.74, 0.0), col, rot=(0, 0, math.radians(4)))
    T.box("stu_power_strip_body", (0.36, 0.062, 0.038), (0, 0, 0.019), M["plastic_white"], 0.008, 3, col=col, parent=ms)
    for k in range(4):
        x = -0.11 + k * 0.06
        T.cyl(f"stu_power_strip_socket_{k}", 0.017, 0.003, (x, 0, 0.038), M["plastic_white"], col=col, parent=ms, verts=24)
        if k < 3:
            T.cyl(f"stu_power_plug_{k}", 0.019, 0.035, (x, 0, 0.056), M["plastic_dark"], col=col, parent=ms, verts=24, r2=0.016)
    T.box("stu_power_strip_switch", (0.022, 0.03, 0.006), (0.155, 0, 0.04), T.mat_emission("stu_strip_switch", (1, 0.2, 0.1), 1.5,
          (0.6, 0.1, 0.05)), 0.003, col=col, parent=ms)
    rub = M["rubber"]
    T.curve_tube("stu_cable_strip_outlet", [(3.48, 4.74, 0.02), (3.45, 4.88, 0.006), (3.36, 4.97, 0.006), (3.35, 4.99, 0.27)], 0.004, rub, col)
    T.curve_tube("stu_cable_monitor", [(3.02, 4.66, 0.86), (3.06, 4.79, 0.6), (3.1, 4.8, 0.1), (3.19, 4.74, 0.05)], 0.003, rub, col)
    T.curve_tube("stu_cable_deck", [(2.25, 4.76, 0.8), (2.3, 4.8, 0.4), (2.6, 4.82, 0.006), (3.12, 4.78, 0.006), (3.25, 4.74, 0.05)], 0.0028, rub, col)
    T.curve_tube("stu_cable_lamp", [(1.98, 4.7, 0.76), (1.95, 4.8, 0.5), (2.1, 4.85, 0.006), (3.0, 4.86, 0.006), (3.31, 4.74, 0.05)], 0.0028, rub, col)
    T.curve_tube("stu_cable_rack", [(4.6, 4.6, 0.6), (4.45, 4.75, 0.2), (4.0, 4.85, 0.006), (3.45, 4.78, 0.006), (3.37, 4.74, 0.05)], 0.0035, rub, col)
    T.curve_tube("stu_cable_floorlamp", [(5.62, 0.62, 0.02), (5.8, 0.9, 0.006), (5.95, 2.6, 0.006), (5.99, 3.25, 0.25)], 0.003, rub, col)
    # 책상 위 개인 소지품
    top = 0.74
    gl = T.empty("stu_glasses", (3.52, 4.18, top + 0.012), col, rot=(0, 0, math.radians(-25)))
    for sx in (-1, 1):
        T.torus(f"stu_glasses_rim_{sx}", 0.022, 0.0016, (sx * 0.031, 0, 0), M["black_metal"], rot=(math.radians(80), 0, 0), col=col, parent=gl)
        T.cyl(f"stu_glasses_lens_{sx}", 0.021, 0.0015, (sx * 0.031, 0, 0), M["glass_clean"], rot=(math.radians(80), 0, 0), col=col, parent=gl)
        T.box(f"stu_glasses_temple_{sx}", (0.0018, 0.13, 0.002), (sx * 0.054, 0.065, -0.008), M["black_metal"], 0.0006, col=col, parent=gl,
              rot=(math.radians(-8), 0, math.radians(sx * 6)))
    T.box("stu_glasses_bridge", (0.018, 0.002, 0.002), (0, 0, 0.012), M["black_metal"], 0.0006, col=col, parent=gl)
    ph = T.box("stu_phone", (0.072, 0.152, 0.008), (3.75, 4.25, top + 0.004), M["plastic_dark"], 0.006, 4, col=col,
               rot=(0, 0, math.radians(12)))
    T.box("stu_phone_camera", (0.03, 0.03, 0.002), (3.75 - 0.012, 4.25 + 0.05, top + 0.009), M["alu_dark"], 0.004, 3, col=col,
          rot=(0, 0, math.radians(12)))
    T.box("stu_wallet", (0.11, 0.09, 0.016), (1.75 + 0.35, 4.48, top + 0.008),
          T.mat_pbr("stu_leather_brown", "rubber_black", tint=(9.0, 5.0, 3.0)), 0.006, 4, col=col, rot=(0, 0, math.radians(-30)))
    kr = T.empty("stu_keys", (3.92, 4.33, top + 0.003), col)
    T.torus("stu_keyring", 0.013, 0.0012, (0, 0, 0), M["chrome"], col=col, parent=kr)
    for k, a in enumerate((0.3, 1.2)):
        T.box(f"stu_key_{k}", (0.055, 0.02, 0.002), (math.cos(a) * 0.04, math.sin(a) * 0.04, 0), M["chrome"], 0.002, col=col, parent=kr,
              rot=(0, 0, a))
    # 펼쳐진 수첩
    nb = T.empty("stu_notebook", (2.75, 4.38, top), col, rot=(0, 0, math.radians(-8)))
    for sx in (-1, 1):
        T.box(f"stu_notebook_page_{sx}", (0.105, 0.15, 0.006), (sx * 0.053, 0, 0.003), M["paper"], 0.002, 3, col=col, parent=nb,
              rot=(0, math.radians(-sx * 3), 0))
    T.box("stu_notebook_cover", (0.22, 0.155, 0.002), (0, 0, 0.0005), M["walnut"], 0.001, col=col, parent=nb)
    for k in range(6):
        T.box(f"stu_notebook_ink_{k}", (R.uniform(0.04, 0.08), 0.0012, 0.0002), (0.05 + R.uniform(-0.01, 0.01), 0.05 - k * 0.016, 0.0062),
              M["plastic_dark"], 0, col=col, parent=nb)
    # 펜꽂이 + 펜
    T.lathe("stu_pen_cup", [(0.0, 0.0), (0.032, 0.0), (0.033, 0.1), (0.031, 0.1), (0.03, 0.004), (0.0, 0.004)], 32,
            (1.75 + 0.38, 4.7, top), mat=M["black_metal"], col=col, cap_ends=False)
    for k in range(4):
        T.cyl(f"stu_pen_cup_pen_{k}", 0.0045, 0.14, (2.13 + R.uniform(-0.012, 0.012), 4.7 + R.uniform(-0.012, 0.012), top + 0.075),
              [M["plastic_dark"], M["plastic_white"], M["binder"][0], M["binder"][2]][k], rot=(R.uniform(-0.25, 0.25), R.uniform(-0.25, 0.25), 0),
              col=col, verts=8)
    # 모니터 베젤 포스트잇 2장 + 생수병 + 이어폰 케이스 + USB
    for k, x in enumerate((-0.36, 0.33)):
        T.box(f"stu_sticky_{k}", (0.07, 0.0006, 0.07), (3.0 + x, 4.62 - 0.0225, top + 0.43 - k * 0.02), M["sticky"], 0, col=col,
              rot=(math.radians(R.uniform(-4, 4)), 0, math.radians(R.uniform(-5, 5))))
    T.lathe("stu_water_bottle", [(0.0, 0.0), (0.032, 0.0), (0.034, 0.01), (0.034, 0.15), (0.02, 0.19), (0.013, 0.2), (0.013, 0.215),
                                 (0.0, 0.215)], 32, (4.0, 4.62, top), mat=T.mat_glass("stu_pet_bottle", 0.05, rain=False), col=col)
    T.cyl("stu_water_bottle_cap", 0.0145, 0.012, (4.0, 4.62, top + 0.221), M["binder"][0], col=col, verts=24)
    T.box("stu_earbuds_case", (0.06, 0.045, 0.024), (3.58, 4.55, top + 0.012), M["plastic_white"], 0.011, 4, col=col)
    T.box("stu_usb_stick", (0.04, 0.012, 0.005), (2.66, 4.57, top + 0.003), M["alu"], 0.0015, col=col, rot=(0, 0, 0.6))
    # 문가: 젖은 우산(기대어 둠) + 실내 슬리퍼
    um = T.empty("stu_umbrella", (0.18, 0.55, 0.0), col, rot=(math.radians(-8), math.radians(10), 0))
    T.lathe("stu_umbrella_canopy", [(0.0, 0.08), (0.03, 0.12), (0.045, 0.4), (0.04, 0.75), (0.012, 0.85), (0.0, 0.86)], 16,
            (0, 0, 0), mat=T.mat_pbr("stu_umbrella_fabric", "sofa_fabric", tint=(0.4, 0.45, 0.6), rough_mul=0.5), col=col, parent=um,
            radial_fn=lambda th, z: 1.0 - 0.18 * (abs(math.sin(th * 4)) < 0.3))
    T.cyl("stu_umbrella_tip", 0.004, 0.08, (0, 0, 0.04), M["chrome"], col=col, parent=um, verts=8)
    T.torus("stu_umbrella_handle", 0.035, 0.008, (0.035, 0, 0.92), M["walnut"], rot=(math.pi / 2, 0, 0), col=col, parent=um, arc=0.5)
    T.cyl("stu_umbrella_shaft", 0.005, 0.1, (0, 0, 0.87), M["chrome"], col=col, parent=um, verts=8)
    for k, (x, a) in enumerate(((0.42, 0.2), (0.58, -0.15))):
        sl = T.empty(f"stu_slipper_{k}", (x, 0.35, 0), col, rot=(0, 0, a))
        T.box(f"stu_slipper_{k}_sole", (0.1, 0.27, 0.02), (0, 0, 0.01), M["rubber"], 0.01, 3, col=col, parent=sl)
        T.box(f"stu_slipper_{k}_strap", (0.1, 0.09, 0.03), (0, -0.04, 0.03), T.mat_pbr("stu_slipper_strap", "abs_grey", tint=(0.4, 0.5, 0.8)),
              0.012, 3, col=col, parent=sl)
    # 책상 아래 PC 본체 (팬 소리 음원 위치)
    pc = T.empty("stu_pc_tower", (2.25, 4.5, 0.0), col)
    T.box("stu_pc_case", (0.2, 0.42, 0.44), (0, 0, 0.23), M["black_metal"], 0.006, 3, col=col, parent=pc)
    T.box("stu_pc_front", (0.2, 0.006, 0.44), (0, -0.212, 0.23), M["plastic_dark"], 0.004, col=col, parent=pc)
    for k in range(8):
        T.box(f"stu_pc_vent_{k}", (0.14, 0.003, 0.006), (0, -0.216, 0.12 + k * 0.025), M["alu_dark"], 0, col=col, parent=pc)
    T.box("stu_pc_power_led", (0.006, 0.002, 0.006), (0.06, -0.216, 0.41), M["led_green"], 0, col=col, parent=pc)
    for sx in (-1, 1):
        T.box(f"stu_pc_foot_{sx}", (0.18, 0.04, 0.02), (0, sx * 0.17, 0.01), M["rubber"], 0.004, col=col, parent=pc)
    T.empty("stu_spawn_sound_pc_fan", (2.25, 4.5, 0.3), col)
    T.collider("stu_pc_tower", (0.2, 0.42, 0.44), (2.25, 4.5, 0.23), C["col"], kind="convcolonly")
    # 책상 아래 떨어진 카세트 (어둠 속 단서 테스트용 위치)
    T.empty("stu_spawn_clue_under_desk", (2.7, 4.35, 0.0), col, rot=(0, 0, math.radians(35)))
    # 택배 상자 위치 (복도, 문 바로 앞)
    T.empty("stu_spawn_prop_parcel", (DOOR_X + 0.05, -0.75, 0.0), col, rot=(0, 0, math.radians(8)))


def build_decals(M, C):
    """생활 흔적: 벽 하단 오염, 스위치·문 손때, 천장 누수 얼룩, 바닥 긁힘."""
    col = C["props"]
    up = 0.24
    for i in range(4):
        T.decal_plane(f"stu_decal_dirt_n_{i}", 1.5, 0.3, (0.75 + i * 1.5, D - 0.0015, 0.08 + up / 2), (math.pi / 2, 0, 0), M["d_dirt"], col)
        T.decal_plane(f"stu_decal_dirt_s_{i}", 1.5, 0.3, (1.62 + i * 1.1, 0.0015, 0.08 + up / 2), (math.pi / 2, 0, math.pi), M["d_dirt"], col)
    for i in range(3):
        T.decal_plane(f"stu_decal_dirt_w_{i}", 1.6, 0.3, (0.0015, 0.8 + i * 1.6, 0.08 + up / 2), (math.pi / 2, 0, math.pi / 2), M["d_dirt"], col)
        T.decal_plane(f"stu_decal_dirt_e_{i}", 1.6, 0.3, (W - 0.0015, 0.8 + i * 1.6, 0.08 + up / 2), (math.pi / 2, 0, -math.pi / 2), M["d_dirt"], col)
    T.decal_plane("stu_decal_smudge_switch", 0.28, 0.32, (1.62, 0.0018, 1.25), (math.pi / 2, 0, math.pi), M["d_smudge"], col)
    T.decal_plane("stu_decal_smudge_doorjamb", 0.22, 0.5, (1.47, 0.0018, 1.05), (math.pi / 2, 0, math.pi), M["d_smudge"], col)
    T.decal_plane("stu_decal_smudge_desk_wall", 0.5, 0.35, (2.4, D - 0.0018, 0.95), (math.pi / 2, 0, 0), M["d_smudge"], col)
    T.decal_plane("stu_decal_ceiling_stain", 0.75, 0.75, (5.05, 0.95, H - 0.0018), (math.pi, 0, 0.4), M["d_stain"], col)
    T.decal_plane("stu_decal_ceiling_stain_2", 0.4, 0.4, (0.7, 4.1, H - 0.0018), (math.pi, 0, 1.3), M["d_stain"], col)
    for nm, w_, loc in (("chair", 1.1, (2.95, 3.6, 0.0015)), ("door", 0.9, (DOOR_X, 0.7, 0.0015)), ("shelf", 0.8, (0.7, 3.2, 0.0015)),
                        ("path", 1.2, (2.2, 2.2, 0.0015))):
        T.decal_plane(f"stu_decal_scuff_{nm}", w_, w_, loc, (0, 0, R.uniform(0, 3)), M["d_scuff"], col)
    T.decal_plane("stu_decal_tape_wall", 0.3, 0.3, (4.3, D - 0.0018, 1.6), (math.pi / 2, 0, 0), M["d_tape"], col)


PROP_PLACEMENT = {   # prop.blend 컬렉션 → 마커 (렌더용 인스턴스. GLB에는 포함하지 않고 Godot이 마커 위치에 프롭 씬을 배치)
    "prop_tape_deck": ("stu_spawn_prop_tape_deck", (0, 0, 0)),
    "prop_recorder": ("stu_spawn_prop_recorder", (0, 0, 0)),
    "prop_flashlight": ("stu_spawn_prop_flashlight", (0, 0, 0.0285)),
}


def place_prop_instances(C):
    n = 0
    for name, (marker, off) in PROP_PLACEMENT.items():
        path = PROPS_BLEND / f"{name}.blend"
        mk = bpy.data.objects.get(marker)
        if not path.exists() or mk is None:
            print("[stu] prop missing (run build_props.py first):", name)
            continue
        with bpy.data.libraries.load(str(path), link=False) as (src, dst):
            dst.collections = [c for c in src.collections if c == name]
        pc = dst.collections[0]
        for o in list(pc.all_objects):
            if o.name.endswith("colonly"):
                pc.objects.unlink(o)
        inst = bpy.data.objects.new(f"{name}_instance", None)
        inst.instance_type = "COLLECTION"
        inst.instance_collection = pc
        bpy.context.view_layer.update()
        inst.matrix_world = mk.matrix_world.copy()
        inst.location = inst.location + __import__("mathutils").Vector(off)
        T._link(inst, C["propinst"])
        n += 1
    return n


# ======================================================================= cameras / export
def build_cameras(C):
    col = C["cams"]
    cams = {
        "plan": T.camera("CAM_plan", (W / 2, D / 2, 12), (W / 2, D / 2, 0), ortho=6.8, col=col, clip_start=9.0),
        "top": T.camera("CAM_top", (W / 2 + 0.2, -1.4, 7.2), (W / 2, D / 2 + 0.1, 0.2), lens=20, col=col),
        "entry": T.camera("CAM_entry", (DOOR_X + 0.1, 0.4, 1.62), (3.6, 4.4, 0.95), fov_v=62, col=col),
        "front": T.camera("CAM_front", (3.0, 0.3, 1.62), (3.0, 5.0, 1.15), fov_v=62, col=col),
        "left": T.camera("CAM_left", (4.9, 2.9, 1.62), (0.0, 3.1, 1.05), fov_v=62, col=col),
        "right": T.camera("CAM_right", (1.0, 1.6, 1.62), (6.0, 1.9, 0.9), fov_v=62, col=col),
        "fps": T.camera("CAM_fps", (2.85, 2.95, 1.62), (2.75, 4.6, 0.92), fov_v=70, col=col),
    }
    return cams


def main():
    args = sys.argv[1:]
    do_render = "--render" in args
    views = None
    samples = 48
    res = (1600, 900)
    if "--views" in args:
        views = args[args.index("--views") + 1].split(",")
    if "--samples" in args:
        samples = int(args[args.index("--samples") + 1])
    if "--res" in args:
        res = tuple(int(v) for v in args[args.index("--res") + 1].split("x"))

    T.reset_scene()
    C = {k: T.collection(v) for k, v in {"arch": "stu_architecture", "furn": "stu_furniture", "props": "stu_props",
                                          "lights": "stu_lights", "col": "stu_collision", "ext": "stu_exterior",
                                          "cams": "stu_cameras", "cass": "stu_cassettes", "propinst": "stu_prop_instances"}.items()}
    M = build_materials()
    lights = []
    build_shell(M, C)
    build_window(M, C)
    build_door(M, C)
    build_ceiling_fixtures(M, C, lights)
    build_desk(M, C)
    build_chair(M, C)
    build_sofa(M, C)
    build_coffee_table(M, C)
    n_cass = build_shelves(M, C)
    build_south_cabinet(M, C)
    build_speakers_rack(M, C)
    build_desk_items(M, C, lights)
    build_walls_misc(M, C, lights)
    build_details(M, C)
    build_decals(M, C)
    build_exterior(M, C, lights)
    n_inst = place_prop_instances(C)
    cams = build_cameras(C)
    C["col"].hide_render = True

    BLEND.parent.mkdir(parents=True, exist_ok=True)
    GLB.parent.mkdir(parents=True, exist_ok=True)
    CASSETTE_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    n_obj = len([o for o in bpy.data.objects if o.type == "MESH"])
    print(f"[stu] source meshes={n_obj} cassettes={n_cass} prop_instances={n_inst}")
    print(f"[stu] saved {BLEND}")
    if do_render:
        RENDERS.mkdir(parents=True, exist_ok=True)
        T.setup_render(samples, res, exposure=0.0)
        ceiling_objs = [o for o in bpy.data.objects if o.name.startswith("stu_ceiling")]
        for name, cam in cams.items():
            if views and name not in views:
                continue
            hide = ceiling_objs if name in ("plan", "top") else []
            if name == "plan":
                bpy.context.scene.view_settings.exposure = 2.1
                bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = (1100, 1000)
            else:
                bpy.context.scene.view_settings.exposure = 1.9
                bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = res
            T.render(cam, str(RENDERS / f"stu_{name}.png"), hide)
            print("[stu] rendered", name)
    # --- 게임용 최적화 익스포트 (씬을 변경하므로 저장·렌더 이후에 실행) ---
    nc, ns = export_cassette_instances(C)
    merged, kept, src = T.export_optimized(str(GLB), [C["arch"], C["furn"], C["props"], C["ext"]], C["col"], "stu",
                                           exclude=[C["cass"], C["propinst"]])
    print(f"[stu] cassette instances: cases={nc} spines={ns} -> {CASSETTE_JSON.name}")
    print(f"[stu] GLB: source meshes={src} -> merged static={merged} + kept interactive={kept}")
    print(f"[stu] exported {GLB}")


if __name__ == "__main__":
    main()
