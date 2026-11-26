"""주요 오브젝트 (REF 10 / REF 21) — Blender 5.3 빌드 스크립트

prop_flashlight     휴대용 손전등 (스위치 개별, 광원 위치 마커)
prop_parcel         발신인 없는 택배 상자 (덮개 4장 개별 피벗, 테이프, 운송장, 완충재)
prop_tape_1..7      카세트테이프 7개 (릴 2개 개별 — 재생 시 회전)
prop_memo           손으로 쓴 메모
prop_recorder       휴대용 카세트 녹음기 (카세트 도어 피벗, 버튼 6개 개별, 표시등)
prop_tape_deck      테이프 재생 장비 (도어·VU 바늘·버튼 개별)

축 규약: 오브젝트 '앞'은 Blender -Y (= Godot +Z). 손전등 빛은 Blender +Y 방향(= Godot -Z).
실행: python3 tools/blender/build_props.py [--render]
출력: art/blender/props/prop_*.blend, game/assets/models/props/prop_*.glb, art/renders/props/*.png
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402

import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
T.PBR_DIR = ROOT / "game" / "assets" / "textures" / "pbr"
PTEX = ROOT / "game" / "assets" / "textures" / "props"
BLEND_DIR = ROOT / "art" / "blender" / "props"
GLB_DIR = ROOT / "game" / "assets" / "models" / "props"
RENDER_DIR = ROOT / "art" / "renders" / "props"
R = T.RNG
M = {}


def mats():
    M["black"] = T.mat_pbr("prop_powdercoat_black", "powdercoat_black")
    M["alu"] = T.mat_pbr("prop_brushed_aluminium", "brushed_aluminium")
    M["steel"] = T.mat_pbr("prop_brushed_steel", "brushed_steel")
    M["dark_alu"] = T.mat_pbr("prop_anodized_dark", "anodized_dark")
    M["silver"] = T.mat_pbr("prop_silver_faceplate", "silver_faceplate")
    M["abs_dark"] = T.mat_pbr("prop_abs_charcoal", "abs_charcoal")
    M["abs_grey"] = T.mat_pbr("prop_abs_grey", "abs_grey")
    M["rubber"] = T.mat_pbr("prop_rubber", "rubber_black")
    M["walnut"] = T.mat_pbr("prop_walnut", "walnut_veneer")
    M["cardboard"] = T.mat_pbr("prop_cardboard", "cardboard")
    M["paper"] = T.mat_pbr("prop_paper", "paper")
    M["tape_film"] = T.mat_basic("prop_tape_film", (0.11, 0.06, 0.03), 0.35, 0.3, 0.05, 400, 0.02)
    M["smoke_shell"] = T.mat_basic("prop_cassette_shell_smoke", (0.10, 0.10, 0.11), 0.22, 0, 0.03, 60, 0.01)
    M["shell_white"] = T.mat_basic("prop_cassette_shell_white", (0.78, 0.77, 0.74), 0.35, 0, 0.03, 60, 0.01)
    M["window"] = T.mat_glass("prop_clear_plastic", 0.06, rain=False)
    M["lens"] = T.mat_glass("prop_lens_glass", 0.01, rain=False)
    M["reflector"] = T.mat_basic("prop_reflector_chrome", (0.9, 0.9, 0.9), 0.05, 1.0, 0.01, 30, 0)
    M["led_red"] = T.mat_emission("prop_led_red", (1.0, 0.05, 0.02), 4.0)
    M["lcd"] = T.mat_emission("prop_lcd_segment", (0.42, 0.55, 0.42), 0.4, (0.25, 0.3, 0.24))
    M["vu"] = T.mat_emission("prop_vu_backlight", (1.0, 0.62, 0.25), 1.4, (0.9, 0.85, 0.65))
    M["needle"] = T.mat_basic("prop_vu_needle", (0.6, 0.05, 0.03), 0.4)
    M["tape"] = T.mat_basic("prop_packing_tape", (0.62, 0.48, 0.3), 0.25, 0, 0.05, 30, 0.02)
    M["tape"].node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.85
    M["tape"].surface_render_method = "BLENDED"
    M["labels"] = [T.mat_image(f"prop_tape_label_{n}", str(PTEX / f"prop_tape_label_{n}.png"), rough=0.7) for n in range(1, 8)]
    M["memo"] = T.mat_image("prop_memo_paper", str(PTEX / "prop_memo.png"), rough=0.85)
    M["waybill"] = T.mat_image("prop_waybill", str(PTEX / "prop_waybill.png"), rough=0.6)


def new_prop(name):
    T.reset_scene()
    mats()
    col = T.collection(name)
    root = T.empty(name, (0, 0, 0), col)
    return col, root


def save_prop(name, col, render_cam=None, render_target=(0, 0, 0)):
    BLEND_DIR.mkdir(parents=True, exist_ok=True)
    GLB_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_DIR / f"{name}.blend"), compress=True)
    b, a = T.merge_rigid([col])                 # 게임용: 움직이는 부품 단위 병합 (원본 .blend는 위에서 저장됨)
    print(f"[prop] {name}: meshes {b} -> {a} (rigid merge)")
    T.strip_aux_uv()
    T.export_glb(str(GLB_DIR / f"{name}.gltf"), [col])
    tris = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in col.all_objects:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            tris += sum(len(p.vertices) - 2 for p in me.polygons)
            o.evaluated_get(dg).to_mesh_clear()
    print(f"[prop] {name}: objects={len(col.all_objects)} tris={tris}")
    if "--render" in sys.argv and render_cam:
        studio_light_rig(render_target)
        RENDER_DIR.mkdir(parents=True, exist_ok=True)
        T.setup_render(64, (1200, 900), exposure=0.3)
        cam = T.camera(f"CAM_{name}", render_cam, render_target, lens=70, col=col)
        T.render(cam, str(RENDER_DIR / f"{name}.png"))


def studio_light_rig(target):
    """오브젝트 상세 렌더용 — 어두운 책상 위 따뜻한 키 라이트 + 차가운 림."""
    tx, ty, tz = target
    T.box("_table", (1.2, 1.0, 0.03), (tx, ty, -0.016), T.mat_pbr("_walnut_tbl", "walnut_veneer"), 0.002)
    for nm, loc, e, c, s in (("key", (tx - 0.35, ty - 0.4, tz + 0.5), 25, (1.0, 0.78, 0.55), 0.15),
                             ("rim", (tx + 0.4, ty + 0.45, tz + 0.35), 12, (0.6, 0.72, 0.95), 0.3),
                             ("fill", (tx + 0.3, ty - 0.6, tz + 0.2), 3, (0.9, 0.9, 1.0), 0.6)):
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy, ld.color, ld.size = e, c, s
        lo = bpy.data.objects.new(nm, ld)
        lo.location = loc
        d = __import__("mathutils").Vector(target) - lo.location
        lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(lo)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.01, 0.011, 0.014, 1)
    bpy.context.scene.world = w


# ======================================================================= flashlight
def build_flashlight():
    name = "prop_flashlight"
    col, root = new_prop(name)
    T.keep(root, "flashlight")
    L = 0.245

    def ribs(th, y):
        # 손잡이 구간 세로 홈 (REF 21)
        if 0.07 < y < 0.19:
            return 1.0 - 0.045 * (0.5 + 0.5 * math.copysign(1, math.cos(th * 28)))
        return 1.0
    body = [(0.0, 0.0), (0.0158, 0.0), (0.0170, 0.003), (0.0172, 0.022), (0.0168, 0.026), (0.0172, 0.03),
            (0.0172, 0.06), (0.0176, 0.066), (0.0176, 0.195), (0.0185, 0.2), (0.025, 0.215), (0.0272, 0.232),
            (0.0272, L - 0.004), (0.0262, L)]
    T.lathe("prop_flashlight_body", body, 168, mat=M["black"], col=col, parent=root, radial_fn=ribs, axis="Y")
    # 꼬리 배터리 캡 (널링) — 개별
    cap = T.lathe("prop_flashlight_tailcap", [(0.0, -0.022), (0.0168, -0.022), (0.0178, -0.018), (0.0178, -0.002),
                                              (0.0172, 0.0)], 48, mat=M["black"], col=col, parent=root,
                  radial_fn=lambda th, y: 1.0 - 0.03 * (math.sin(th * 40) > 0), axis="Y")
    T.keep(cap, "battery_cap")
    T.torus("prop_flashlight_lanyard_loop", 0.007, 0.0016, (0, -0.026, 0), M["steel"], rot=(0, 0, 0), col=col, parent=root)
    # 헤드: 베젤 링 · 렌즈 · 반사판 · 전구
    T.lathe("prop_flashlight_bezel", [(0.0262, L - 0.002), (0.0285, L - 0.002), (0.0288, L + 0.008), (0.0255, L + 0.01)],
            64, mat=M["alu"], col=col, parent=root, axis="Y")
    T.lathe("prop_flashlight_reflector", [(0.004, L - 0.025), (0.01, L - 0.02), (0.017, L - 0.01), (0.0245, L + 0.002)],
            48, mat=M["reflector"], col=col, parent=root, axis="Y", cap_ends=False)
    T.cyl("prop_flashlight_lens", 0.0252, 0.0025, (0, L + 0.006, 0), M["lens"], rot=(math.pi / 2, 0, 0), col=col, parent=root, verts=48)
    bulb = T.cyl("prop_flashlight_bulb", 0.003, 0.006, (0, L - 0.021, 0), T.mat_emission("prop_bulb", (1, 0.9, 0.75), 0.0),
                 rot=(math.pi / 2, 0, 0), col=col, parent=root, verts=12)
    T.keep(bulb, "bulb_emission")
    # 상단 스위치 하우징 + 스위치 (개별, 누름 애니메이션 피벗 = 바닥 중심)
    T.box("prop_flashlight_switch_housing", (0.016, 0.042, 0.007), (0, 0.205, 0.0215), M["dark_alu"], 0.002, 3, col=col, parent=root)
    sw = T.empty("prop_flashlight_switch", (0, 0.205, 0.025), col, parent=root)
    T.keep(sw, "switch")
    sw["tuv_anim"] = "button_press_-z_0.0015"
    T.box("prop_flashlight_switch_cap", (0.011, 0.022, 0.004), (0, 0, 0.002), M["rubber"], 0.0015, 3, col=col, parent=sw)
    for k in range(4):
        T.box(f"prop_flashlight_switch_grip_{k}", (0.011, 0.0012, 0.0008), (0, -0.007 + k * 0.0045, 0.0042), M["rubber"], 0,
              col=col, parent=sw)
    led = T.cyl("prop_flashlight_indicator", 0.0018, 0.002, (0, 0.188, 0.0245), M["led_red"], col=col, parent=root, verts=12)
    T.keep(led, "indicator")
    T.empty("prop_flashlight_light_origin", (0, L + 0.01, 0), col, parent=root)
    # 사용 흔적: 모서리 마모는 powdercoat 스크래치 텍스처 + 베젤 찍힘
    for k in range(3):
        T.box(f"prop_flashlight_ding_{k}", (0.004, 0.002, 0.001), (math.cos(k * 2.1) * 0.0286, L + 0.004, math.sin(k * 2.1) * 0.0286),
              M["steel"], 0.0005, col=col, parent=root, rot=(0, k * 2.1, 0))
    T.collider("prop_flashlight", (0.06, 0.28, 0.06), (0, 0.12, 0), col, kind="convcolonly")
    root.rotation_euler = (0, 0, 0)
    save_prop(name, col, (0.25, -0.18, 0.22), (0, 0.12, 0.0))


# ======================================================================= cassette tape
def tape_mesh(col, parent, n, wound=0.5):
    """카세트 1개 (100.4 x 63.8 x 12 mm). 앞면 = -Y 쪽이 아니라 +Z가 A면 라벨 (책상에 눕힌 상태)."""
    t = T.empty(f"prop_tape_{n}", (0, 0, 0), col, parent=parent)
    T.keep(t, "tape")
    t["tuv_item"] = f"tape_{n}"
    W, D, H = 0.1004, 0.0638, 0.012
    shell = M["shell_white"] if n % 2 else M["smoke_shell"]
    T.box(f"prop_tape_{n}_shell_bottom", (W, D, H / 2 - 0.0004), (0, 0, H * 0.25), shell, 0.0015, 3, col=col, parent=t)
    # 윗판: 창 개구부(60 x 14 mm)를 둘러싼 4조각 → 창으로 릴과 감긴 테이프가 보인다
    wx0, wx1, wy0, wy1 = -0.03, 0.03, -0.008, 0.006
    zt = H * 0.75
    ht = H / 2 - 0.0004
    T.box(f"prop_tape_{n}_shell_top_n", (W, D / 2 - wy1, ht), (0, (wy1 + D / 2) / 2, zt), shell, 0.0012, 2, col=col, parent=t)
    T.box(f"prop_tape_{n}_shell_top_s", (W, wy0 + D / 2, ht), (0, (wy0 - D / 2) / 2, zt), shell, 0.0012, 2, col=col, parent=t)
    T.box(f"prop_tape_{n}_shell_top_w", (W / 2 + wx0, wy1 - wy0, ht), ((wx0 - W / 2) / 2, (wy0 + wy1) / 2, zt), shell, 0.0008, 2,
          col=col, parent=t)
    T.box(f"prop_tape_{n}_shell_top_e", (W / 2 - wx1, wy1 - wy0, ht), ((wx1 + W / 2) / 2, (wy0 + wy1) / 2, zt), shell, 0.0008, 2,
          col=col, parent=t)
    T.box(f"prop_tape_{n}_head_lip", (0.064, 0.008, H), (0, -D / 2 - 0.0035, H / 2), shell, 0.0015, 2, col=col, parent=t)
    # 라벨: 창 위(번호·띠)와 창 아래 두 조각 — 이미지의 해당 영역만 사용
    lt = T.box(f"prop_tape_{n}_label_top", (0.088, 0.0185, 0.0003), (0, (wy1 + 0.0015 + 0.0265) / 2 + 0.0, H + 0.0002),
               M["labels"][n - 1], 0, col=col, parent=t)
    T.uv_rect(lt, 0.0, 1.0, 0.5, 1.0)
    lb = T.box(f"prop_tape_{n}_label_bottom", (0.088, 0.0125, 0.0003), (0, (wy0 - 0.0015 - 0.022) / 2, H + 0.0002),
               M["labels"][n - 1], 0, col=col, parent=t)
    T.uv_rect(lb, 0.0, 1.0, 0.0, 0.28)
    T.box(f"prop_tape_{n}_window", (wx1 - wx0 + 0.004, wy1 - wy0 + 0.004, 0.0006), (0, (wy0 + wy1) / 2, H - 0.0006), M["window"], 0.0004,
          col=col, parent=t)
    for side, x in (("l", -0.021), ("r", 0.021)):
        r_tape = 0.012 + 0.012 * (wound if side == "l" else 1 - wound)
        reel = T.empty(f"prop_tape_{n}_reel_{side}", (x, -0.001, H / 2), col, parent=t)
        T.keep(reel, "reel")
        reel["tuv_anim"] = "reel_spin_z"
        T.cyl(f"prop_tape_{n}_reel_{side}_hub", 0.0105, 0.0095, (0, 0, 0), M["shell_white"], col=col, parent=reel, verts=24)
        T.cyl(f"prop_tape_{n}_reel_{side}_film", r_tape, 0.0062, (0, 0, 0), M["tape_film"], col=col, parent=reel, verts=48)
        for k in range(6):
            a = k / 6 * math.tau
            T.box(f"prop_tape_{n}_reel_{side}_tooth_{k}", (0.0016, 0.003, 0.0098), (math.cos(a) * 0.0046, math.sin(a) * 0.0046, 0),
                  M["shell_white"], 0.0003, col=col, parent=reel, rot=(0, 0, a))
    # 두 릴 사이 노출된 테이프 경로 + 가이드 롤러
    T.box(f"prop_tape_{n}_film_path", (0.07, 0.0002, 0.0062), (0, -D / 2 + 0.003, H / 2), M["tape_film"], 0, col=col, parent=t)
    for x in (-0.034, 0.034):
        T.cyl(f"prop_tape_{n}_roller_{x > 0}", 0.0022, 0.009, (x, -D / 2 + 0.0045, H / 2), M["shell_white"], col=col, parent=t, verts=12)
    # 나사 5개
    for k, (x, y) in enumerate([(-0.045, 0.027), (0.045, 0.027), (-0.045, -0.027), (0.045, -0.027), (0, -0.026)]):
        T.cyl(f"prop_tape_{n}_screw_{k}", 0.0017, 0.0006, (x, y, H + 0.0001), M["steel"], col=col, parent=t, verts=12)
    return t


def build_tapes():
    name = "prop_tapes"
    col, root = new_prop(name)
    for n in range(1, 8):
        t = tape_mesh(col, root, n, wound=0.35 + 0.05 * n)
        t.location = ((n - 4) * 0.11, 0, 0)
        T.collider(f"prop_tape_{n}", (0.1, 0.064, 0.013), ((n - 4) * 0.11, 0, 0.006), col, kind="convcolonly")
    save_prop(name, col, (0.0, -0.55, 0.42), (0, 0.0, 0.0))


# ======================================================================= memo
def build_memo():
    name = "prop_memo"
    col, root = new_prop(name)
    T.keep(root, "memo")
    root["tuv_item"] = "note_prologue"
    me = T.heightfield("prop_memo_sheet", 0.1, 0.148, 10, 14, lambda u, v: 0.0035 * math.sin(u * math.pi) * 0.3 +
                       (0.002 if abs(v - 0.5) < 0.05 else 0.0) - 0.002 * (v - 0.5) ** 2, (0, 0, 0.001),
                       mat=M["memo"], col=col, parent=root)
    T.uv_rect(me, 0, 1, 0, 1)
    T.solidify(me, 0.0002)
    T.collider("prop_memo", (0.1, 0.15, 0.01), (0, 0, 0.003), col, kind="convcolonly")
    save_prop(name, col, (0.06, -0.22, 0.3), (0, 0, 0))


# ======================================================================= parcel
def build_parcel():
    """발신인 없는 택배 상자 — 덮개 4장 개별(피벗=접힘선), 봉인 테이프, 운송장, 완충재 + 테이프 7개 + 메모."""
    name = "prop_parcel"
    col, root = new_prop(name)
    T.keep(root, "parcel")
    L, Wd, H, t = 0.34, 0.25, 0.18, 0.004
    cb = M["cardboard"]
    T.box("prop_parcel_bottom", (L, Wd, t), (0, 0, t / 2), cb, 0.001, col=col, parent=root)
    for sx in (-1, 1):
        T.box(f"prop_parcel_wall_x{sx}", (t, Wd, H), (sx * (L / 2 - t / 2), 0, H / 2), cb, 0.0012, col=col, parent=root)
        T.box(f"prop_parcel_wall_y{sx}", (L, t, H), (0, sx * (Wd / 2 - t / 2), H / 2), cb, 0.0012, col=col, parent=root)
    # 덮개: 긴 덮개 2장(위), 짧은 덮개 2장(아래). 원점 = 접힘선.
    flaps = []
    for sy in (-1, 1):
        f = T.empty(f"prop_parcel_flap_long_{'a' if sy < 0 else 'b'}", (0, sy * Wd / 2, H), col, parent=root)
        T.keep(f, "flap")
        f["tuv_anim"] = f"flap_hinge_x_{'-' if sy < 0 else '+'}"
        T.box(f"{f.name}_panel", (L - 0.004, Wd / 2, t), (0, -sy * Wd / 4, t * 1.5), cb, 0.001, col=col, parent=f)
        flaps.append(f)
    for sx in (-1, 1):
        f = T.empty(f"prop_parcel_flap_short_{'a' if sx < 0 else 'b'}", (sx * L / 2, 0, H), col, parent=root)
        T.keep(f, "flap")
        f["tuv_anim"] = f"flap_hinge_y_{'-' if sx < 0 else '+'}"
        T.box(f"{f.name}_panel", (L / 2 - 0.02, Wd - 0.01, t), (-sx * (L / 4 - 0.01), 0, t * 0.5), cb, 0.001, col=col, parent=f)
        flaps.append(f)
    # 봉인 테이프 (열면 사라짐) + 옆면으로 내려오는 끝
    seal = T.empty("prop_parcel_seal_tape", (0, 0, H + 2.2 * t), col, parent=root)
    T.keep(seal, "seal")
    T.box("prop_parcel_seal_top", (L + 0.002, 0.048, 0.0003), (0, 0, 0), M["tape"], 0, col=col, parent=seal)
    for sx in (-1, 1):
        T.box(f"prop_parcel_seal_side_{sx}", (0.0003, 0.048, 0.07), (sx * (L / 2 + 0.0015), 0, -0.035 - 2.2 * t), M["tape"], 0,
              col=col, parent=seal)
    # 운송장 (긴 덮개 위) — 보내는 분 공란
    wb = T.box("prop_parcel_waybill", (0.15, 0.095, 0.0003), (0.06, 0.06, H + 2.0 * t + 0.0003), M["waybill"], 0, col=col,
               parent=root, rot=(0, 0, math.radians(-4)))
    T.fit_uvs(wb)
    # 찌그러짐·젖은 얼룩: 모서리 약간 눌림
    T.box("prop_parcel_dent", (0.03, 0.03, 0.01), (L / 2 - 0.01, -Wd / 2 + 0.01, H - 0.004), cb, 0.004, col=col, parent=root,
          rot=(0.3, 0.2, 0.1))
    # 내용물: 완충재(구겨진 종이) + 테이프 7개 + 메모
    for k in range(10):
        T.box(f"prop_parcel_filler_{k}", (0.07, 0.06, 0.04), (R.uniform(-0.12, 0.12), R.uniform(-0.08, 0.08), 0.03),
              M["paper"], 0.018, 3, col=col, parent=root, rot=(R.random() * 3, R.random() * 3, R.random() * 3))
    tray = T.empty("prop_parcel_contents", (0, 0, 0.055), col, parent=root)
    for n in range(1, 8):
        tp = tape_mesh(col, tray, n, wound=0.35 + 0.05 * n)
        row, c = divmod(n - 1, 4)
        tp.location = (-0.115 + c * 0.077 if row == 0 else -0.08 + c * 0.077, -0.04 + row * 0.075, 0.002 + row * 0.004)
        tp.rotation_euler = (0, 0, math.radians(90 + R.uniform(-6, 6)))
    memo = T.empty("prop_memo", (0.02, 0.0, 0.085), col, parent=tray, rot=(0, 0, math.radians(8)))
    T.keep(memo, "memo")
    memo["tuv_item"] = "note_prologue"
    sheet = T.heightfield("prop_memo_sheet", 0.1, 0.148, 8, 10, lambda u, v: 0.0025 * math.sin(u * math.pi), (0, 0, 0),
                          mat=M["memo"], col=col, parent=memo)
    T.uv_rect(sheet, 0, 1, 0, 1)
    T.collider("prop_parcel", (L, Wd, H), (0, 0, H / 2), col, kind="convcolonly")
    save_prop(name, col, (0.42, -0.5, 0.55), (0, 0, 0.1))


# ======================================================================= recorder
def build_recorder():
    """휴대용 카세트 녹음기 (REF 10: 회색 본체, 상단 카세트 도어, 전면 버튼, LCD, 가죽 케이스 스트랩)."""
    name = "prop_recorder"
    col, root = new_prop(name)
    T.keep(root, "recorder")
    W, D, H = 0.118, 0.084, 0.034
    T.box("prop_recorder_body", (W, D, H), (0, 0, H / 2), M["abs_grey"], 0.006, 4, col=col, parent=root)
    T.box("prop_recorder_side_trim", (W + 0.001, D - 0.01, 0.006), (0, 0, H * 0.5), M["dark_alu"], 0.002, col=col, parent=root)
    # 카세트 도어 (상면, 뒤쪽 경첩) — 열림 애니메이션 피벗
    door = T.empty("prop_recorder_door", (0, D / 2 - 0.006, H), col, parent=root)
    T.keep(door, "cassette_door")
    door["tuv_anim"] = "door_hinge_x_open_-55"
    T.box("prop_recorder_door_panel", (0.106, 0.068, 0.003), (0, -0.034, 0.0015), M["abs_dark"], 0.0015, col=col, parent=door)
    T.box("prop_recorder_door_window", (0.06, 0.022, 0.0008), (0.0, -0.034, 0.0032), M["window"], 0.0004, col=col, parent=door)
    slot = T.empty("prop_recorder_tape_slot", (0, -0.004, H - 0.013), col, parent=root)
    slot["tuv_marker"] = "tape_slot"
    # 전면 버튼 6개 (개별 — 누름 피벗)
    for k, (lab, c) in enumerate([("rec", M["led_red"]), ("play", M["abs_dark"]), ("rew", M["abs_dark"]),
                                   ("ff", M["abs_dark"]), ("stop", M["abs_dark"]), ("pause", M["abs_dark"])]):
        b = T.empty(f"prop_recorder_btn_{lab}", (-0.045 + k * 0.018, -D / 2 - 0.001, H * 0.62), col, parent=root)
        T.keep(b, "button")
        b["tuv_anim"] = "button_press_+y_0.003"
        T.box(f"prop_recorder_btn_{lab}_cap", (0.014, 0.006, 0.008), (0, 0, 0), M["abs_dark"] if lab != "rec" else
              T.mat_basic("prop_btn_red", (0.5, 0.05, 0.04), 0.4), 0.0015, 3, col=col, parent=b)
    # LCD 카운터 · 표시등 · 마이크 · 스피커 그릴
    T.box("prop_recorder_lcd", (0.034, 0.002, 0.009), (0.03, -D / 2 - 0.0005, H * 0.25), M["lcd"], 0.0005, col=col, parent=root)
    led = T.cyl("prop_recorder_rec_led", 0.0016, 0.002, (0.052, -D / 2 - 0.001, H * 0.25), M["led_red"],
                rot=(math.pi / 2, 0, 0), col=col, parent=root, verts=12)
    T.keep(led, "indicator")
    for i in range(6):
        for j in range(4):
            T.cyl(f"prop_recorder_grille_{i}_{j}", 0.0011, 0.0008, (-0.05 + i * 0.0045, 0.022 + j * 0.0045 - 0.035, H + 0.0001),
                  M["black"], col=col, parent=root, verts=8)
    T.cyl("prop_recorder_volume", 0.009, 0.004, (W / 2 + 0.001, 0.02, H / 2), M["abs_dark"], rot=(0, math.pi / 2, 0), col=col,
          parent=root, verts=24)
    # 가죽 케이스 스트랩 (REF 10)
    T.curve_tube("prop_recorder_strap", [(-W / 2 - 0.002, 0.03, 0.01), (-W / 2 - 0.02, 0.0, 0.004), (-W / 2 - 0.05, -0.03, 0.002),
                                         (-W / 2 - 0.08, -0.02, 0.002)], 0.0025, M["rubber"], col=col, parent=root)
    T.collider("prop_recorder", (W, D, H + 0.01), (0, 0, H / 2), col, kind="convcolonly")
    save_prop(name, col, (0.22, -0.32, 0.22), (0, 0, 0.015))


# ======================================================================= tape deck
def build_tape_deck():
    """음성 복원 장비 — 우드 사이드 실버 카세트 데크 (REF 10). 도어(하단 경첩) · VU 바늘 · 버튼 개별."""
    name = "prop_tape_deck"
    col, root = new_prop(name)
    T.keep(root, "tape_deck")
    W, D, H = 0.44, 0.3, 0.13
    T.box("prop_deck_chassis", (W - 0.04, D, H), (0, 0, H / 2), M["silver"], 0.002, col=col, parent=root)
    T.box("prop_deck_top", (W - 0.04, D - 0.004, 0.004), (0, 0.002, H + 0.001), M["dark_alu"], 0.001, col=col, parent=root)
    for sx in (-1, 1):
        T.box(f"prop_deck_side_{sx}", (0.02, D + 0.004, H + 0.006), (sx * (W / 2 - 0.01), 0, H / 2), M["walnut"], 0.003, 3,
              col=col, parent=root)
    fy = -D / 2 - 0.001
    # 카세트 도어 — 원점 = 하단 경첩, -X축 회전으로 앞으로 열림
    door = T.empty("prop_deck_door", (-0.1, fy, 0.035), col, parent=root)
    T.keep(door, "cassette_door")
    door["tuv_anim"] = "door_hinge_x_open_+25"
    T.box("prop_deck_door_panel", (0.15, 0.006, 0.08), (0, -0.003, 0.04), M["abs_dark"], 0.002, col=col, parent=door)
    T.box("prop_deck_door_window", (0.1, 0.002, 0.03), (0, -0.0065, 0.048), M["window"], 0.0005, col=col, parent=door)
    slot = T.empty("prop_deck_tape_slot", (-0.1, fy + 0.03, 0.075), col, parent=root)
    slot["tuv_marker"] = "tape_slot"
    # VU 미터 2개 + 바늘
    for i in range(2):
        x = 0.03 + i * 0.065
        T.box(f"prop_deck_vu_{i}_face", (0.055, 0.003, 0.034), (x, fy, 0.088), M["vu"], 0.001, col=col, parent=root)
        T.box(f"prop_deck_vu_{i}_bezel", (0.06, 0.004, 0.039), (x, fy + 0.001, 0.088), M["black"], 0.001, col=col, parent=root)
        nd = T.empty(f"prop_deck_vu_{i}_needle", (x, fy - 0.0025, 0.074), col, parent=root, rot=(0, math.radians(-40), 0))
        T.keep(nd, "vu_needle")
        nd["tuv_anim"] = "needle_y_-40_+40"
        T.box(f"prop_deck_vu_{i}_needle_mesh", (0.0008, 0.0006, 0.026), (0, 0, 0.013), M["needle"], 0, col=col, parent=nd)
    # 트랜스포트 버튼 6개
    for k, lab in enumerate(["eject", "rew", "play", "ff", "stop", "rec"]):
        b = T.empty(f"prop_deck_btn_{lab}", (-0.165 + k * 0.026, fy - 0.002, 0.02), col, parent=root)
        T.keep(b, "button")
        b["tuv_anim"] = "button_press_+y_0.003"
        T.box(f"prop_deck_btn_{lab}_cap", (0.022, 0.01, 0.012), (0, 0, 0), M["silver"], 0.0015, 3, col=col, parent=b)
    for i in range(3):
        T.lathe(f"prop_deck_knob_{i}", [(0.0, 0.0), (0.014, 0.0), (0.0145, 0.004), (0.0135, 0.0155), (0.0125, 0.0165), (0.0, 0.0165)], 48,
                (0.09 + i * 0.045, fy - 0.0165, 0.03), (-math.pi / 2, 0, 0), M["steel"], col=col, parent=root,
                radial_fn=lambda th, z: 1.0 - 0.03 * (math.sin(th * 36) > 0))
    T.box("prop_deck_counter", (0.035, 0.003, 0.012), (0.17, fy, 0.09), M["lcd"], 0.001, col=col, parent=root)
    led = T.cyl("prop_deck_power_led", 0.002, 0.002, (0.185, fy, 0.03), M["led_red"], rot=(math.pi / 2, 0, 0), col=col, parent=root)
    T.keep(led, "indicator")
    for sx in (-1, 1):
        for sy in (-1, 1):
            T.cyl(f"prop_deck_foot_{sx}{sy}", 0.012, 0.008, (sx * 0.17, sy * 0.11, -0.004), M["rubber"], col=col, parent=root)
    T.collider("prop_tape_deck", (W, D, H), (0, 0, H / 2), col, kind="convcolonly")
    save_prop(name, col, (0.35, -0.75, 0.35), (0, 0, 0.06))


def build_keys():
    """열쇠 꾸러미 (REF 10 열쇠) — 링 + 열쇠 3개 + 플라스틱 태그."""
    name = "prop_keys"
    col, root = new_prop(name)
    T.keep(root, "keys")
    root["tuv_item"] = "keys_stairwell"
    T.torus("prop_keys_ring", 0.016, 0.0013, (0, 0, 0.0015), M["steel"], col=col, parent=root)
    for k, (a, ln) in enumerate(((0.2, 0.058), (1.1, 0.052), (2.3, 0.045))):
        kr = T.empty(f"prop_keys_key_{k}", (math.cos(a) * 0.016, math.sin(a) * 0.016, 0.0015 + k * 0.0022), col, parent=root,
                     rot=(0, 0, a))
        T.cyl(f"prop_keys_key_{k}_bow", 0.011, 0.002, (0.011, 0, 0), M["alu"] if k else M["steel"], col=col, parent=kr, verts=20)
        T.box(f"prop_keys_key_{k}_blade", (ln - 0.02, 0.007, 0.0018), (0.022 + (ln - 0.02) / 2, 0, 0), M["alu"] if k else M["steel"],
              0.0005, col=col, parent=kr)
        for t in range(4):
            T.box(f"prop_keys_key_{k}_cut_{t}", (0.003, 0.003, 0.0019), (0.03 + t * 0.007, 0.004, 0), M["alu"] if k else M["steel"],
                  0.0003, col=col, parent=kr, rot=(0, 0, 0.785))
    T.box("prop_keys_tag", (0.045, 0.022, 0.003), (-0.034, -0.012, 0.0015), T.mat_basic("prop_keys_tag", (0.1, 0.25, 0.55), 0.4),
          0.002, col=col, parent=root, rot=(0, 0, 0.5))
    T.collider("prop_keys", (0.12, 0.08, 0.01), (0.01, 0, 0.003), col, kind="convcolonly")
    save_prop(name, col, (0.1, -0.14, 0.14), (0.01, 0, 0))


if __name__ == "__main__":
    build_keys()
    build_flashlight()
    build_tapes()
    build_memo()
    build_parcel()
    build_recorder()
    build_tape_deck()
