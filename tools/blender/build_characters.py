"""캐릭터 전신 모델 + 리그 — 소은(9세, 1998) · 프롤로그 괴물. (사용자 검토용 1차 모델)

베이스: MakeHuman CC0 기본 메시·스켈레톤(163 뼈)·웨이트 (art/third_party/makehuman)
 1) 뼈 단위 '길이·굵기 배율'로 체형을 바꾼다 (선형 블렌드: 정점 = Σ w·A_b(v)) → 관절 위치도 같은 변환으로 이동
 2) 서브디비전 1단계 → 옷·머리카락은 몸 표면을 부위별로 복제해 법선 방향으로 띄운 셸(웨이트 공유 → 함께 움직임)
 3) 같은 뼈 구조의 아마추어로 스키닝 → glTF (+ 공유 텍스처)
소은: 검은 단발 · 노란 카디건 · 청 멜빵바지 · 흰 양말 · 빨간 운동화 (요구사항 02)
괴물: 사람과 비슷하지만 긴 팔·손가락·늘어난 목·마른 몸, 젖은 긴 머리카락이 얼굴을 가림(정체 비공개), 해진 작업복
출력: game/assets/models/characters/chr_soeun.gltf, gst_prologue_monster.gltf · art/blender/characters/*.blend
usage: python3 tools/blender/build_characters.py [soeun|monster]
"""
import json
import math
import os
import sys
from pathlib import Path

import bpy  # noqa: F401
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import tuv_lib as T  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MH = ROOT / "art/third_party/makehuman"
OUT = ROOT / "game/assets/models/characters"
TEX = ROOT / "game/assets/textures/chr"
BLEND = ROOT / "art/blender/characters"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
DM = 0.1        # MakeHuman dm → m (키는 마지막에 맞춤)


def conv(p):
    return np.array([p[0], -p[2], p[1]]) * DM


def load_mh():
    V, F, groups = [], [], {}
    g = None
    for ln in open(MH / "base.obj"):
        if ln.startswith("v "):
            V.append([float(x) for x in ln.split()[1:4]])
        elif ln.startswith("g "):
            g = ln.split()[1]
        elif ln.startswith("f "):
            idx = [int(t.split("/")[0]) - 1 for t in ln.split()[1:]]
            if g == "body":
                F.append(idx)
            groups.setdefault(g, set()).update(idx)
    V = np.array([conv(p) for p in V])
    sk = json.loads((MH / "default.mhskel").read_text())
    wt = json.loads((MH / "default_weights.mhw").read_text())["weights"]
    return V, F, groups, sk, wt


def skeleton(V, sk):
    J = lambda n: V[sk["joints"][n]].mean(0)
    bones = {}
    for name, b in sk["bones"].items():
        bones[name] = {"head": J(b["head"]), "tail": J(b["tail"]), "parent": b["parent"]}
    order = []
    def visit(n):
        if n in order:
            return
        p = bones[n]["parent"]
        if p:
            visit(p)
        order.append(n)
    for n in bones:
        visit(n)
    return bones, order


def morph(V, bones, order, W, names, spec):
    """spec: bone이름 접두사 → (길이 배율, 굵기 배율). 각 뼈 변환 A_b(p) = A_parent(head) + R S R^T (p - head)."""
    A = {}

    scales = {}

    def scale_for(n):
        best = None
        for k, v in spec.items():
            if n == k or n.startswith(k):
                best = v
        if best is None:
            # 지정 없는 뼈(얼굴 근육 oris·levator·oculi·eye 등)는 부모 배율을 물려받는다
            # → 머리만 키우고 얼굴 근육 뼈는 그대로 두어 코 밑·입술이 접히던(콧수염처럼 보이던) 문제 수정
            p = bones[n]["parent"]
            best = scales.get(p, (1.0, 1.0)) if p else (1.0, 1.0)
        scales[n] = best
        return best

    newb = {}
    for n in order:
        b = bones[n]
        h, t = b["head"], b["tail"]
        y = t - h
        L = np.linalg.norm(y)
        y = y / L if L > 1e-6 else np.array([0, 0, 1.0])
        tmp = np.array([1.0, 0, 0]) if abs(y[0]) < 0.9 else np.array([0, 1.0, 0])
        x = np.cross(y, tmp)
        x /= np.linalg.norm(x)
        z = np.cross(x, y)
        R = np.stack([x, y, z], 1)
        l, r = scale_for(n)
        M = R @ np.diag([r, l, r]) @ R.T
        p = b["parent"]
        h_new = A[p](h) if p else h
        A[n] = (lambda h=h, h_new=h_new, M=M: (lambda q: h_new + (np.asarray(q) - h) @ M.T))()
        newb[n] = {"head": h_new, "tail": A[n](t), "parent": p}
    out = np.zeros_like(V)
    tot = W.sum(1)
    for k, n in enumerate(names):
        w = W[:, k]
        m = w > 0
        if m.any():
            out[m] += w[m, None] * A[n](V[m])
    zero = tot < 1e-6
    out[~zero] /= tot[~zero, None]
    out[zero] = V[zero]
    return out, newb


