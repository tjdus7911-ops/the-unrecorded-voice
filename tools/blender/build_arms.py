"""서정우(37세) 1인칭 손·팔 — 메시, 리그, 스킨 텍스처 베이크, 카디건 소매, glTF 익스포트.

베이스: MakeHuman 1.x 기본 메시 + 기본 스켈레톤·웨이트 (CC0, art/third_party/makehuman/LICENSE.md)
 - 손(손목 위 7 cm까지)만 MakeHuman 메시에서 잘라 서브디비전 2단계
 - 손톱·마디 주름·손바닥 손금·핏줄·모공은 정점 속성(좌표) + 절차적 셰이더 → 2048 텍스처 베이크
 - 소매: 팔 표면 반지름을 측정해 스윕한 튜브 (팔꿈치 안쪽 주름, 소맷부리 근처 뭉침, 2x2 고무단)
 - 리그: 위팔(2)·아래팔(2, 비틀림 분산)·손목·손허리뼈 4·손가락 15 x 좌우
   손가락 뼈 로컬 X = 굽힘 축, Z = 손등 방향 (굽힘 = -X 회전)
출력: game/assets/models/characters/chr_jungwoo_arms.gltf (+.bin), 텍스처 game/assets/textures/chr/
       art/blender/characters/chr_jungwoo_arms.blend, 검토 렌더 art/renders/characters/
usage: python3 tools/blender/build_arms.py [--no-bake] [--render]
"""
import json
import math
import os
import sys
from pathlib import Path

import bpy  # noqa: F401  (bmesh는 bpy 이후)
import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MH = ROOT / "art/third_party/makehuman"
TEX = ROOT / "game/assets/textures/chr"
OUT_GLTF = ROOT / "game/assets/models/characters/chr_jungwoo_arms.gltf"
OUT_BLEND = ROOT / "art/blender/characters/chr_jungwoo_arms.blend"
RENDERS = ROOT / "art/renders/characters"
POSES = ROOT / "game/data/characters/hand_poses.json"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]

S = 0.104          # MakeHuman dm → m, x1.04 (키 약 176 cm, 손 길이 약 18.4 cm — 37세 한국 남성)
BAKE = 2048

ARM_BONES = ["upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist",
             "metacarpal1", "metacarpal2", "metacarpal3", "metacarpal4"] + \
            [f"finger{f}-{s}" for f in range(1, 6) for s in range(1, 4)]
HAND_BONES = set(ARM_BONES[4:])
DISTAL = [f"finger{f}-3" for f in range(1, 6)]


def conv(p):
    """MakeHuman OBJ (Y-up, dm) → Blender (Z-up, m). 캐릭터 정면 = -Y."""
    return Vector((p[0] * S, -p[2] * S, p[1] * S))


# ------------------------------------------------------------------ MakeHuman 데이터
def load_mh():
    V, VT, F = [], [], []
    group = None
    for line in open(MH / "base.obj"):
        if line.startswith("v "):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("vt "):
            VT.append([float(x) for x in line.split()[1:3]])
        elif line.startswith("g "):
            group = line.split()[1]
        elif line.startswith("f ") and group == "body":
            F.append([tuple(int(x) - 1 for x in t.split("/")[:2]) for t in line.split()[1:]])
    V = np.array(V)
    sk = json.loads((MH / "default.mhskel").read_text())
    wt = json.loads((MH / "default_weights.mhw").read_text())["weights"]
    return V, VT, F, sk, wt


def joint(V, sk, name):
    return conv(V[sk["joints"][name]].mean(0))


def bone_frames(V, sk, side="L"):
    """뼈마다 head, tail, Z(손등/팔꿈치 바깥) 벡터."""
    out = {}
    J = lambda n: joint(V, sk, n)
    for b in ARM_BONES:
        bb = sk["bones"][f"{b}.{side}"]
        h, t = J(bb["head"]), J(bb["tail"])
        y = (t - h).normalized()
        P = [J(n) for n in sk["planes"][bb["rotation_plane"]]]
        n = (P[1] - P[0]).cross(P[2] - P[0]).normalized()
        if b == "wrist":
            # 손바닥 평면 법선 = Z. 부호는 가운뎃손가락이 휘는 반대쪽(손등)
            fb = sk["bones"][f"finger3-1.{side}"]
            W, B, Tt = J(sk["bones"][f"wrist.{side}"]["head"]), J(fb["tail"]), J(sk["bones"][f"finger3-3.{side}"]["tail"])
            ref = B - (W + (Tt - W) * ((B - W).dot(Tt - W) / (Tt - W).length_squared))
            z = n if n.dot(ref) > 0 else -n
            z = (z - y * z.dot(y)).normalized()
        else:
            # 굽힘 평면: P0=끝, P1=가운데 마디, P2=시작 — 가운데 마디가 현(chord)에서 벗어난 쪽이 손등/팔꿈치 바깥
            A, M, C = P[2], P[1], P[0]
            ref = M - (A + (C - A) * ((M - A).dot(C - A) / (C - A).length_squared))
            x = n
            z = x.cross(y)
            if z.dot(ref) < 0:
                z = -z
            z = (z - y * z.dot(y)).normalized()
        out[b] = {"head": h, "tail": t, "z": z, "parent": bb["parent"].rsplit(".", 1)[0]}
    return out


