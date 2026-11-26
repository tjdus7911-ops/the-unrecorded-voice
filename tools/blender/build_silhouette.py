"""[PH_] 소은(어린이) 실루엣 — 1998 복도 끝에 잠깐 나타나는 연출용 (어두운 역광 실루엣 전용, 얼굴·디테일 없음).
MakeHuman CC0 기본 메시를 아이 비율(머리 크게·다리 짧게)로 바꾸고 팔을 내린 뒤 단순 원피스 실루엣을 더한다.
정식 캐릭터 모델은 PHASE 승인 후 별도 제작. 출력: game/assets/models/characters/PH_chr_soeun_silhouette.gltf
usage: python3 tools/blender/build_silhouette.py
"""
import json
import math
import os
import sys
from pathlib import Path

import bpy  # noqa: F401
import bmesh
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MH = ROOT / "art/third_party/makehuman"
OUT = ROOT / "game/assets/models/characters/PH_chr_soeun_silhouette.gltf"
HEIGHT = 1.30


def main():
    T.reset_scene()
    V, F = [], []
    g = None
    for ln in open(MH / "base.obj"):
        if ln.startswith("v "):
            V.append([float(x) for x in ln.split()[1:4]])
        elif ln.startswith("g "):
            g = ln.split()[1]
        elif ln.startswith("f ") and g == "body":
            F.append([int(t.split("/")[0]) - 1 for t in ln.split()[1:]])
    V = np.array(V)
    sk = json.loads((MH / "default.mhskel").read_text())
    wt = json.loads((MH / "default_weights.mhw").read_text())["weights"]
    J = lambda n: V[sk["joints"][n]].mean(0)
    neck = J(sk["bones"]["neck01"]["head"])
    # 팔 내리기: 어깨 관절 기준으로 팔 웨이트만큼 회전 (A자세 → 차렷에 가깝게)
    for side, sgn in (("L", 1), ("R", -1)):
        sh = J(sk["bones"][f"upperarm01.{side}"]["head"])
        w = np.zeros(len(V))
        for b in ["upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist", "metacarpal1", "metacarpal2",
                  "metacarpal3", "metacarpal4"] + [f"finger{f}-{s}" for f in range(1, 6) for s in range(1, 4)]:
            for i, x in wt.get(f"{b}.{side}", []):
                w[i] += x
        w = np.clip(w, 0, 1)
        a = math.radians(-38) * sgn
        R = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])
        rel = V - sh
        V = V + (rel @ R.T - rel) * w[:, None]
    # 아이 비율: 목 위(머리)를 크게
    head = V[:, 1] > neck[1]
    V[head] = neck + (V[head] - neck) * 1.28
    # 다리 짧게 (골반 아래 y 압축)
    hip = J(sk["bones"]["pelvis.L"]["head"])[1]
    low = V[:, 1] < hip
    V[low, 1] = hip + (V[low, 1] - hip) * 0.86
    ymin, ymax = V[:, 1].min(), V[:, 1].max()
    s = HEIGHT / (ymax - ymin)
    V = (V - np.array([0, ymin, 0])) * s
    me = bpy.data.meshes.new("PH_chr_soeun_silhouette")
    used = sorted({i for f in F for i in f})
    remap = {v: k for k, v in enumerate(used)}
    bm = bmesh.new()
    vs = [bm.verts.new((V[i][0], -V[i][2], V[i][1])) for i in used]
    for f in F:
        try:
            bm.faces.new([vs[remap[i]] for i in f])
        except ValueError:
            pass
    # 단순 원피스 (허리 → 무릎 위, 원뿔대)
    waist_y = (hip - ymin) * s + 0.08
    hem_y = waist_y - 0.42
    ring_top, ring_bot = [], []
    for k in range(24):
        t = k / 24 * 2 * math.pi
        ring_top.append(bm.verts.new((math.cos(t) * 0.125, math.sin(t) * 0.085, waist_y)))
        ring_bot.append(bm.verts.new((math.cos(t) * 0.215, math.sin(t) * 0.17, hem_y)))
    for k in range(24):
        k2 = (k + 1) % 24
        bm.faces.new([ring_top[k], ring_top[k2], ring_bot[k2], ring_bot[k]])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("PH_chr_soeun_silhouette", me)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new("PH_silhouette_dark")
    m.diffuse_color = (0.02, 0.02, 0.025, 1)
    me.materials.append(m)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLTF_SEPARATE", use_selection=True, export_yup=True)
    print("silhouette", len(me.vertices), "verts")


if __name__ == "__main__":
    main()