def weight_matrix(nv, wt, names, groups=None):
    W = np.zeros((nv, len(names)))
    for k, n in enumerate(names):
        for i, x in wt.get(n, []):
            W[i, k] = x
    if groups:   # 눈 위치 보조 정점은 머리 뼈를 따르게
        hk = names.index("head")
        for g in ("joint-l-eye", "joint-r-eye", "helper-l-eye", "helper-r-eye"):
            for i in groups.get(g, []):
                if W[i].sum() < 1e-6:
                    W[i, hk] = 1.0
    return W


def mesh_from(name, V, faces, W, names, keep=None):
    keep_set = set(range(len(V))) if keep is None else keep
    faces = [f for f in faces if all(i in keep_set for i in f)]
    used = sorted({i for f in faces for i in f})
    remap = {v: k for k, v in enumerate(used)}
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new(V[i]) for i in used]
    for f in faces:
        try:
            bm.faces.new([vs[remap[i]] for i in f])
        except ValueError:
            pass
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    groups = {n: ob.vertex_groups.new(name=n) for n in names}
    for k, i in enumerate(used):
        for j in np.nonzero(W[i] > 1e-4)[0]:
            groups[names[j]].add([k], float(W[i, j]), "REPLACE")
    return ob


def subdivide(ob, levels=1):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="sub")


def vgroup_weights(ob, prefixes):
    """정점마다 해당 뼈(접두사 목록) 웨이트 합."""
    idx = {g.index for g in ob.vertex_groups if any(g.name.startswith(p) for p in prefixes)}
    w = np.zeros(len(ob.data.vertices))
    for v in ob.data.vertices:
        for g in v.groups:
            if g.group in idx:
                w[v.index] += g.weight
    return w


def shell(src, name, select_fn, offset, mat, solid=0.0, delete_fn=None):
    """src 메시에서 select_fn(정점 위치, 법선, 인덱스)->bool 인 면만 복제해 법선 방향으로 offset만큼 띄운 옷/머리 셸."""
    me = src.data.copy()
    me.name = name
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    keep = [select_fn(np.array(v.co), np.array(v.normal), v.index) for v in bm.verts]
    dead = [f for f in bm.faces if not all(keep[v.index] for v in f.verts)]
    if delete_fn:
        dead += [f for f in bm.faces if f not in dead and delete_fn(f)]
    bmesh.ops.delete(bm, geom=list(set(dead)), context="FACES")
    for v in bm.verts:
        o = offset(np.array(v.co), np.array(v.normal)) if callable(offset) else offset
        v.co += v.normal * o
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat)
    if solid > 0:
        s = ob.modifiers.new("solid", "SOLIDIFY")
        s.thickness = solid
        s.offset = 1.0
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.selected_objects:
            o.select_set(False)
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier="solid")
    return ob