# ------------------------------------------------------------------ 손 메시
def build_hand_mesh(V, VT, F, wt, frames, side="L"):
    nv = len(V)
    w = {b: np.zeros(nv) for b in ARM_BONES}
    for b in ARM_BONES:
        for i, x in wt.get(f"{b}.{side}", []):
            w[b][i] = x
    other = np.zeros(nv)
    for k, lst in wt.items():
        if k.endswith(f".{side}") and k.rsplit(".", 1)[0] not in ARM_BONES:
            for i, x in lst:
                other[i] += x
    hand = sum(w[b] for b in HAND_BONES)
    low = w["lowerarm01"] + w["lowerarm02"]
    P = np.array([conv(p) for p in V])
    wr = frames["wrist"]["head"]
    el = frames["lowerarm01"]["head"]
    ax = (wr - el).normalized()
    t_from_wrist = (P - np.array(wr)) @ np.array(ax)          # 손목 관절 기준 (+는 손 쪽)
    keep = (hand > 0.35) | (((low + hand) > 0.5) & (t_from_wrist > -0.07))
    keep &= (P[:, 0] > 0.02) if side == "L" else (P[:, 0] < -0.02)
    faces = [f for f in F if all(keep[vi] for vi, _ in f)]
    used = sorted({vi for f in faces for vi, _ in f})
    remap = {vi: k for k, vi in enumerate(used)}
    me = bpy.data.meshes.new(f"chr_hand_{side}")
    bm = bmesh.new()
    bv = [bm.verts.new(P[vi]) for vi in used]
    uvl = bm.loops.layers.uv.new("mh")
    for f in faces:
        try:
            face = bm.faces.new([bv[remap[vi]] for vi, _ in f])
        except ValueError:
            continue
        for loop, (_, ti) in zip(face.loops, f):
            loop[uvl].uv = VT[ti]
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"chr_hand_{side}", me)
    bpy.context.scene.collection.objects.link(ob)
    # 웨이트: 포함 안 된 뼈(어깨·쇄골 등)는 아래팔로
    groups = {b: ob.vertex_groups.new(name=f"{b}.{side}") for b in ARM_BONES}
    for k, vi in enumerate(used):
        tot = 0.0
        for b in ARM_BONES:
            if w[b][vi] > 1e-4:
                groups[b].add([k], float(w[b][vi]), "REPLACE")
                tot += w[b][vi]
        if tot < 0.999:
            groups["lowerarm02"].add([k], float(1 - tot), "ADD")
    for p in me.polygons:
        p.use_smooth = True
    # 서브디비전 2단계 적용 (웨이트·UV 보간)
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = 2
    m.render_levels = 2
    m.uv_smooth = "PRESERVE_BOUNDARIES"
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="sub")
    return ob


def weights_array(ob, names):
    W = np.zeros((len(ob.data.vertices), len(names)))
    idx = {ob.vertex_groups[n].index: k for k, n in enumerate(names) if n in ob.vertex_groups}
    for v in ob.data.vertices:
        for g in v.groups:
            if g.group in idx:
                W[v.index, idx[g.group]] = g.weight
    return W


def write_attributes(ob, frames, side="L"):
    """손톱·마디·부위 마스크용 좌표를 정점 속성으로 (셰이더에서 선명한 경계로 복원)."""
    me = ob.data
    P = np.array([v.co for v in me.vertices])
    N = np.array([v.normal for v in me.vertices])
    names = [f"{b}.{side}" for b in ARM_BONES]
    W = weights_array(ob, names)
    bi = {b: k for k, b in enumerate(ARM_BONES)}
    nv = len(P)
    nail = np.zeros((nv, 4))
    nail[:, 0] = -1
    jnt = np.zeros((nv, 4))
    jnt[:, 0] = 0.5
    reg = np.zeros((nv, 4))
    # --- 손톱: 끝마디 뼈 좌표 (t=뼈 길이 비율, v=옆 방향/손톱 반폭, d=손등 방향 내적)
    for b in DISTAL:
        f = frames[b]
        h, t, z = np.array(f["head"]), np.array(f["tail"]), np.array(f["z"])
        y = (t - h)
        L = np.linalg.norm(y)
        y /= L
        x = np.cross(y, z)
        sel = W[:, bi[b]] > 0.5
        rel = P[sel] - h
        tt = rel @ y / L
        lat = rel @ x
        up = rel @ z
        rad = np.sqrt(lat ** 2 + up ** 2)
        r = np.percentile(rad, 70)
        half = (0.80 if b == "finger1-3" else 0.74) * r
        d = N[sel] @ z
        idx = np.where(sel)[0]
        nail[idx, 0] = tt
        nail[idx, 1] = lat / half
        nail[idx, 2] = d
        nail[idx, 3] = 1.0 if b != "finger1-3" else 2.0
    # --- 마디 주름: 가장 가까운 손가락 관절까지 뼈 축 방향 거리(mm), 손등 방향
    joints = []
    for f in range(1, 6):
        for s in (1, 2, 3):
            b = f"finger{f}-{s}"
            fr = frames[b]
            strength = {1: 0.55, 2: 1.0, 3: 0.75}[s] if f != 1 else {1: 0.3, 2: 0.8, 3: 0.9}[s]
            joints.append((np.array(fr["head"]), np.array((fr["tail"] - fr["head"]).normalized()),
                           np.array(fr["z"]), strength, b))
    wfr = frames["wrist"]
    joints.append((np.array(wfr["head"]), np.array((wfr["tail"] - wfr["head"]).normalized()),
                   np.array(wfr["z"]), 0.9, "wrist"))
    best = np.full(nv, 1e9)
    for h, y, z, st, b in joints:
        rel = P - h
        along = rel @ y
        radial = np.linalg.norm(rel - np.outer(along, y), axis=1)
        dist = np.sqrt(along ** 2 + (radial * 0.35) ** 2)
        near = dist < best
        # 관절 영향 범위: 손가락은 반경 ~1.5 cm 안쪽만
        near &= radial < (0.016 if b != "wrist" else 0.045)
        best[near] = dist[near]
        jnt[near, 0] = np.clip(along[near] / 0.02 * 0.5 + 0.5, 0, 1)       # ±20 mm → 0..1
        jnt[near, 1] = (N[near] @ z) * 0.5 + 0.5
        jnt[near, 2] = st
        jnt[near, 3] = 1.0 if b == "wrist" else 0.0
    # --- 부위: R 손등, G 손바닥, B 아래팔(손목 위), A 손가락 끝 바닥(지문)
    hz = np.array(frames["wrist"]["z"])
    meta = W[:, [bi[f"metacarpal{k}"] for k in range(1, 5)]].sum(1) + W[:, bi["wrist"]]
    dors = N @ hz
    reg[:, 0] = np.clip(meta, 0, 1) * np.clip(dors * 2.0, 0, 1)
    reg[:, 1] = np.clip(meta + W[:, bi["finger1-1"]], 0, 1) * np.clip(-dors * 2.0, 0, 1)
    reg[:, 2] = np.clip(W[:, bi["lowerarm01"]] + W[:, bi["lowerarm02"]], 0, 1)
    for b in DISTAL:
        z = np.array(frames[b]["z"])
        reg[:, 3] += W[:, bi[b]] * np.clip(-(N @ z) * 1.5, 0, 1)
    reg = np.clip(reg, 0, 1)
    for name, arr in (("tuv_nail", nail), ("tuv_joint", jnt), ("tuv_region", reg)):
        a = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
        a.data.foreach_set("color", arr.astype(np.float32).ravel())


