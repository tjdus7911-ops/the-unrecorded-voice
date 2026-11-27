"""TAPE 01 종료 후 책상 위에 나타나는 어린 시절 사진 (요구사항 16) — 1998년 단지 놀이터, 그네 옆에 선 어린 소은.
apt_1998.blend(build_apartment.py) + chr_soeun.gltf(build_characters.py)를 불러와 렌더 → 필름 사진처럼 후처리
(바랜 색·비네팅·흰 테두리·주황색 날짜 각인 '98 6 14). 얼굴은 작게, 정면을 정확히 보여 주지 않는다.
출력: game/assets/textures/apt/apt_tape01_photo.jpg   실행: python3 tools/blender/render_tape01_photo.py
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy  # noqa: E402
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont  # noqa: E402

import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
BLEND = ROOT / "art" / "blender" / "environments" / "apartment_1998" / "apt_1998.blend"
SOEUN = ROOT / "game" / "assets" / "models" / "characters" / "chr_soeun.gltf"
RAW = ROOT / "art" / "renders" / "apartment_1998" / "apt_tape01_photo_raw.png"
OUT = ROOT / "game" / "assets" / "textures" / "apt" / "apt_tape01_photo.jpg"


def main():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    bpy.ops.import_scene.gltf(filepath=str(SOEUN))
    root = [o for o in bpy.context.selected_objects if o.parent is None][0]
    # 그네(빨간 좌석) 옆 모래 위, 카메라 쪽으로 몸을 약간 돌림
    root.location = (9.5, -9.35, -0.43)            # 두 그네 사이, 모래 위
    root.rotation_euler = (0, 0, math.radians(-24))
    # 팔을 몸 옆으로 내린 자세 (MakeHuman A-포즈 → 차렷에 가깝게), 고개 살짝 기울임
    from mathutils import Quaternion, Vector
    arm = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
    if arm:
        for bn, ang in (("upperarm01.L", 34), ("upperarm01.R", -34), ("head", 0)):
            pb = arm.pose.bones.get(bn)
            if pb is None:
                continue
            ml = pb.bone.matrix_local.to_3x3()
            axis = Vector((0, 1, 0)) if bn != "head" else Vector((0, 1, 0))
            a = math.radians(ang if bn != "head" else 7)
            r = Quaternion(axis, a).to_matrix()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (ml.inverted() @ r @ ml).to_quaternion()
        bpy.context.view_layer.update()
    for o in bpy.context.selected_objects:
        o.hide_render = False
    sun = bpy.data.lights.new("photo_sun", "SUN")
    sun.energy = 3.4
    sun.color = (1.0, 0.86, 0.7)
    so = bpy.data.objects.new("photo_sun", sun)
    so.rotation_euler = (math.radians(58), 0, math.radians(-35))
    bpy.context.scene.collection.objects.link(so)
    cam = T.camera("CAM_photo", (10.6, -13.2, 0.9), (8.8, -9.1, 0.35), fov_v=38)
    for c in bpy.data.collections:
        if c.name == "apt_collision":
            c.hide_render = True
    T.setup_render(48, (900, 630), exposure=0.15)
    RAW.parent.mkdir(parents=True, exist_ok=True)
    T.render(cam, str(RAW))
    film(RAW, OUT)
    print("[photo] saved", OUT)


def film(src: Path, dst: Path):
    im = Image.open(src).convert("RGB")
    im = ImageEnhance.Color(im).enhance(0.72)
    im = ImageEnhance.Contrast(im).enhance(0.88)
    # 바랜 노란기·들뜬 검정
    r, g, b = im.split()
    r = r.point(lambda v: min(255, int(v * 1.04 + 14)))
    g = g.point(lambda v: min(255, int(v * 1.0 + 10)))
    b = b.point(lambda v: min(255, int(v * 0.88 + 8)))
    im = Image.merge("RGB", (r, g, b)).filter(ImageFilter.GaussianBlur(0.6))
    w, h = im.size
    vig = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(vig)
    for k in range(40):
        d.ellipse([-w * 0.25 + k * 6, -h * 0.3 + k * 5, w * 1.25 - k * 6, h * 1.3 - k * 5], fill=int(255 * k / 40))
    vig = vig.filter(ImageFilter.GaussianBlur(40))
    dark = Image.new("RGB", (w, h), (40, 30, 22))
    im = Image.composite(im, dark, vig)
    # 필름 날짜 각인 (주황, 우하단)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 30)
    stamp = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ds = ImageDraw.Draw(stamp)
    ds.text((w - 200, h - 62), "'98 6 14", font=font, fill=(255, 138, 40, 230))
    stamp = stamp.filter(ImageFilter.GaussianBlur(0.8))
    im.paste(stamp, (0, 0), stamp)
    # 흰 테두리 (인화지)
    bw = 26
    out = Image.new("RGB", (w + bw * 2, h + bw * 2), (236, 232, 222))
    out.paste(im, (bw, bw))
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, quality=90)


if __name__ == "__main__":
    main()