def mat(name, color, rough=0.7, tex=None, sss=0.0, tint_tex=False):
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = T._nodes(m)
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if sss:
        bsdf.inputs["Subsurface Weight"].default_value = sss
    if tex:
        uv = nt.nodes.new("ShaderNodeUVMap")
        for suf, nc in (("albedo", False), ("normal", True)):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(str(TEX / f"{tex}_{suf}.png"), check_existing=True)
            if nc:
                t.image.colorspace_settings.name = "Non-Color"
            nt.links.new(uv.outputs["UV"], t.inputs["Vector"])
            if suf == "albedo" and tint_tex:
                continue                     # 색은 재질 색 그대로, 짜임은 노멀맵으로만
            if suf == "albedo":
                if tint_tex:
                    mx = nt.nodes.new("ShaderNodeMix")
                    mx.data_type = "RGBA"
                    mx.blend_type = "MULTIPLY"
                    mx.inputs["Factor"].default_value = 1.0
                    nt.links.new(t.outputs["Color"], mx.inputs[6])
                    mx.inputs[7].default_value = (*[min(1, c * 3.2) for c in color], 1)
                    nt.links.new(mx.outputs[2], bsdf.inputs["Base Color"])
                else:
                    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
            else:
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(t.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def box_uv(ob, scale=6.0):
    """셸 메시에 박스 투영 UV (니트·데님 반복 텍스처용)."""
    me = ob.data
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (co[a] * scale, co[b] * scale)


def armature(name, newb, order):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for n in order:
        b = newb[n]
        e = arm.edit_bones.new(n)
        e.head = Vector(b["head"])
        t = b["tail"]
        if np.linalg.norm(t - b["head"]) < 1e-4:
            t = b["head"] + np.array([0, 0, 0.01])
        e.tail = Vector(t)
        eb[n] = e
    for n in order:
        p = newb[n]["parent"]
        if p:
            eb[n].parent = eb[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def scale_all(V, newb, height):
    z0, z1 = V[:, 2].min(), V[:, 2].max()
    s = height / (z1 - z0)
    off = np.array([0, 0, -z0])
    V2 = (V + off) * s
    for b in newb.values():
        b["head"] = (b["head"] + off) * s
        b["tail"] = (b["tail"] + off) * s
    return V2


def eye(name, center, r, m, sclera=None, iris_cos=0.80):
    """안구: 흰자(sclera) + 앞쪽(-Y) 원형 홍채·동공(m). sclera가 없으면 단색."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=18, radius=r, location=Vector(center))
    o = bpy.context.active_object
    o.name = name
    for p in o.data.polygons:
        p.use_smooth = True
    if sclera is None:
        o.data.materials.append(m)
        return o
    o.data.materials.append(sclera)
    o.data.materials.append(m)
    for p in o.data.polygons:
        if -p.normal.y > iris_cos:
            p.material_index = 1
    return o


def finish(name, objs, rig, out_path):
    for o in objs:
        o.parent = rig
        md = o.modifiers.new("rig", "ARMATURE")
        md.object = rig
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs + [rig]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out_path), export_format="GLTF_SEPARATE", use_selection=True,
                              export_keep_originals=True, export_yup=True, export_apply=False, export_skins=True,
                              export_def_bones=False, export_animations=False, export_tangents=True)
    BLEND.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND / f"{name}.blend"))
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    print(f"{name}: {tris} tris, {len(rig.data.bones)} bones")


def eye_bind(ob, newb, bone="head"):
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")


# ---------------------------------------------------------------- 소은
def build_soeun():
    T.reset_scene()
    V, F, groups, sk, wt = load_mh()
    bones, order = skeleton(V, sk)
    names = order
    W = weight_matrix(len(V), wt, names, groups)
    spec = {
        "head": (1.30, 1.30), "neck": (0.85, 0.92),
        "spine": (0.92, 0.88), "pelvis": (0.9, 0.9), "breast": (0.6, 0.4), "clavicle": (0.82, 0.9), "shoulder": (0.85, 0.85),
        "upperarm": (0.86, 0.80), "lowerarm": (0.86, 0.80), "wrist": (0.85, 0.85), "finger": (0.85, 0.85), "metacarpal": (0.85, 0.85),
        "upperleg": (0.84, 0.82), "lowerleg": (0.84, 0.82), "foot": (0.85, 0.9), "toe": (0.85, 0.9),
    }
    V2, nb = morph(V, bones, order, W, names, spec)
    V2 = scale_all(V2, nb, 1.30)
    body = mesh_from("chr_soeun_body", V2, F, W, names)
    subdivide(body, 1)
    # 얼굴: 눈썹·입술 색 (정점 색 — 부드러운 마스크)
    skin = mat("chr_soeun_skin", (0.60, 0.43, 0.34), 0.55, sss=0.3)
    body.data.materials.append(skin)
    # 옷·머리 셸
    P = lambda o: np.array([v.co for v in o.data.vertices])
    w_torso = vgroup_weights(body, ["spine0", "clavicle", "shoulder", "breast", "neck01"])
    w_arm = vgroup_weights(body, ["upperarm", "lowerarm"])
    w_hand = vgroup_weights(body, ["wrist", "finger", "metacarpal"])
    w_hip = vgroup_weights(body, ["pelvis", "spine01", "spine02", "root"])
    w_leg = vgroup_weights(body, ["upperleg", "lowerleg"])
    w_foot = vgroup_weights(body, ["foot", "toe"])
    w_head = vgroup_weights(body, ["head", "neck03", "eye", "oris", "levator", "oculi", "orbicularis", "risorius", "jaw", "temporalis", "special"])
    Pb = P(body)
    # 손목 위·발목 위 위치
    wrist_z = {s: nb[f"wrist.{s}"]["head"] for s in "LR"}
    ankle_z = nb["foot.L"]["head"][2]
    knit = mat("chr_soeun_cardigan", (0.86, 0.66, 0.16), 0.9, tex="chr_knit", tint_tex=True)
    denim = mat("chr_soeun_overalls", (0.20, 0.30, 0.48), 0.85, tex="chr_rib", tint_tex=True)
    sock = mat("chr_soeun_socks", (0.88, 0.87, 0.84), 0.9)
    shoe = mat("chr_soeun_sneakers", (0.62, 0.06, 0.05), 0.55)
    hair_m = mat("chr_soeun_hair", (0.015, 0.012, 0.012), 0.42)
    eye_m = mat("chr_eye_dark", (0.035, 0.022, 0.015), 0.08)
    sclera_m = mat("chr_eye_sclera", (0.62, 0.58, 0.54), 0.15)
    cardigan = shell(body, "chr_soeun_cardigan", lambda c, n, i: (w_torso[i] + w_arm[i]) > 0.5 and c[2] > ankle_z + 0.62
                     and w_hand[i] < 0.2 and not (w_head[i] > 0.3), 0.009, knit)
    overalls = shell(body, "chr_soeun_overalls", lambda c, n, i: (w_hip[i] + w_leg[i]) > 0.45 and c[2] > ankle_z + 0.08
                     or (w_torso[i] > 0.6 and c[2] < ankle_z + 0.78 and abs(c[0]) < 0.085), 0.013, denim)
    socks = shell(body, "chr_soeun_socks", lambda c, n, i: c[2] < ankle_z + 0.11 and w_foot[i] + w_leg[i] > 0.5, 0.004, sock)
    shoes = shell(body, "chr_soeun_sneakers", lambda c, n, i: c[2] < ankle_z + 0.045 and w_foot[i] > 0.4, 0.012, shoe)
    # 단발머리: 정수리·뒤통수(귀 위) → 밖으로 1.6 cm, 아래로 퍼지게
    head_top = Pb[w_head > 0.6][:, 2].max()
    eyeL = V2[list(groups["joint-l-eye"])].mean(0) if "joint-l-eye" in groups else None
    eye_level = eyeL[2] if eyeL is not None else head_top - 0.1
    hc = nb["head"]["head"]
    def hair_sel(c, n, i):
        if w_head[i] < 0.5:
            return False
        face = n[1] < -0.35 and c[1] < hc[1]                  # 얼굴 쪽(-Y)을 향한 면
        if c[1] < hc[1] - 0.04 and c[2] < eye_level + 0.03:
            return False                                       # 얼굴 앞쪽(코 밑·입·턱 아랫면)은 법선과 무관하게 비움 — 콧수염처럼 보이던 문제
        if face and c[2] < eye_level + 0.03:
            return False                                       # 이마 아래 얼굴은 비움 (앞머리는 눈썹 위까지)
        if c[2] < eye_level - 0.075:
            return False                                       # 단발: 턱선 높이에서 끝
        return not (abs(c[0]) < 0.03 and c[2] < eye_level and n[1] < 0)
    hair = shell(body, "chr_soeun_hair", hair_sel, lambda c, n: 0.012 + 0.012 * max(0.0, (eye_level - c[2]) / 0.08), hair_m)
    # 앞머리 경계를 일직선으로 정리 — 삼각형 계단 모양(톱니) 제거
    bm = bmesh.new()
    bm.from_mesh(hair.data)
    for e in bm.edges:
        if e.is_boundary:
            for v in e.verts:
                if v.co.y < hc[1] - 0.02 and v.co.z > eye_level - 0.02:
                    v.co.z = eye_level + 0.028          # 앞머리: 눈썹 위 일자
    bm.to_mesh(hair.data)
    bm.free()
    objs = [body, cardigan, overalls, socks, shoes, hair]
    for o in (cardigan, overalls):
        box_uv(o, 8.0)
    # 눈 (검은 눈동자 — 작은 반사광은 게임 재질에서)
    eyes = []
    for s in ("l", "r"):
        g = groups.get(f"helper-{s}-eye") or groups.get(f"joint-{s}-eye")
        if g:
            # MakeHuman 눈 보조 메시(안구 자리)를 변형한 좌표로 안구 중심·반지름을 잡는다 (눈꺼풀 안쪽에 정확히 맞춤)
            P = V2[list(g)]
            c0 = P.mean(0)
            r0 = float(np.linalg.norm(P - c0, axis=1).max()) * 0.97 if len(P) > 8 else 0.0145
            e = eye(f"chr_soeun_eye_{s}", c0, r0, eye_m, sclera=sclera_m, iris_cos=0.62)
            eye_bind(e, nb)
            eyes.append(e)
    rig = armature("chr_soeun_rig", nb, order)
    finish("chr_soeun", objs + eyes, rig, OUT / "chr_soeun.gltf")


# ---------------------------------------------------------------- 괴물
def build_monster():
    T.reset_scene()
    V, F, groups, sk, wt = load_mh()
    bones, order = skeleton(V, sk)
    names = order
    W = weight_matrix(len(V), wt, names, groups)
    spec = {
        "neck": (1.9, 0.78), "head": (1.06, 0.95), "spine": (1.08, 0.80), "breast": (0.3, 0.3), "pelvis": (0.95, 0.8),
        "clavicle": (1.15, 0.8), "shoulder": (1.1, 0.78),
        "upperarm": (1.28, 0.66), "lowerarm": (1.42, 0.62), "wrist": (1.25, 0.8), "metacarpal": (1.35, 0.75), "finger": (1.75, 0.68),
        "upperleg": (1.12, 0.72), "lowerleg": (1.18, 0.66), "foot": (1.15, 0.8), "toe": (1.4, 0.8),
    }
    V2, nb = morph(V, bones, order, W, names, spec)
    V2 = scale_all(V2, nb, 2.18)
    body = mesh_from("gst_monster_body", V2, F, W, names)
    subdivide(body, 1)
    # 마르고 울퉁불퉁한 피부: 법선 방향 잡음 변위 (갈비·관절 돌출 느낌)
    rng = np.random.default_rng(7)
    me = body.data
    co = np.array([v.co for v in me.vertices])
    nrm = np.array([v.normal for v in me.vertices])
    def noise3(p, f):
        return (np.sin(p[:, 0] * f * 1.7 + 1.3) * np.sin(p[:, 1] * f * 2.3 + 0.7) * np.sin(p[:, 2] * f * 1.1 + 2.1))
    disp = 0.004 * noise3(co, 40) + 0.0025 * noise3(co, 110) - 0.006
    for v, d, n in zip(me.vertices, disp, nrm):
        v.co = Vector(np.array(v.co) + n * d)
    skin = mat("gst_monster_skin", (0.36, 0.34, 0.31), 0.45, sss=0.15)
    me.materials.append(skin)
    w_head = vgroup_weights(body, ["head", "neck03", "eye", "oris", "levator", "oculi", "orbicularis", "risorius", "jaw", "temporalis", "special"])
    w_torso = vgroup_weights(body, ["spine0", "clavicle", "shoulder", "breast", "neck01"])
    w_arm = vgroup_weights(body, ["upperarm"])
    w_hip = vgroup_weights(body, ["pelvis", "spine01", "spine02", "root"])
    w_leg = vgroup_weights(body, ["upperleg", "lowerleg"])
    P = np.array([v.co for v in body.data.vertices])
    ankle = nb["foot.L"]["head"][2]
    cloth = mat("gst_monster_cloth", (0.10, 0.11, 0.10), 0.95, tex="chr_knit", tint_tex=True)
    trousers = mat("gst_monster_trousers", (0.07, 0.07, 0.08), 0.92, tex="chr_rib", tint_tex=True)
    hair_m = mat("gst_monster_hair", (0.01, 0.01, 0.01), 0.3)
    # 해진 셔츠: 몸통·위팔, 무작위 구멍과 찢어진 밑단
    shirt = shell(body, "gst_monster_shirt", lambda c, n, i: (w_torso[i] + w_arm[i]) > 0.5 and c[2] > ankle + 1.0, 0.008, cloth,
                  delete_fn=lambda f: rng.random() < 0.008 or (f.calc_center_median()[2] < ankle + 1.12 and rng.random() < 0.5))
    pants = shell(body, "gst_monster_trousers", lambda c, n, i: (w_hip[i] + w_leg[i]) > 0.3 and c[2] > ankle + 0.2 and c[2] < ankle + 1.2, 0.012, trousers,
                  delete_fn=lambda f: f.calc_center_median()[2] < ankle + 0.32 and rng.random() < 0.45)
    # 얼굴을 가리는 젖은 긴 머리: 두피 셸 + 정수리·이마에서 늘어진 가닥 리본 90개 (머리 뼈를 따름)
    scalp = shell(body, "gst_monster_scalp", lambda c, n, i: w_head[i] > 0.6 and c[2] > nb["head"]["head"][2] + 0.06, 0.006, hair_m)
    hb = nb["head"]
    top = np.array(hb["tail"])
    center = (np.array(hb["head"]) + top) * 0.5
    bmh = bmesh.new()
    for k in range(170):
        ang = rng.normal(0.0, 0.9) if k < 110 else rng.uniform(-math.pi, math.pi)   # 대부분 얼굴 앞쪽
        front = math.cos(ang)                       # +면 얼굴 쪽(-Y)으로
        el = rng.uniform(0.25, 0.95)
        root = center + np.array([math.sin(ang) * 0.085 * (1 - 0.3 * el), -math.cos(ang) * 0.095 * (1 - 0.3 * el), 0.04 + 0.07 * el])
        length = rng.uniform(0.38, 0.72) * (1.0 if front > -0.2 else 0.8)
        width = rng.uniform(0.015, 0.035)
        seg = 8
        side = np.array([math.cos(ang), math.sin(ang), 0]) * width
        prev = None
        for j in range(seg + 1):
            tt = j / seg
            out_push = 0.012 + 0.018 * math.sin(min(1, tt * 2.5) * math.pi / 2)    # 얼굴에서 약간 떨어져 늘어짐
            pnt = root + np.array([math.sin(ang) * out_push, -math.cos(ang) * out_push, -length * tt]) \
                + np.array([rng.normal(0, 0.004), rng.normal(0, 0.004), 0])
            w = 1.0 - 0.6 * tt
            a1 = bmh.verts.new(pnt - side * w)
            a2 = bmh.verts.new(pnt + side * w)
            if prev:
                bmh.faces.new([prev[0], prev[1], a2, a1])
            prev = (a1, a2)
    strands_me = bpy.data.meshes.new("gst_monster_hair")
    bmh.to_mesh(strands_me)
    bmh.free()
    hair = bpy.data.objects.new("gst_monster_hair", strands_me)
    bpy.context.scene.collection.objects.link(hair)
    strands_me.materials.append(hair_m)
    for o in (hair, scalp):
        for g in list(o.vertex_groups):
            o.vertex_groups.remove(g)
        vg = o.vertex_groups.new(name="head")
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    for o in (shirt, pants):
        box_uv(o, 7.0)
    rig = armature("gst_monster_rig", nb, order)
    finish("gst_prologue_monster", [body, shirt, pants, scalp, hair], rig, OUT / "gst_prologue_monster.gltf")


# ---------------------------------------------------------------- 잡음의 실루엣 (요구사항 16 EVENT 09)
def build_noise():
    """사람보다 약간 큰(1.98 m) 검은 인간형. 얼굴은 어둠에 묻혀 식별되지 않고, 몸 곳곳에서 카세트 자기테이프 리본이
    늘어져 불규칙하게 흔들린다(흔들림은 Godot 셰이더 — UV.v = 리본 뿌리 0 → 끝 1)."""
    T.reset_scene()
    V, F, groups, sk, wt = load_mh()
    bones, order = skeleton(V, sk)
    names = order
    W = weight_matrix(len(V), wt, names, groups)
    spec = {
        "neck": (1.35, 0.8), "head": (1.0, 0.92), "spine": (1.05, 0.82), "breast": (0.3, 0.3), "pelvis": (0.95, 0.85),
        "clavicle": (1.08, 0.85), "shoulder": (1.05, 0.82), "upperarm": (1.12, 0.74), "lowerarm": (1.18, 0.7), "wrist": (1.1, 0.85),
        "metacarpal": (1.15, 0.8), "finger": (1.3, 0.75), "upperleg": (1.06, 0.78), "lowerleg": (1.08, 0.74), "foot": (1.05, 0.85), "toe": (1.1, 0.85),
    }
    V2, nb = morph(V, bones, order, W, names, spec)
    V2 = scale_all(V2, nb, 1.98)
    body = mesh_from("gst_noise_body", V2, F, W, names)
    subdivide(body, 1)
    rng = np.random.default_rng(16)
    me = body.data
    co = np.array([v.co for v in me.vertices])
    nrm = np.array([v.normal for v in me.vertices])
    # 표면을 감은 테이프처럼 결이 있는 울퉁불퉁함 (세로 결 + 잔물결)
    disp = 0.005 * np.sin(co[:, 2] * 95 + co[:, 0] * 30) * np.sin(co[:, 1] * 60 + 1.0) + 0.003 * np.sin(co[:, 0] * 210 + co[:, 2] * 160)
    for v, d, n in zip(me.vertices, disp, nrm):
        v.co = Vector(np.array(v.co) + n * d)
    skin = mat("gst_noise_body", (0.018, 0.014, 0.012), 0.42)
    me.materials.append(skin)
    tape_m = mat("gst_noise_tape", (0.06, 0.035, 0.02), 0.22)
    # 자기테이프 리본: 몸 위 무작위 지점(머리·어깨·팔·몸통에 집중)에서 아래로 늘어짐, 폭 6.3 mm 실제 테이프 비율보다 약간 넓게
    P = np.array([v.co for v in body.data.vertices])
    N = np.array([v.normal for v in body.data.vertices])
    gids = {g.index: g.name for g in body.vertex_groups}
    def main_bone(i):
        best, bw = "spine03", 0.0
        for ge in body.data.vertices[i].groups:
            if ge.weight > bw:
                bw, best = ge.weight, gids[ge.group]
        return best
    ztop = P[:, 2].max()
    cand = np.where(P[:, 2] > ztop * 0.45)[0]
    bm = bmesh.new()
    vg_of = []   # (vert index range, bone)
    count = 0
    for k in range(260):
        i = int(rng.choice(cand))
        root = P[i] + N[i] * 0.004
        bone = main_bone(i)
        length = rng.uniform(0.12, 0.55) * (1.3 if P[i][2] > ztop * 0.85 else 1.0)
        width = rng.uniform(0.006, 0.012)
        seg = 7
        side = np.cross(N[i], [0, 0, 1.0])
        if np.linalg.norm(side) < 1e-3:
            side = np.array([1.0, 0, 0])
        side = side / np.linalg.norm(side) * width
        prev = None
        start = count
        for j in range(seg + 1):
            tt = j / seg
            pnt = root + N[i] * (0.015 * tt) + np.array([rng.normal(0, 0.006), rng.normal(0, 0.006), -length * tt])
            a1 = bm.verts.new(pnt - side)
            a2 = bm.verts.new(pnt + side)
            count += 2
            if prev:
                bm.faces.new([prev[0], prev[1], a2, a1])
            prev = (a1, a2)
        vg_of.append((start, count, bone))
    me2 = bpy.data.meshes.new("gst_noise_tape")
    bm.to_mesh(me2)
    bm.free()
    tape = bpy.data.objects.new("gst_noise_tape", me2)
    bpy.context.scene.collection.objects.link(tape)
    me2.materials.append(tape_m)
    uv = me2.uv_layers.new(name="UVMap")
    # 리본별 UV: u = 좌우(0/1), v = 뿌리 0 → 끝 1
    for poly in me2.polygons:
        for li in poly.loop_indices:
            vi = me2.loops[li].vertex_index
            for (a, b, _bn) in vg_of:
                if a <= vi < b:
                    local = vi - a
                    uv.data[li].uv = (local % 2, (local // 2) / 7.0)
                    break
    groups_made = {}
    for (a, b, bn) in vg_of:
        g = groups_made.get(bn) or tape.vertex_groups.new(name=bn)
        groups_made[bn] = g
        g.add(list(range(a, b)), 1.0, "REPLACE")
    rig = armature("gst_noise_rig", nb, order)
    finish("gst_noise_silhouette", [body, tape], rig, OUT / "gst_noise_silhouette.gltf")


if __name__ == "__main__":
    what = ARGS[0] if ARGS else "all"
    if what in ("soeun", "all"):
        build_soeun()
    if what in ("monster", "all"):
        build_monster()
    if what in ("noise", "all"):
        build_noise()