# ------------------------------------------------------------------ 피부 셰이더 (베이크 원본)
class G:
    def __init__(self, nt):
        self.nt = nt

    def n(self, kind, **kw):
        node = self.nt.nodes.new(kind)
        for k, v in kw.items():
            setattr(node, k, v)
        return node

    def _in(self, sock, val):
        if isinstance(val, (int, float)):
            sock.default_value = val
        elif isinstance(val, tuple):
            sock.default_value = val if len(val) == 4 or sock.type != "RGBA" else (*val, 1)
        else:
            self.nt.links.new(val, sock)

    def m(self, op, a, b=0.0, c=None, clamp=False):
        node = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._in(node.inputs[0], a)
        self._in(node.inputs[1], b)
        if c is not None:
            self._in(node.inputs[2], c)
        return node.outputs[0]

    def ss(self, x, a, b):
        """smoothstep(a, b, x)"""
        node = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
        self._in(node.inputs["Value"], x)
        node.inputs["From Min"].default_value = a
        node.inputs["From Max"].default_value = b
        return node.outputs["Result"]

    def mix(self, a, b, f):
        node = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MIX", clamp_factor=True)
        self._in(node.inputs["Factor"], f)
        self._in(node.inputs[6], a)
        self._in(node.inputs[7], b)
        return node.outputs[2]

    def mulc(self, a, b):
        node = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY", clamp_factor=True)
        node.inputs["Factor"].default_value = 1.0
        self._in(node.inputs[6], a)
        self._in(node.inputs[7], b)
        return node.outputs[2]

    def attr(self, name):
        node = self.n("ShaderNodeAttribute", attribute_name=name, attribute_type="GEOMETRY")
        sep = self.n("ShaderNodeSeparateColor")
        self.nt.links.new(node.outputs["Color"], sep.inputs["Color"])
        alpha = node.outputs["Alpha"]
        return sep.outputs[0], sep.outputs[1], sep.outputs[2], alpha

    def noise(self, vec, scale, detail=4.0, rough=0.5, dist=0.0):
        node = self.n("ShaderNodeTexNoise")
        self._in(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        node.inputs["Distortion"].default_value = dist
        return node.outputs["Fac"]

    def voronoi(self, vec, scale):
        node = self.n("ShaderNodeTexVoronoi", feature="F1")
        self._in(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = scale
        return node.outputs["Distance"]

    def vec_scale(self, vec, sx, sy, sz, rot=(0, 0, 0)):
        node = self.n("ShaderNodeMapping")
        self._in(node.inputs["Vector"], vec)
        node.inputs["Scale"].default_value = (sx, sy, sz)
        node.inputs["Rotation"].default_value = rot
        return node.outputs["Vector"]


def skin_shader(ob, frames):
    """절차적 피부: 반환 (재질, 알베도·거칠기·높이 소켓 노드 이름) — 베이크 전용."""
    mat = bpy.data.materials.new("bake_skin")
    nt = mat.node_tree
    nt.nodes.clear()
    g = G(nt)
    out = g.n("ShaderNodeOutputMaterial")
    tc = g.n("ShaderNodeTexCoord")
    tc.object = ob
    pos = tc.outputs["Object"]
    # 팔 축 기준 좌표 (핏줄·결 방향을 손~아래팔 축에 맞춤)
    el, wr = frames["lowerarm01"]["head"], frames["wrist"]["head"]
    axis = (wr - el).normalized()
    q = axis.to_track_quat("Z", "Y").to_euler()
    loc = g.n("ShaderNodeMapping", vector_type="POINT")
    g._in(loc.inputs["Vector"], pos)
    # 회전 역변환: 팔 축을 로컬 Z로
    m_inv = q.to_matrix().inverted().to_euler()
    loc.inputs["Rotation"].default_value = m_inv
    apos = loc.outputs["Vector"]                    # Z = 팔(손가락) 방향

    nu, nv_, nd, nk = g.attr("tuv_nail")            # t, 옆, 손등 내적, 손가락(1 일반 / 2 엄지)
    jd, jdors, jst, jwr = g.attr("tuv_joint")
    rb, rp, rf, rtip = g.attr("tuv_region")

    # ---------- 손톱 마스크 (둥근 큐티클 경계, 끝은 손끝 밖까지)
    v2 = g.m("MULTIPLY", nv_, nv_)
    is_d = g.m("GREATER_THAN", nk, 0.5)
    thumb = g.m("GREATER_THAN", nk, 1.5)
    cut0 = g.m("ADD", g.m("MULTIPLY_ADD", thumb, -0.06, 0.47), g.m("MULTIPLY", v2, 0.20))   # 큐티클 호
    in_u = g.ss(g.m("SUBTRACT", nu, cut0), 0.0, 0.025)
    in_v = g.ss(g.m("SUBTRACT", 1.0, g.m("ABSOLUTE", nv_)), 0.0, 0.08)
    in_d = g.ss(nd, 0.15, 0.4)
    nail = g.m("MULTIPLY", g.m("MULTIPLY", in_u, in_v), g.m("MULTIPLY", in_d, is_d))
    lunula = g.m("MULTIPLY", nail, g.m("SUBTRACT", 1.0, g.ss(g.m("SUBTRACT", nu, cut0), 0.05, 0.11)))
    lunula = g.m("MULTIPLY", lunula, g.ss(g.m("SUBTRACT", 0.75, g.m("ABSOLUTE", nv_)), 0.0, 0.25))
    free_edge = g.m("MULTIPLY", nail, g.ss(nu, 0.93, 0.985))
    cuticle = g.m("MULTIPLY", g.m("MULTIPLY", in_v, g.m("MULTIPLY", in_d, is_d)),
                  g.m("SUBTRACT", g.ss(g.m("SUBTRACT", nu, cut0), -0.05, 0.0), in_u))
    sidewall = g.m("MULTIPLY", g.m("MULTIPLY", in_u, g.m("MULTIPLY", in_d, is_d)),
                   g.m("SUBTRACT", g.ss(g.m("SUBTRACT", 1.08, g.m("ABSOLUTE", nv_)), 0.0, 0.08), in_v))
    # 손톱 세로 결
    ridge = g.noise(g.vec_scale(apos, 2600, 2600, 120), 1.0, detail=2.0)

    # ---------- 마디 주름 (손등: 가는 줄 여러 개, 손바닥: 깊은 금 1~2개)
    dmm = g.m("MULTIPLY", g.m("SUBTRACT", jd, 0.5), 40.0)            # mm
    jitter = g.noise(g.vec_scale(apos, 900, 900, 300), 1.0, detail=2.0)
    dmm_j = g.m("ADD", dmm, g.m("MULTIPLY", g.m("SUBTRACT", jitter, 0.5), 1.2))
    env = g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", dmm, dmm), -1.0 / 18.0))     # σ ≈ 3 mm
    lines = g.m("POWER", g.m("ABSOLUTE", g.m("SINE", g.m("MULTIPLY", dmm_j, 2.6))), 0.35)
    dorsal = g.ss(jdors, 0.55, 0.8)
    palmar = g.ss(g.m("SUBTRACT", 1.0, jdors), 0.6, 0.85)
    not_wr = g.m("SUBTRACT", 1.0, jwr)
    kn_dors = g.m("MULTIPLY", g.m("MULTIPLY", env, g.m("SUBTRACT", 1.0, lines)), g.m("MULTIPLY", dorsal, jst))
    kn_dors = g.m("MULTIPLY", kn_dors, not_wr)
    crease_p = g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", dmm_j, dmm_j), -1.0 / 0.25))
    crease_p2 = g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", g.m("SUBTRACT", dmm_j, 2.2), g.m("SUBTRACT", dmm_j, 2.2)), -1.0 / 0.3))
    creases = g.m("MULTIPLY", g.m("ADD", crease_p, g.m("MULTIPLY", crease_p2, 0.6)), g.m("MULTIPLY", palmar, jst))
    # 손목 안쪽 팔찌 주름 2줄
    wr_cr = g.m("MULTIPLY", g.m("MULTIPLY", jwr, palmar),
                g.m("ADD", g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", g.m("SUBTRACT", dmm_j, -4.0), g.m("SUBTRACT", dmm_j, -4.0)), -1.0 / 0.35)),
                    g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", g.m("SUBTRACT", dmm_j, -9.0), g.m("SUBTRACT", dmm_j, -9.0)), -1.0 / 0.5))))
    # ---------- 손바닥 손금 (큰 금 3개: 굴곡 노이즈 능선)
    palm_lines = g.noise(g.vec_scale(apos, 18, 18, 9), 1.0, detail=1.5, dist=0.4)
    pl = g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", g.m("SUBTRACT", palm_lines, 0.5), g.m("SUBTRACT", palm_lines, 0.5)), -1.0 / 0.0012))
    pl = g.m("MULTIPLY", pl, rp)
    # ---------- 핏줄 (손등·손목 위 — 능선 노이즈를 팔 방향으로 늘림)
    vn = g.noise(g.vec_scale(apos, 55, 55, 14), 1.0, detail=2.0, rough=0.45, dist=0.25)
    vein = g.m("EXPONENT", g.m("MULTIPLY", g.m("MULTIPLY", g.m("SUBTRACT", vn, 0.5), g.m("SUBTRACT", vn, 0.5)), -1.0 / 0.0015))
    vein_mask = g.m("ADD", g.m("MULTIPLY", rb, 0.9), g.m("MULTIPLY", rf, 0.55), clamp=True)
    vein_mask = g.m("MULTIPLY", vein_mask, g.m("SUBTRACT", 1.0, rp))
    vein = g.m("MULTIPLY", vein, vein_mask)
    # ---------- 미세 피부결: 모공 + 교차 잔주름
    pores = g.m("SUBTRACT", 1.0, g.ss(g.voronoi(pos, 2600), 0.0, 0.32))
    hatch_a = g.noise(g.vec_scale(apos, 2200, 160, 600, (0, 0, 0.7)), 1.0, detail=1.0)
    hatch_b = g.noise(g.vec_scale(apos, 160, 2200, 600, (0, 0, 0.7)), 1.0, detail=1.0)
    hatch = g.m("ADD", g.m("ABSOLUTE", g.m("SUBTRACT", hatch_a, 0.5)), g.m("ABSOLUTE", g.m("SUBTRACT", hatch_b, 0.5)))
    fine = g.noise(pos, 700, detail=5.0, rough=0.6)
    # 지문 (손가락 끝 바닥)
    fp = g.n("ShaderNodeTexWave", wave_type="RINGS", rings_direction="SPHERICAL")
    g._in(fp.inputs["Vector"], g.vec_scale(apos, 1, 1, 1))
    fp.inputs["Scale"].default_value = 1900
    fp.inputs["Distortion"].default_value = 3.0
    fprint = g.m("MULTIPLY", fp.outputs["Fac"], rtip)

    # ---------- 높이 (1.0 = 1 mm)
    hgt = g.m("MULTIPLY", nail, 0.22)
    hgt = g.m("ADD", hgt, g.m("MULTIPLY", g.m("MULTIPLY", ridge, nail), 0.02))
    hgt = g.m("SUBTRACT", hgt, g.m("MULTIPLY", cuticle, 0.12))
    hgt = g.m("SUBTRACT", hgt, g.m("MULTIPLY", sidewall, 0.10))
    hgt = g.m("SUBTRACT", hgt, g.m("MULTIPLY", kn_dors, 0.09))
    hgt = g.m("SUBTRACT", hgt, g.m("MULTIPLY", creases, 0.22))
    hgt = g.m("SUBTRACT", hgt, g.m("MULTIPLY", wr_cr, 0.12))
    hgt = g.m("SUBTRACT", hgt, g.m("MULTIPLY", pl, 0.18))
    hgt = g.m("ADD", hgt, g.m("MULTIPLY", vein, 0.45))
    skin_only = g.m("SUBTRACT", 1.0, nail)
    micro = g.m("ADD", g.m("MULTIPLY", pores, -0.018), g.m("MULTIPLY", hatch, -0.03))
    micro = g.m("ADD", micro, g.m("MULTIPLY", g.m("SUBTRACT", fine, 0.5), 0.02))
    micro = g.m("ADD", micro, g.m("MULTIPLY", fprint, 0.012))
    hgt = g.m("ADD", hgt, g.m("MULTIPLY", micro, skin_only))

    # ---------- 색 (선형)
    base = (0.50, 0.285, 0.195)
    tan = (0.44, 0.245, 0.16)
    palm_c = (0.60, 0.34, 0.255)
    red = (0.52, 0.21, 0.15)
    tone = g.noise(pos, 22, detail=3.0)
    col = g.mix(base, tan, g.m("MULTIPLY", rb, 0.8))
    col = g.mix(col, palm_c, rp)
    col = g.mix(col, (0.47, 0.27, 0.19), g.m("MULTIPLY", g.m("SUBTRACT", tone, 0.5), 0.8))
    redness = g.m("ADD", g.m("MULTIPLY", env, g.m("MULTIPLY", jst, 0.55)), g.m("MULTIPLY", rtip, 0.45), clamp=True)
    col = g.mix(col, red, g.m("MULTIPLY", redness, 0.55))
    col = g.mix(col, (0.30, 0.17, 0.12), g.m("MULTIPLY", g.m("ADD", kn_dors, g.m("MULTIPLY", creases, 0.6)), 0.6))
    col = g.mix(col, (0.36, 0.26, 0.24), g.m("MULTIPLY", vein, 0.35))     # 비치는 정맥 (약하게)
    # 작은 잡티·점
    spots = g.ss(g.noise(pos, 260, detail=2.0), 0.68, 0.74)
    col = g.mix(col, (0.33, 0.19, 0.12), g.m("MULTIPLY", g.m("MULTIPLY", spots, rb), 0.45))
    # 손톱
    nail_c = g.mix((0.70, 0.45, 0.38), (0.62, 0.36, 0.31), g.m("MULTIPLY", ridge, 0.6))
    nail_c = g.mix(nail_c, (0.84, 0.68, 0.62), lunula)
    nail_c = g.mix(nail_c, (0.86, 0.80, 0.70), free_edge)
    col = g.mix(col, nail_c, nail)
    col = g.mix(col, (0.42, 0.22, 0.16), g.m("MULTIPLY", cuticle, 0.7))

    # ---------- 거칠기
    r_val = g.m("ADD", 0.50, g.m("MULTIPLY", rp, 0.10))
    r_val = g.m("ADD", r_val, g.m("MULTIPLY", g.m("ADD", kn_dors, creases), 0.12))
    r_val = g.m("ADD", r_val, g.m("MULTIPLY", g.m("SUBTRACT", fine, 0.5), 0.08))
    r_val = g.m("ADD", g.m("MULTIPLY", r_val, skin_only), g.m("MULTIPLY", nail, 0.26))

    # 출력 노드 묶음
    emit = g.n("ShaderNodeEmission")
    emit.name = "BAKE_EMIT"
    bsdf = g.n("ShaderNodeBsdfPrincipled")
    bsdf.name = "BAKE_BSDF"
    bump = g.n("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.001
    g._in(bump.inputs["Height"], hgt)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    g._in(bsdf.inputs["Base Color"], col)
    rgb_r = g.n("ShaderNodeCombineColor")
    g._in(rgb_r.inputs[0], r_val)
    g._in(rgb_r.inputs[1], r_val)
    g._in(rgb_r.inputs[2], r_val)
    mat["col_socket"] = 0
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat, out, emit, bsdf, col, rgb_r.outputs[0]


def bake_skin(ob, frames):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.margin = 12
    sc.render.bake.margin_type = "EXTEND"
    # UV: 스마트 프로젝트 (MakeHuman UV는 전신용이라 손 해상도가 낮음)
    me = ob.data
    if "bake" not in me.uv_layers:
        me.uv_layers.new(name="bake")
    me.uv_layers.active = me.uv_layers["bake"]
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    mat, out, emit, bsdf, col, rough = skin_shader(ob, frames)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    nt = mat.node_tree
    TEX.mkdir(parents=True, exist_ok=True)

    def target(name, noncolor):
        img = bpy.data.images.new(name, BAKE, BAKE, alpha=False, float_buffer=False)
        img.colorspace_settings.name = "Non-Color" if noncolor else "sRGB"
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        for n in nt.nodes:
            n.select = False
        node.select = True
        nt.nodes.active = node
        return img, node

    def save(img, fname):
        img.filepath_raw = str(TEX / fname)
        img.file_format = "PNG"
        img.save()

    # 알베도 · 거칠기: 이미션 베이크
    img_a, _ = target("chr_skin_albedo", False)
    nt.links.new(col, emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    bpy.ops.object.bake(type="EMIT")
    save(img_a, "chr_skin_albedo.png")
    img_r, _ = target("chr_skin_rough", True)
    nt.links.new(rough, emit.inputs["Color"])
    bpy.ops.object.bake(type="EMIT")
    # AO (손가락 사이 그늘)
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    img_o, _ = target("chr_skin_ao", True)
    sc.cycles.samples = 48
    bpy.ops.object.bake(type="AO")
    sc.cycles.samples = 1
    # 노멀 (탄젠트 공간, OpenGL +Y)
    img_n, _ = target("chr_skin_normal", True)
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z")
    save(img_n, "chr_skin_normal.png")
    # ORM 패킹
    def px(img):
        a = np.empty(BAKE * BAKE * 4, np.float32)
        img.pixels.foreach_get(a)
        return a.reshape(-1, 4)
    o, r = px(img_o), px(img_r)
    orm = bpy.data.images.new("chr_skin_orm", BAKE, BAKE, alpha=False)
    orm.colorspace_settings.name = "Non-Color"
    packed = np.stack([0.35 + 0.65 * o[:, 0], r[:, 0], np.zeros(len(o)), np.ones(len(o))], -1)
    orm.pixels.foreach_set(packed.astype(np.float32).ravel())
    save(orm, "chr_skin_orm.png")


def mat_from_images(name, prefix, sheen=0.0, sss=0.0):
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = T._nodes(m)
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "bake"

    def img(suffix, noncolor):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(str(TEX / f"{prefix}_{suffix}.png"), check_existing=True)
        if noncolor:
            t.image.colorspace_settings.name = "Non-Color"
        nt.links.new(uv.outputs["UV"], t.inputs["Vector"])
        return t
    nt.links.new(img("albedo", False).outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(img("orm", True).outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.uv_map = "bake"
    nt.links.new(img("normal", True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if sss:
        bsdf.inputs["Subsurface Weight"].default_value = sss
        bsdf.inputs["Subsurface Radius"].default_value = (0.012, 0.004, 0.0025)
    if sheen:
        bsdf.inputs["Sheen Weight"].default_value = sheen
    m["tuv_tex"] = prefix
    return m


# ------------------------------------------------------------------ 소매 (카디건)
def chain_curve(frames):
    pts = [frames["upperarm01"]["head"], frames["lowerarm01"]["head"], frames["wrist"]["head"]]
    return pts


def build_sleeve(V, F, wt, frames, side="L"):
    """팔 표면을 각도 32칸 x 단면 N개로 측정 → 여유분 + 주름 → 두께 있는 튜브."""
    nv = len(V)
    P = np.array([conv(p) for p in V])
    armw = np.zeros(nv)
    for b in ["upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "shoulder01"]:
        for i, x in wt.get(f"{b}.{side}", []):
            armw[i] += x
    sel = (armw > 0.45) & ((P[:, 0] > 0.02) if side == "L" else (P[:, 0] < -0.02))
    AP = P[sel]
    sh, el, wr = [np.array(frames[k]["head"]) for k in ("upperarm01", "lowerarm01", "wrist")]
    # 축: 어깨→팔꿈치→손목 (팔꿈치는 반경 4 cm로 둥글게)
    L1, L2 = np.linalg.norm(el - sh), np.linalg.norm(wr - el)
    d1, d2 = (el - sh) / L1, (wr - el) / L2
    s_cuff_end = L1 + L2 - 0.022          # 소맷부리 끝: 손목 관절 2.2 cm 위
    s_start = 0.06
    NS, NA = 72, 40

    def axis_at(s):
        bl = np.clip((s - (L1 - 0.04)) / 0.08, 0, 1)
        bl = bl * bl * (3 - 2 * bl)
        c = sh + d1 * s if s < L1 else el + d2 * (s - L1)
        t = d1 * (1 - bl) + d2 * bl
        return c, t / np.linalg.norm(t)
    # 기준 법선 (팔꿈치 바깥 방향 = lowerarm Z)
    zref = np.array(frames["lowerarm01"]["z"])
    elbow_out = zref
    rings = []
    radii = np.zeros((NS, NA))
    frames_s = []
    ss = np.linspace(s_start, s_cuff_end, NS)
    prev_n = None
    for k, s in enumerate(ss):
        c, t = axis_at(s)
        n = (zref - t * zref.dot(t)) if prev_n is None else (prev_n - t * prev_n.dot(t))
        n /= np.linalg.norm(n)
        b = np.cross(t, n)
        prev_n = n
        frames_s.append((c, t, n, b))
        rel = AP - c
        along = rel @ t
        slab = np.abs(along) < 0.012
        r = rel[slab] - np.outer(along[slab], t)
        ang = np.arctan2(r @ b, r @ n)
        dist = np.linalg.norm(r, axis=1)
        bins = ((ang + np.pi) / (2 * np.pi) * NA).astype(int) % NA
        row = np.zeros(NA)
        for a in range(NA):
            m = dist[bins == a]
            row[a] = np.percentile(m, 90) if len(m) else np.nan
        # 빈 칸 보간 + 너무 먼 점(몸통 정점 섞임) 제거
        med = np.nanmedian(row) if np.isfinite(row).any() else 0.04
        row[(row > med * 1.6) | ~np.isfinite(row)] = np.nan
        idx = np.arange(NA)
        good = np.isfinite(row)
        row = np.interp(idx, idx[good], row[good], period=NA) if good.any() else np.full(NA, 0.04)
        radii[k] = row
    # 매끈하게 (각도 방향, 길이 방향)
    for _ in range(3):
        radii = (np.roll(radii, 1, 1) + 2 * radii + np.roll(radii, -1, 1)) / 4
    for _ in range(4):
        radii[1:-1] = (radii[:-2] + 2 * radii[1:-1] + radii[2:]) / 4
    rng = np.random.default_rng(11 if side == "L" else 23)
    noise_a = rng.normal(0, 1, (NS, NA))
    for _ in range(6):
        noise_a = (np.roll(noise_a, 1, 1) + 2 * noise_a + np.roll(noise_a, -1, 1)) / 4
        noise_a[1:-1] = (noise_a[:-2] + 2 * noise_a[1:-1] + noise_a[2:]) / 4
    noise_a /= noise_a.std() + 1e-9

    me = bpy.data.meshes.new(f"chr_sleeve_{side}")
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("bake")
    verts = []
    cuff_len = 0.055
    cuff_mat = []
    for k, s in enumerate(ss):
        c, t, n, b = frames_s[k]
        row = []
        # 여유분: 위팔 2.0 cm → 아래팔 1.3 cm → 고무단 0.5 cm
        ease = np.interp(s, [0, L1, s_cuff_end - cuff_len - 0.02, s_cuff_end - cuff_len, s_cuff_end],
                         [0.021, 0.015, 0.012, 0.006, 0.0055])
        for a in range(NA):
            ang = -np.pi + (a + 0.5) / NA * 2 * np.pi
            dirv = n * np.cos(ang) + b * np.sin(ang)
            r = radii[k, a] + ease
            # 팔꿈치 안쪽 주름 (안쪽 = 바깥의 반대)
            inner = max(0.0, -dirv.dot(elbow_out))
            ge = math.exp(-((s - L1) / 0.05) ** 2)
            r += 0.0045 * ge * inner * math.sin((s - L1) * 2 * math.pi / 0.021 + ang * 0.8)
            r -= 0.003 * ge * inner
            # 소맷부리 위 뭉침 (밀려 올라간 소매)
            gb = math.exp(-((s - (s_cuff_end - cuff_len - 0.03)) / 0.03) ** 2)
            r += 0.0035 * gb * math.sin(s * 2 * math.pi / 0.016 + 1.7 * math.sin(ang * 2 + k * 0.3))
            # 위팔 아래쪽 처짐 + 천의 불규칙함
            r += 0.0025 * max(0.0, -dirv[2]) * (1 - min(1.0, s / L1))
            r += 0.0014 * noise_a[k, a]
            row.append(bm.verts.new(c + dirv * r))
        verts.append(row)
    circ = 2 * np.pi * radii.mean() + 0.1
    for k in range(NS - 1):
        for a in range(NA):
            a2 = (a + 1) % NA
            f = bm.faces.new([verts[k][a], verts[k][a2], verts[k + 1][a2], verts[k + 1][a]])
            f.smooth = True
            in_cuff = ss[k] >= s_cuff_end - cuff_len
            f.material_index = 1 if in_cuff else 0
            for loop in f.loops:
                kk = k + (1 if loop.vert in (verts[k + 1][a], verts[k + 1][a2]) else 0)
                aa = a2 if loop.vert in (verts[k][a2], verts[k + 1][a2]) else a
                uu = (aa if not (aa == 0 and a == NA - 1) else NA) / NA * (2 * np.pi * 0.045) / 0.05
                loop[uvl].uv = (uu, ss[kk] / 0.05)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"chr_sleeve_{side}", me)
    bpy.context.scene.collection.objects.link(ob)
    # 두께 4 mm + 끝단 마감 (안쪽 면은 같은 니트)
    sol = ob.modifiers.new("thick", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = -1.0
    sol.use_rim = True
    sol.use_even_offset = True
    sol.material_offset_rim = 1
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="thick")
    # 웨이트: 축 거리 s 기준 (위팔 01/02 → 팔꿈치 → 아래팔 01/02 → 소맷부리 약간 손목)
    names = ["upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist"]
    vg = {n: ob.vertex_groups.new(name=f"{n}.{side}") for n in names}
    u2 = np.linalg.norm(np.array(frames["upperarm02"]["head"]) - sh)
    l2 = L1 + np.linalg.norm(np.array(frames["lowerarm02"]["head"]) - el)
    for v in ob.data.vertices:
        p = np.array(v.co)
        # 가장 가까운 단면
        dists = [abs(np.dot(p - fs[0], fs[1])) + 0.3 * np.linalg.norm((p - fs[0]) - np.dot(p - fs[0], fs[1]) * fs[1]) * 0 for fs in frames_s]
        k = int(np.argmin(dists))
        s = ss[k] + float(np.dot(p - frames_s[k][0], frames_s[k][1]))
        w = {n: 0.0 for n in names}

        def blend(a, b, s0, width):
            f = np.clip((s - (s0 - width)) / (2 * width), 0, 1)
            f = f * f * (3 - 2 * f)
            return 1 - f, f
        if s < L1:
            x0, x1 = blend("upperarm01", "upperarm02", u2, 0.04)
            w["upperarm01"], w["upperarm02"] = x0, x1
            e0, e1 = blend(None, None, L1, 0.035)
            w["upperarm01"] *= e0
            w["upperarm02"] *= e0
            w["lowerarm01"] = e1
        else:
            e0, e1 = blend(None, None, L1, 0.035)
            w["upperarm02"] = e0
            l0, l1 = blend(None, None, l2, 0.05)
            w["lowerarm01"] = e1 * l0
            w["lowerarm02"] = e1 * l1
            c0, c1 = blend(None, None, L1 + L2, 0.03)
            w["wrist"] = c1 * 0.5
            w["lowerarm02"] *= (1 - c1 * 0.5)
        tot = sum(w.values()) or 1.0
        for n, x in w.items():
            if x > 1e-3:
                vg[n].add([v.index], x / tot, "REPLACE")
    return ob


# ------------------------------------------------------------------ 리그
def build_armature(frames_by_side):
    arm = bpy.data.armatures.new("chr_jungwoo_arms_rig")
    ob = bpy.data.objects.new("chr_jungwoo_arms_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("arms_root")
    shL = frames_by_side["L"]["upperarm01"]["head"]
    root.head = Vector((0, shL.y, shL.z))
    root.tail = root.head + Vector((0, 0, 0.1))
    for side, frames in frames_by_side.items():
        eb = {}
        for b in ARM_BONES:
            f = frames[b]
            e = arm.edit_bones.new(f"{b}.{side}")
            e.head, e.tail = f["head"], f["tail"]
            e.align_roll(f["z"])
            eb[b] = e
        for b in ARM_BONES:
            p = frames[b]["parent"]
            eb[b].parent = eb.get(p, root)
            eb[b].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def mirror_frames(frames):
    out = {}
    M = Vector((-1, 1, 1))
    for b, f in frames.items():
        h = f["head"] * M
        t = f["tail"] * M
        z = f["z"] * M
        out[b] = {"head": Vector((-f["head"].x, f["head"].y, f["head"].z)),
                  "tail": Vector((-f["tail"].x, f["tail"].y, f["tail"].z)),
                  "z": Vector((-f["z"].x, f["z"].y, f["z"].z)), "parent": f["parent"]}
    return out


def mirror_object(ob, new_name):
    me = ob.data.copy()
    me.name = new_name
    bm = bmesh.new()
    bm.from_mesh(me)
    for v in bm.verts:
        v.co.x = -v.co.x
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    o2 = bpy.data.objects.new(new_name, me)
    bpy.context.scene.collection.objects.link(o2)
    # Blender 3+ 에서는 정점 그룹 이름이 메시에 저장되므로 복사된 메시가 .L 그룹과 웨이트를 그대로 가진다 → 이름만 .R로
    for g in o2.vertex_groups:
        if g.name.endswith(".L"):
            g.name = g.name[:-2] + ".R"
    return o2


def apply_pose(rig, pose, side):
    """hand_poses.json 포즈를 Blender 포즈 본에 적용 (굽힘 = 로컬 -X, 벌림 = 로컬 Z)."""
    for f, vals in pose.get("fingers", {}).items():
        for s, deg in enumerate(vals["curl"], 1):
            pb = rig.pose.bones.get(f"finger{f}-{s}.{side}")
            if pb is None:
                continue
            pb.rotation_mode = "XYZ"
            spread = vals.get("spread", 0.0) if s == 1 else 0.0
            twist = vals.get("twist", 0.0) if s == 1 else 0.0
            sgn = 1 if side == "L" else -1
            pb.rotation_euler = (math.radians(-deg), math.radians(twist) * sgn, math.radians(spread) * sgn)


# ------------------------------------------------------------------ 메인
def main():
    T.reset_scene()
    V, VT, F, sk, wt = load_mh()
    fL = bone_frames(V, sk, "L")
    fR = mirror_frames(fL)
    hand_len = (fL["wrist"]["head"] - fL["finger3-3"]["tail"]).length
    print(f"hand length {hand_len*100:.1f} cm, forearm {(fL['wrist']['head']-fL['lowerarm01']['head']).length*100:.1f} cm,"
          f" upper arm {(fL['lowerarm01']['head']-fL['upperarm01']['head']).length*100:.1f} cm")
    hand = build_hand_mesh(V, VT, F, wt, fL, "L")
    write_attributes(hand, fL, "L")
    if "--no-bake" not in ARGS or not (TEX / "chr_skin_orm.png").exists():
        bake_skin(hand, fL)
    else:
        me = hand.data
        if "bake" not in me.uv_layers:
            me.uv_layers.new(name="bake")
        me.uv_layers.active = me.uv_layers["bake"]
        bpy.context.view_layer.objects.active = hand
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")
    # 익스포트용 정리: 베이크 UV만 남기고 속성 제거
    me = hand.data
    for name in [u.name for u in me.uv_layers if u.name != "bake"]:
        me.uv_layers.remove(me.uv_layers[name])
    for name in ["tuv_nail", "tuv_joint", "tuv_region"]:
        a = me.color_attributes.get(name)
        if a:
            me.color_attributes.remove(a)
    skin = mat_from_images("chr_skin", "chr_skin", sss=0.25)
    me.materials.clear()
    me.materials.append(skin)
    knit = bpy.data.materials.new("chr_cardigan_knit")
    rib = bpy.data.materials.new("chr_cardigan_rib")
    for m_, pre in ((knit, "chr_knit"), (rib, "chr_rib")):
        nt, bsdf, _ = T._nodes(m_)
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.uv_map = "bake"
        for suf, sock, nc in (("albedo", "Base Color", False), ("orm", None, True), ("normal", None, True)):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(str(TEX / f"{pre}_{suf}.png"), check_existing=True)
            if nc:
                t.image.colorspace_settings.name = "Non-Color"
            nt.links.new(uv.outputs["UV"], t.inputs["Vector"])
            if suf == "albedo":
                nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
            elif suf == "orm":
                sp = nt.nodes.new("ShaderNodeSeparateColor")
                nt.links.new(t.outputs["Color"], sp.inputs["Color"])
                nt.links.new(sp.outputs["Green"], bsdf.inputs["Roughness"])
                nt.links.new(sp.outputs["Blue"], bsdf.inputs["Metallic"])
            else:
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nm.uv_map = "bake"
                nt.links.new(t.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Sheen Weight"].default_value = 0.6
        m_["tuv_tex"] = pre
    sleeve = build_sleeve(V, F, wt, fL, "L")
    sleeve.data.materials.append(knit)
    sleeve.data.materials.append(rib)
    hand_r = mirror_object(hand, "chr_hand_R")
    sleeve_r = mirror_object(sleeve, "chr_sleeve_R")
    rig = build_armature({"L": fL, "R": fR})
    for o in (hand, sleeve, hand_r, sleeve_r):
        o.parent = rig
        mod = o.modifiers.new("rig", "ARMATURE")
        mod.object = rig
    # 포즈 라이브러리 → Blender 액션 (검토·외부 툴용, Godot는 같은 JSON을 직접 사용)
    poses = json.loads(POSES.read_text("utf-8"))["poses"]
    rig.animation_data_create()
    for pname, pose in poses.items():
        act = bpy.data.actions.new(f"pose_{pname}")
        act.use_fake_user = True
        rig.animation_data.action = act
        for pb in rig.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
        apply_pose(rig, pose, "L")
        apply_pose(rig, pose, "R")
        for pb in rig.pose.bones:
            if pb.name.startswith("finger"):
                pb.keyframe_insert("rotation_euler", frame=1)
        track = rig.animation_data.nla_tracks.new()
        track.name = act.name
        track.strips.new(act.name, 1, act)
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_euler = (0, 0, 0)
    # 통계
    tris = sum(len(p.vertices) - 2 for o in (hand, sleeve) for p in o.data.polygons) * 2
    print(f"arms: {tris} tris (both sides)")
    OUT_GLTF.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in (rig, hand, sleeve, hand_r, sleeve_r):
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=str(OUT_GLTF), export_format="GLTF_SEPARATE", use_selection=True,
                              export_keep_originals=True, export_yup=True, export_apply=False,
                              export_tangents=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_skins=True, export_def_bones=False, export_extras=True)
    # 뼈 프레임(Godot IK·포즈용)도 JSON으로
    rest = {side: {b: {"head": list(f["head"]), "tail": list(f["tail"]), "z": list(f["z"])} for b, f in fr.items()}
            for side, fr in (("L", fL), ("R", fR))}
    (ROOT / "game/data/characters/arms_rest_blender.json").write_text(json.dumps(rest, indent=1), "utf-8")
    OUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND))
    if "--render" in ARGS:
        review_renders(rig, poses)


def review_renders(rig, poses):
    RENDERS.mkdir(parents=True, exist_ok=True)
    T.setup_render(samples=96, res=(1280, 800), exposure=0.0)
    sc = bpy.context.scene
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.03, 0.035, 1)
    for loc, e in (((0.6, -0.9, 1.9), 220), ((-0.8, -0.4, 1.4), 70), ((0.0, 0.6, 1.6), 110)):
        ld = bpy.data.lights.new("l", "AREA")
        ld.energy = e
        ld.size = 0.6
        lo = bpy.data.objects.new("l", ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0.3, -0.25, 1.15)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(lo)
    wl = rig.data.bones["wrist.L"].head_local
    for shot, pname, tgt, eye in (("hand_back", "relaxed", wl + Vector((0.07, -0.05, -0.06)), Vector((0.32, -0.35, 1.05))),
                                  ("hand_palm", "relaxed", wl + Vector((0.07, -0.05, -0.06)), Vector((0.05, -0.05, 0.95))),
                                  ("grip", "grip_flashlight", wl + Vector((0.07, -0.05, -0.06)), Vector((0.32, -0.35, 1.05)))):
        act = bpy.data.actions.get(f"pose_{pname}")
        for tr in rig.animation_data.nla_tracks:
            tr.mute = tr.name != f"pose_{pname}"
        sc.frame_set(1)
        cam = T.camera(f"cam_{shot}", eye, tgt, lens=70)
        T.render(cam, str(RENDERS / f"arms_{shot}.png"))


if __name__ == "__main__":
    main()
