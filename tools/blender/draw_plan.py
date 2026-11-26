"""치수 평면도 생성 — .blend 안의 실제 오브젝트(충돌체 풋프린트)를 읽어 그린다.
평면도와 3D 렌더가 같은 공간 데이터를 쓰도록 보장.

usage: python3 tools/blender/draw_plan.py <file.blend> <out.png>
"""
import sys

import bpy
import matplotlib
from mathutils import Vector

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib import font_manager  # noqa: E402
from matplotlib.patches import Arc, Rectangle  # noqa: E402

FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
font_manager.fontManager.addfont(FONT)
plt.rcParams["font.family"] = font_manager.FontProperties(fname=FONT).get_name()

LABELS = {
    "stu_desk": "작업 책상", "stu_chair": "의자", "stu_sofa": "소파", "stu_coffee_table": "작은 테이블",
    "stu_shelf_0": "카세트 선반 A", "stu_shelf_1": "카세트 선반 B", "stu_cabinet": "수납장\n(손전등)",
    "stu_rack": "장비 랙", "stu_speaker_stand": "스피커", "stu_floor_lamp": "스탠드",
}


def footprint(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    xs, ys = [p.x for p in pts], [p.y for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def main():
    blend, out = sys.argv[1], sys.argv[2]
    bpy.ops.wm.open_mainfile(filepath=blend)
    W, D = 6.0, 5.0
    fig, ax = plt.subplots(figsize=(11, 10), dpi=150)
    ax.set_aspect("equal")
    ax.set_facecolor("#f4f2ed")
    # 벽
    for o in bpy.data.objects:
        if o.name.startswith("stu_wall") and o.type == "MESH" and "colonly" not in o.name:
            x0, y0, x1, y1 = footprint(o)
            ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, color="#3a3a3a"))
    # 가구 (충돌체 풋프린트)
    for o in bpy.data.objects:
        if not o.name.endswith("convcolonly"):
            continue
        key = o.name.replace("-convcolonly", "")
        x0, y0, x1, y1 = footprint(o)
        ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, facecolor="#d9cdb8", edgecolor="#5b4a35", lw=1.2))
        narrow = (x1 - x0) < 0.4 and (y1 - y0) > 0.8
        ax.text((x0 + x1) / 2, (y0 + y1) / 2, LABELS.get(key, key), ha="center", va="center", fontsize=9, color="#2b2b2b",
                rotation=90 if narrow else 0)
    # 창
    ax.add_patch(Rectangle((1.3, 4.98), 3.4, 0.24, facecolor="#9fc3d8", edgecolor="#333", lw=1))
    ax.text(3.0, 5.42, "창 3.4 m (블라인드) — 창밖: 비 내리는 도시", ha="center", fontsize=9)
    # 문 + 열림 궤적
    ax.add_patch(Rectangle((0.5, -0.2), 0.9, 0.2, facecolor="#f4f2ed", edgecolor="none"))
    ax.plot([0.5, 0.5], [0.0, 0.9], color="#333", lw=2)
    ax.add_patch(Arc((0.5, 0.0), 1.8, 1.8, theta1=0, theta2=90, color="#777", ls="--"))
    ax.text(0.95, -0.45, "출입문 0.9 m\n(외부 상가 복도 · 택배 상자 위치)", ha="center", va="top", fontsize=9)
    # 벽 부착물
    ax.plot([2.2, 2.5], [0.03, 0.03], color="#b33", lw=4, zorder=5)
    ax.text(2.35, 0.55, "벽시계 (남벽 상부 2.0 m)", ha="center", fontsize=8, color="#b33")
    ax.plot([0.03, 0.03], [2.2, 3.1], color="#36c", lw=4)
    ax.text(0.45, 2.65, "← 냉난방기 (벽 상부 2.3 m)", fontsize=7.5, color="#36c", va="center")
    for (x0, x1) in ((0.45, 1.05), (5.0, 5.6)):
        ax.plot([x0, x1], [4.97, 4.97], color="#222", lw=5)
    ax.plot([5.97, 5.97], [1.1, 2.9], color="#222", lw=5)
    ax.text(5.8, 3.05, "흡음재", fontsize=7.5, ha="center")
    # 치수선
    ax.annotate("", xy=(0, -0.95), xytext=(W, -0.95), arrowprops=dict(arrowstyle="<->", lw=1))
    ax.text(W / 2, -1.08, "6.00 m", ha="center", va="top", fontsize=10)
    ax.annotate("", xy=(W + 0.55, 0), xytext=(W + 0.55, D), arrowprops=dict(arrowstyle="<->", lw=1))
    ax.text(W + 0.65, D / 2, "5.00 m", rotation=90, va="center", fontsize=10)
    ax.set_title("현대 음성 복원 작업실 — 평면도  (30.0 m² ≈ 9.1평 · 천장고 2.65 m)", fontsize=13, pad=14)
    ax.text(-0.3, -1.45, "출처: art/blender/environments/studio/stu_studio.blend (충돌체 풋프린트 기준)  ·  N ↑",
            fontsize=8, color="#666")
    ax.set_xlim(-0.6, W + 1.0)
    ax.set_ylim(-1.7, D + 0.7)
    ax.axis("off")
    fig.savefig(out, bbox_inches="tight", facecolor="white")
    print("plan ->", out)


if __name__ == "__main__":
    main()
