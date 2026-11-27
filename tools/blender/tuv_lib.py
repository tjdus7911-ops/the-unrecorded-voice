"""The Unrecorded Voice — Blender 공용 빌드 라이브러리 (Blender 5.3 / bpy)

모델링 헬퍼(베벨 박스·실린더·피벗 지정), 절차적 PBR 재질, 충돌체, 카메라·렌더, 익스포트.
모든 공간 빌드 스크립트(build_*.py)가 이 모듈을 사용한다.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

RNG = random.Random(2026)


# ---------------------------------------------------------------- scene
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    return sc


def collection(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    p = parent or bpy.context.scene.collection
    if c.name not in [x.name for x in p.children]:
        p.children.link(c)
    return c


def _link(obj, col):
    for c in obj.users_collection:
        c.objects.unlink(obj)
    (col or bpy.context.scene.collection).objects.link(obj)


# ---------------------------------------------------------------- mesh helpers
def fit_uvs(obj):
    """재질별 UV 처리: 타일 재질(tile_m)은 m 단위 UV를 타일 크기로 나누고, 이미지 재질(fit)은 면마다 0~1로 맞춘다."""
    me = obj.data
    if not me.uv_layers or not me.materials:
        return
    if "uv_m" not in me.uv_layers:          # 원본(m 단위) UV 보존 → 여러 번 호출해도 결과 동일
        src = me.uv_layers[0]
        keep = me.uv_layers.new(name="uv_m")
        for i, d in enumerate(src.data):
            keep.data[i].uv = d.uv
        me.uv_layers.active_index = 0
        me.uv_layers[0].active_render = True
    base = me.uv_layers["uv_m"].data
    uv = me.uv_layers[0].data
    for i, d in enumerate(base):
        uv[i].uv = d.uv
    for poly in me.polygons:
        if poly.material_index >= len(me.materials):
            continue
        m = me.materials[poly.material_index]
        if m is None:
            continue
        if "tile_m" in m:
            tx, ty = m["tile_m"][0], m["tile_m"][1]
            for li in poly.loop_indices:
                u, v = uv[li].uv
                uv[li].uv = (u / tx, v / ty)
        elif m.get("fit"):
            us = [uv[li].uv[0] for li in poly.loop_indices]
            vs = [uv[li].uv[1] for li in poly.loop_indices]
            u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
            for li in poly.loop_indices:
                u, v = uv[li].uv
                uv[li].uv = ((u - u0) / max(u1 - u0, 1e-6), (v - v0) / max(v1 - v0, 1e-6))


def _finish(obj, mat, bevel, segs, col, smooth=True, weighted=True):
    if mat is not None:
        if isinstance(mat, (list, tuple)):
            for m in mat:
                obj.data.materials.append(m)
        else:
            obj.data.materials.append(mat)
        fit_uvs(obj)
    if bevel and bevel > 0:
        b = obj.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = segs
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(35)
        b.harden_normals = False
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
        if weighted:
            w = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
            w.keep_sharp = True
    _link(obj, col)
    return obj


def box(name, dims, loc=(0, 0, 0), mat=None, bevel=0.004, segs=2, col=None, rot=(0, 0, 0),
        pivot=(0, 0, 0), parent=None):
    """dims = (x, y, z) 실제 크기(m). pivot = 박스 중심 기준 원점 위치 (-0.5~0.5 비율).
    예: pivot=(0,0,-0.5) → 원점이 바닥 중앙."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(dims), verts=bm.verts)
    off = Vector((-pivot[0] * dims[0], -pivot[1] * dims[1], -pivot[2] * dims[2]))
    bmesh.ops.translate(bm, vec=off, verts=bm.verts)
    _box_uv(bm)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    obj.rotation_euler = rot
    if parent:
        obj.parent = parent
    return _finish(obj, mat, bevel, segs, col)


def _box_uv(bm):
    """간단한 박스 투영 UV (1 UV unit = 1 m) — 타일 텍스처·베이크용."""
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            co = l.vert.co
            if ax == 0:
                l[uv].uv = (co.y, co.z)
            elif ax == 1:
                l[uv].uv = (co.x, co.z)
            else:
                l[uv].uv = (co.x, co.y)


def cyl(name, r, depth, loc=(0, 0, 0), mat=None, rot=(0, 0, 0), verts=32, bevel=0.002, segs=2,
        col=None, parent=None, r2=None, pivot_bottom=False, cap=True):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=verts,
                          radius1=r, radius2=r if r2 is None else r2, depth=depth)
    if pivot_bottom:
        bmesh.ops.translate(bm, vec=Vector((0, 0, depth / 2)), verts=bm.verts)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for l in f.loops:
            co = l.vert.co
            l[uv].uv = (math.atan2(co.y, co.x) / math.tau * 2 * math.pi * r, co.z)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    obj.rotation_euler = rot
    if parent:
        obj.parent = parent
    return _finish(obj, mat, bevel, segs, col)


def torus(name, R, r, loc=(0, 0, 0), mat=None, rot=(0, 0, 0), col=None, parent=None, arc=1.0,
          major_seg=48, minor_seg=12):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    n_major = max(4, int(major_seg * arc))
    for i in range(n_major + (0 if arc >= 1.0 else 1)):
        a = (i / major_seg) * math.tau
        ring = []
        for j in range(minor_seg):
            b = j / minor_seg * math.tau
            x = (R + r * math.cos(b)) * math.cos(a)
            y = (R + r * math.cos(b)) * math.sin(a)
            z = r * math.sin(b)
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)
    count = len(rings) if arc >= 1.0 else len(rings) - 1
    for i in range(count):
        r0, r1 = rings[i], rings[(i + 1) % len(rings)]
        for j in range(minor_seg):
            bm.faces.new((r0[j], r1[j], r1[(j + 1) % minor_seg], r0[(j + 1) % minor_seg]))
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    obj.rotation_euler = rot
    if parent:
        obj.parent = parent
    return _finish(obj, mat, 0, 0, col)


def empty(name, loc=(0, 0, 0), col=None, parent=None, rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.2
    e.location = loc
    e.rotation_euler = rot
    if parent:
        e.parent = parent
    _link(e, col)
    return e


def linked_copy(src, name, loc, rot=(0, 0, 0), col=None, parent=None, mat=None):
    o = src.copy()
    o.name = name
    o.location = loc
    o.rotation_euler = rot
    if parent:
        o.parent = parent
    if mat is not None:
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = mat
    _link(o, col)
    return o


def heightfield(name, w, h, nx, ny, fn, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, col=None, parent=None):
    """평면 격자에 높이 함수 fn(u,v)->z 적용 (흡음재 웨지 패턴 등)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            row.append(bm.verts.new(((u - 0.5) * w, (v - 0.5) * h, fn(u, v))))
        vs.append(row)
    uv = bm.loops.layers.uv.verify()
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
            for l in f.loops:
                l[uv].uv = (l.vert.co.x, l.vert.co.y)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    obj.rotation_euler = rot
    if parent:
        obj.parent = parent
    return _finish(obj, mat, 0, 0, col, smooth=False, weighted=False)


def solidify(obj, t):
    m = obj.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = t
    return obj


def collider(name, dims, loc, col, rot=(0, 0, 0), kind="colonly"):
    """Godot 임포트 힌트용 단순 충돌체 (-colonly / -convcolonly)."""
    o = box(f"{name}_col-{kind}", dims, loc, None, bevel=0, col=col, rot=rot)   # _col: 노드 이름 충돌 방지
    o.display_type = "WIRE"
    o.hide_render = True
    return o


# ---------------------------------------------------------------- materials
def _nodes(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return nt, bsdf, out


def _tex_coord(nt, kind="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    return tc.outputs[kind]


def _noise(nt, vec, scale, detail=6.0, rough=0.55):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    nt.links.new(vec, n.inputs["Vector"])
    return n


def _ramp(nt, fac, c0, c1, p0=0.3, p1=0.7):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = p0
    r.color_ramp.elements[0].color = (*c0, 1)
    r.color_ramp.elements[1].position = p1
    r.color_ramp.elements[1].color = (*c1, 1)
    nt.links.new(fac, r.inputs["Fac"])
    return r


def _bump(nt, height, strength, bsdf, distance=0.002):
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = distance
    nt.links.new(height, b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    return b


def mat_basic(name, color, rough=0.5, metal=0.0, noise=0.08, noise_scale=40.0, bump=0.05, spec=0.5):
    """색 편차(얼룩)·거칠기 편차·미세 범프가 있는 범용 PBR 재질 — 플라스틱처럼 매끈하지 않게."""
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    vec = _tex_coord(nt)
    n = _noise(nt, vec, noise_scale)
    dark = tuple(max(c * (1 - noise * 2.5), 0) for c in color)
    light = tuple(min(c * (1 + noise), 1) for c in color)
    r = _ramp(nt, n.outputs["Fac"], dark, light)
    nt.links.new(r.outputs["Color"], bsdf.inputs["Base Color"])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = max(rough - 0.12, 0.02)
    rr.inputs["To Max"].default_value = min(rough + 0.12, 1.0)
    nt.links.new(n.outputs["Fac"], rr.inputs["Value"])
    nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Specular IOR Level"].default_value = spec
    if bump:
        n2 = _noise(nt, vec, noise_scale * 8, 4, 0.6)
        _bump(nt, n2.outputs["Fac"], bump, bsdf)
    m.diffuse_color = (*color, 1)
    return m


def mat_wall_paint(name, color=(0.78, 0.76, 0.71), grime=0.35):
    """벽 페인트 — 롤러 질감, 바닥 근처·손 닿는 높이의 생활 오염."""
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    vec = _tex_coord(nt, "Object")
    n = _noise(nt, vec, 3.0, 8, 0.6)
    base = _ramp(nt, n.outputs["Fac"], tuple(c * 0.93 for c in color), color, 0.35, 0.65)
    # 높이에 따른 오염(바닥 쪽 어둡게)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vec, sep.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 0.35
    mr.inputs["To Min"].default_value = grime
    mr.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    n2 = _noise(nt, vec, 14.0, 6, 0.7)
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(mr.outputs["Result"], mul.inputs[0])
    nt.links.new(n2.outputs["Fac"], mul.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(mul.outputs[0], mix.inputs["Factor"])
    nt.links.new(base.outputs["Color"], mix.inputs[6])
    mix.inputs[7].default_value = (0.32, 0.29, 0.25, 1)
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.88
    n3 = _noise(nt, vec, 260.0, 3, 0.5)
    _bump(nt, n3.outputs["Fac"], 0.06, bsdf, 0.001)
    m.diffuse_color = (*color, 1)
    return m


def mat_wood_planks(name, c0=(0.30, 0.20, 0.12), c1=(0.46, 0.33, 0.21), plank=(1.2, 0.18)):
    """우드 패턴 데코타일(PVC 바닥재) — 판재 단위 색 편차 + 결."""
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    vec = _tex_coord(nt, "Object")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.37
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Brick Width"].default_value = plank[0]
    brick.inputs["Row Height"].default_value = plank[1]
    brick.inputs["Mortar Size"].default_value = 0.0015
    brick.inputs["Color1"].default_value = (*c0, 1)
    brick.inputs["Color2"].default_value = (*c1, 1)
    brick.inputs["Mortar"].default_value = (0.08, 0.06, 0.04, 1)
    brick.inputs["Bias"].default_value = 0.0
    nt.links.new(vec, brick.inputs["Vector"])
    # 결: 늘린 노이즈
    mapn = nt.nodes.new("ShaderNodeMapping")
    mapn.inputs["Scale"].default_value = (0.6, 14.0, 1.0)
    nt.links.new(vec, mapn.inputs["Vector"])
    grain = _noise(nt, mapn.outputs["Vector"], 6.0, 10, 0.65)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.45
    nt.links.new(brick.outputs["Color"], mix.inputs[6])
    nt.links.new(grain.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    # 사용 흔적: 거칠기 얼룩
    wear = _noise(nt, vec, 2.0, 5, 0.6)
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = 0.32
    rr.inputs["To Max"].default_value = 0.62
    nt.links.new(wear.outputs["Fac"], rr.inputs["Value"])
    nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(brick.outputs["Fac"], inv.inputs[1])
    _bump(nt, brick.outputs["Fac"], 0.25, bsdf, 0.001)
    m.diffuse_color = (*c1, 1)
    return m


def mat_ceiling_tile(name):
    """석고 흡음 텍스 600×600 — 미세 구멍 질감 + 그리드 바."""
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    vec = _tex_coord(nt, "Object")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Brick Width"].default_value = 0.6
    brick.inputs["Row Height"].default_value = 0.6
    brick.inputs["Mortar Size"].default_value = 0.012
    brick.inputs["Color1"].default_value = (0.80, 0.79, 0.76, 1)
    brick.inputs["Color2"].default_value = (0.76, 0.75, 0.71, 1)
    brick.inputs["Mortar"].default_value = (0.62, 0.62, 0.60, 1)
    nt.links.new(vec, brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    pores = nt.nodes.new("ShaderNodeTexVoronoi")
    pores.inputs["Scale"].default_value = 160.0
    nt.links.new(vec, pores.inputs["Vector"])
    _bump(nt, pores.outputs["Distance"], 0.25, bsdf, 0.0008)
    return m


def mat_fabric(name, color, rough=0.95, weave=420.0):
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    vec = _tex_coord(nt, "Object")
    n = _noise(nt, vec, 9.0, 6, 0.6)
    r = _ramp(nt, n.outputs["Fac"], tuple(c * 0.8 for c in color), color)
    nt.links.new(r.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Sheen Weight"].default_value = 0.6
    bsdf.inputs["Sheen Roughness"].default_value = 0.5
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = weave
    wave.inputs["Distortion"].default_value = 2.0
    nt.links.new(vec, wave.inputs["Vector"])
    _bump(nt, wave.outputs["Fac"], 0.12, bsdf, 0.0006)
    m.diffuse_color = (*color, 1)
    return m


_PBR_META = None
PBR_DIR = None


def mat_pbr(name, tex, tint=None, rough_mul=1.0, emission=None):
    """game/assets/textures/pbr/<tex>_{albedo,orm,normal}.jpg 기반 PBR 재질 (glTF로 그대로 내보내짐)."""
    import json
    global _PBR_META
    if _PBR_META is None:
        _PBR_META = json.loads((PBR_DIR / "materials.json").read_text("utf-8"))
    meta = _PBR_META[tex]
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    uvn = nt.nodes.new("ShaderNodeUVMap")

    def img(suffix, noncolor):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(str(PBR_DIR / f"{tex}_{suffix}.jpg"), check_existing=True)
        if noncolor:
            t.image.colorspace_settings.name = "Non-Color"
        t.interpolation = "Linear"
        nt.links.new(uvn.outputs["UV"], t.inputs["Vector"])
        return t
    a = img("albedo", False)
    if tint:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(a.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = (*tint, 1)
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
    o = img("orm", True)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(o.outputs["Color"], sep.inputs["Color"])
    if rough_mul != 1.0:
        mm = nt.nodes.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        mm.inputs[1].default_value = rough_mul
        nt.links.new(sep.outputs["Green"], mm.inputs[0])
        nt.links.new(mm.outputs[0], bsdf.inputs["Roughness"])
    else:
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    if meta.get("normal"):
        nimg = img("normal", True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 1.0
        nt.links.new(nimg.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if meta.get("sheen"):
        bsdf.inputs["Sheen Weight"].default_value = 0.5
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission[0], 1)
        bsdf.inputs["Emission Strength"].default_value = emission[1]
    m["tile_m"] = meta["tile_m"]
    m["tuv_tex"] = tex
    return m


def mat_decal(name, path, rough=0.9):
    """알파 데칼 (벽 오염·손때·얼룩) — glTF alphaMode BLEND."""
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(str(path), check_existing=True)
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = rough
    m.surface_render_method = "BLENDED"
    m["fit"] = True
    m["tuv_decal"] = True
    return m


def decal_plane(name, w, h, loc, rot, mat, col=None, parent=None):
    """얇은 평면 데칼 — 면에서 1.5 mm 띄움. 그림자 미생성."""
    import bmesh as _bm
    me = bpy.data.meshes.new(name)
    bm = _bm.new()
    vs = [bm.verts.new((x, y, 0)) for x, y in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]
    f = bm.faces.new(vs)
    uvl = bm.loops.layers.uv.verify()
    for l, uvv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        l[uvl].uv = uvv
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    o.location = loc
    o.rotation_euler = rot
    if parent:
        o.parent = parent
    me.materials.append(mat)
    o.visible_shadow = False
    o["tuv_decal"] = True
    _link(o, col)
    return o


def mat_emission(name, color, strength, base=(0.02, 0.02, 0.02)):
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    bsdf.inputs["Base Color"].default_value = (*base, 1)
    bsdf.inputs["Emission Color"].default_value = (*color, 1)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.3
    m.diffuse_color = (*color, 1)
    return m


def mat_image(name, path, emission=0.0, rough=0.5, alpha=False):
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    img = bpy.data.images.load(path, check_existing=True)
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    t.interpolation = "Cubic"
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    if emission:
        nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    bsdf.inputs["Roughness"].default_value = rough
    m["fit"] = True
    return m


def mat_glass(name, rough=0.04, rain=True):
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    bsdf.inputs["Base Color"].default_value = (0.9, 0.93, 0.95, 1)
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["IOR"].default_value = 1.45
    bsdf.inputs["Roughness"].default_value = rough
    if rain:
        vec = _tex_coord(nt, "Object")
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 55.0
        vor.feature = "SMOOTH_F1"
        nt.links.new(vec, vor.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.0
        mr.inputs["From Max"].default_value = 0.35
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        nt.links.new(vor.outputs["Distance"], mr.inputs["Value"])
        _bump(nt, mr.outputs["Result"], 0.5, bsdf, 0.002)
        # 빗물 줄기 — 세로로 늘린 노이즈로 거칠기 변화
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (40.0, 1.0, 2.0)
        nt.links.new(vec, mp.inputs["Vector"])
        st = _noise(nt, mp.outputs["Vector"], 4.0, 3, 0.5)
        rr = nt.nodes.new("ShaderNodeMapRange")
        rr.inputs["To Min"].default_value = 0.0
        rr.inputs["To Max"].default_value = 0.18
        nt.links.new(st.outputs["Fac"], rr.inputs["Value"])
        nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    return m


def mat_city_windows(name, seed=0):
    """원경 건물: 창문 그리드 일부만 켜짐 (차가운 백색 위주, 일부 따뜻한 색). 보라·네온 금지."""
    m = bpy.data.materials.new(name)
    nt, bsdf, _ = _nodes(m)
    vec = _tex_coord(nt, "Object")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Brick Width"].default_value = 1.6
    brick.inputs["Row Height"].default_value = 3.2
    brick.inputs["Mortar Size"].default_value = 0.6
    brick.inputs["Color1"].default_value = (1, 1, 1, 1)
    brick.inputs["Color2"].default_value = (1, 1, 1, 1)
    brick.inputs["Mortar"].default_value = (0, 0, 0, 1)
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Location"].default_value = (seed * 3.1, seed * 1.7, 0)
    nt.links.new(vec, mp.inputs["Vector"])
    # 객체 좌표의 XZ를 쓰기 위해 축 교체
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(mp.outputs["Vector"], sep.inputs["Vector"])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(sep.outputs["X"], add.inputs[0])
    nt.links.new(sep.outputs["Y"], add.inputs[1])
    nt.links.new(add.outputs[0], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    nt.links.new(comb.outputs["Vector"], brick.inputs["Vector"])
    cell = nt.nodes.new("ShaderNodeTexWhiteNoise")
    snap = nt.nodes.new("ShaderNodeVectorMath")
    snap.operation = "SNAP"
    snap.inputs[1].default_value = (1.6, 3.2, 1.0)
    nt.links.new(comb.outputs["Vector"], snap.inputs[0])
    nt.links.new(snap.outputs["Vector"], cell.inputs["Vector"])
    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = 0.72
    nt.links.new(cell.outputs["Value"], gt.inputs[0])
    mask = nt.nodes.new("ShaderNodeMath")
    mask.operation = "MULTIPLY"
    nt.links.new(gt.outputs[0], mask.inputs[0])
    nt.links.new(brick.outputs["Fac"], mask.inputs[1])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(brick.outputs["Fac"], inv.inputs[1])
    col = nt.nodes.new("ShaderNodeValToRGB")
    col.color_ramp.elements[0].position = 0.0
    col.color_ramp.elements[0].color = (0.75, 0.85, 1.0, 1)
    col.color_ramp.elements[1].position = 0.85
    col.color_ramp.elements[1].color = (0.8, 0.88, 1.0, 1)
    e = col.color_ramp.elements.new(0.9)
    e.color = (1.0, 0.72, 0.45, 1)
    col.color_ramp.interpolation = "CONSTANT"
    cell2 = nt.nodes.new("ShaderNodeTexWhiteNoise")
    sc = nt.nodes.new("ShaderNodeVectorMath")
    sc.operation = "SCALE"
    sc.inputs["Scale"].default_value = 1.37
    nt.links.new(snap.outputs["Vector"], sc.inputs[0])
    nt.links.new(sc.outputs["Vector"], cell2.inputs["Vector"])
    nt.links.new(cell2.outputs["Value"], col.inputs["Fac"])
    nt.links.new(col.outputs["Color"], bsdf.inputs["Emission Color"])
    em = nt.nodes.new("ShaderNodeMath")
    em.operation = "MULTIPLY"
    em.inputs[1].default_value = 2.2
    nt.links.new(mask.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], bsdf.inputs["Emission Strength"])
    bsdf.inputs["Base Color"].default_value = (0.035, 0.038, 0.045, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    return m


# ---------------------------------------------------------------- render
def setup_render(samples=64, res=(1600, 900), exposure=0.0):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 3
    sc.cycles.transmission_bounces = 6
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 1.0
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    sc.view_settings.exposure = exposure
    sc.render.image_settings.file_format = "PNG"


def camera(name, loc, look_at, lens=None, fov_v=None, col=None, ortho=None, clip_start=0.05):
    cam = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, cam)
    obj.location = loc
    d = Vector(look_at) - Vector(loc)
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.clip_start = clip_start
    cam.clip_end = 400
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    elif fov_v:
        cam.sensor_fit = "VERTICAL"
        cam.angle = math.radians(fov_v)
    elif lens:
        cam.lens = lens
    _link(obj, col)
    return obj


def render(cam, path, hide=()):
    sc = bpy.context.scene
    sc.camera = cam
    saved = []
    for o in hide:
        saved.append((o, o.hide_render))
        o.hide_render = True
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o, h in saved:
        o.hide_render = h


def strip_aux_uv():
    for me in bpy.data.meshes:
        if "uv_m" in me.uv_layers:
            me.uv_layers.remove(me.uv_layers["uv_m"])


def export_glb(path, collections):
    """지정 컬렉션만 GLB로. 재질은 기본값(색·거칠기·금속)만 넘어감 — 텍스처 베이크는 별도 단계."""
    vl = bpy.context.view_layer
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for c in collections:
        for o in c.all_objects:
            if o.type in {"MESH", "EMPTY"}:
                o.select_set(True)
    gltf_export(path)


# ---------------------------------------------------------------- lathe / misc
def lathe(name, profile, segs=48, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, col=None, parent=None,
          radial_fn=None, axis="Z", cap_ends=True, smooth=True):
    """회전체 — profile: [(r, z), ...] 아래→위. radial_fn(theta, z) -> 반지름 배율 (골·홈 표현).
    axis='Y' 이면 +Y 방향으로 세운다."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        ring = []
        for i in range(segs):
            th = i / segs * math.tau
            k = radial_fn(th, z) if radial_fn else 1.0
            x, y = math.cos(th) * r * k, math.sin(th) * r * k
            ring.append(bm.verts.new((x, z, y) if axis == "Y" else (x, y, z)))
        rings.append(ring)
    uv = bm.loops.layers.uv.verify()
    for j in range(len(rings) - 1):
        for i in range(segs):
            a, b = rings[j][i], rings[j][(i + 1) % segs]
            c, d = rings[j + 1][(i + 1) % segs], rings[j + 1][i]
            f = bm.faces.new((a, b, c, d) if axis == "Z" else (d, c, b, a))
            for l in f.loops:
                co = l.vert.co
                zz = co.y if axis == "Y" else co.z
                l[uv].uv = (math.atan2(co.y if axis == "Z" else co.z, co.x) * 0.03 + 0.1, zz)
    if cap_ends:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            if ring[0].co.length > 1e-6:
                try:
                    f = bm.faces.new(ring[::-1] if (flip ^ (axis == "Y")) else ring)
                except ValueError:
                    pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    obj.rotation_euler = rot
    if parent:
        obj.parent = parent
    return _finish(obj, mat, 0, 0, col, smooth=smooth)


def curve_tube(name, pts, radius, mat, col=None, parent=None, res=3):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(name, cu)
    if mat:
        cu.materials.append(mat)
    if parent:
        ob.parent = parent
    _link(ob, col)
    return ob


def wrinkle(obj, strength=0.006, scale=0.06, levels=2, seed=0):
    """천 주름: 서브디비전 + 클라우드 텍스처 변위 (소파·의자·담요)."""
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = sub.render_levels = levels
    tex = bpy.data.textures.new(f"{obj.name}_wrinkle", "CLOUDS")
    tex.noise_scale = scale
    tex.noise_depth = 2
    tex.noise_basis = "BLENDER_ORIGINAL"
    d = obj.modifiers.new("Wrinkle", "DISPLACE")
    d.texture = tex
    d.strength = strength
    d.mid_level = 0.5
    d.texture_coords = "OBJECT"
    tex2 = bpy.data.textures.new(f"{obj.name}_crease", "MARBLE")
    tex2.noise_scale = scale * 2.5
    tex2.marble_type = "SHARP"
    tex2.turbulence = 4.0 + seed
    d2 = obj.modifiers.new("Crease", "DISPLACE")
    d2.texture = tex2
    d2.strength = strength * 0.6
    d2.texture_coords = "OBJECT"
    return obj


def keep(obj, kind="interactive"):
    """GLB 최적화 시 병합하지 않고 독립 노드로 유지할 오브젝트 표시."""
    obj["tuv_keep"] = kind
    return obj


# ---------------------------------------------------------------- optimized export
def _kept_root(o):
    p = o
    while p is not None:
        if "tuv_keep" in p:
            return p
        p = p.parent
    return None


def flatten_basic_colors():
    """mat_basic(절차적 색 얼룩)은 glTF로 색이 내보내지지 않아 Godot에서 흰색이 된다 →
    내보내기 직전 Base Color 링크를 끊고 diffuse_color(설계 색)를 기본값으로 넣는다. (요구사항 16 아파트 QA에서 발견)"""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None or not bsdf.inputs["Base Color"].is_linked:
            continue
        src = bsdf.inputs["Base Color"].links[0].from_node
        if src.type == "VALTORGB":
            m.node_tree.links.remove(bsdf.inputs["Base Color"].links[0])
            bsdf.inputs["Base Color"].default_value = tuple(m.diffuse_color)


def export_optimized(path, collections, collider_col, prefix, exclude=(), flatten_basic=False):
    """정적 메시를 재질별로 병합(드로우콜 감소)하고, 상호작용 오브젝트(tuv_keep)는 계층·피벗을 유지해 따로 내보낸다.
    반환: (병합 메시 수, 유지 오브젝트 수, 원본 메시 수)"""
    dg = bpy.context.evaluated_depsgraph_get()
    tmp = collection(f"{prefix}__merge_tmp")
    kept, statics, n_src = set(), [], 0
    excl = {c.name for c in exclude}
    for c in collections:
        for o in c.all_objects:
            if o.type == "EMPTY" and ("spawn" in o.name or "tuv_keep" in o or "tuv_marker" in o):
                p = o
                while p is not None:
                    kept.add(p)
                    p = p.parent
                continue
            if o.type not in {"MESH", "CURVE"} or o.hide_render:
                continue
            if any(uc.name in excl for uc in o.users_collection):
                continue
            n_src += 1
            kr = _kept_root(o)
            if kr is not None:
                p = o
                while p is not None:
                    kept.add(p)
                    p = p.parent
                continue
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=False, depsgraph=dg)
            if len(me.polygons) == 0:
                continue
            no = bpy.data.objects.new(f"{o.name}__m", me)
            no.matrix_world = o.matrix_world.copy()
            tmp.objects.link(no)
            statics.append(no)
    merged = []
    if statics:
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for o in statics:
            o.select_set(True)
        bpy.context.view_layer.objects.active = statics[0]
        bpy.ops.object.join()
        big = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="MATERIAL")
        bpy.ops.object.mode_set(mode="OBJECT")
        for o in tmp.objects:
            mn = o.data.materials[0].name if o.data.materials else "nomat"
            used = {p.material_index for p in o.data.polygons}
            if len(used) == 1 and o.data.materials:
                mn = o.data.materials[list(used)[0]].name
            o.name = f"{prefix}_static_{mn}"
            o.data.name = o.name
            merged.append(o)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in merged:
        o.select_set(True)
    for o in kept:
        o.select_set(True)
    for o in collider_col.all_objects:
        o.select_set(True)
    strip_aux_uv()
    if flatten_basic:
        flatten_basic_colors()
    gltf_export(path)
    return len(merged), len([o for o in kept if o.type == "MESH"]), n_src


def gltf_export(path, selection=True):
    """.gltf(+.bin)로 내보내고 텍스처는 원본 파일(game/assets/textures/...)을 참조 — 중복 없이 공유, Godot이 VRAM 압축."""
    fmt = "GLTF_SEPARATE" if path.endswith(".gltf") else "GLB"
    kw = dict(filepath=path, export_format=fmt, use_selection=selection, export_apply=True, export_yup=True,
              export_lights=False, export_cameras=False, export_extras=True)
    if fmt == "GLTF_SEPARATE":
        kw["export_keep_originals"] = True
    bpy.ops.export_scene.gltf(**kw)


def blender_to_godot_xform(mw):
    """Blender 월드 행렬 → Godot Transform3D 성분 (basis 열 x,y,z + origin), glTF Y-up 변환 포함."""
    from mathutils import Matrix
    C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
    g = C @ mw @ C.inverted()
    cols = [[g[r][c] for r in range(3)] for c in range(3)]
    return {"x": cols[0], "y": cols[1], "z": cols[2], "o": [g[0][3], g[1][3], g[2][3]]}


def uv_rect(obj, u0, u1, v0, v1, axes=("x", "y")):
    """오브젝트 UV를 정점 좌표(axes)로 [u0,u1]x[v0,v1] 영역에 매핑 (라벨 일부만 쓰기)."""
    me = obj.data
    ai = {"x": 0, "y": 1, "z": 2}
    a, b = ai[axes[0]], ai[axes[1]]
    xs = [v.co[a] for v in me.vertices]
    ys = [v.co[b] for v in me.vertices]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    if "uv_m" in me.uv_layers:
        me.uv_layers.remove(me.uv_layers["uv_m"])
    uv = me.uv_layers[0].data
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (u0 + (co[a] - x0) / max(x1 - x0, 1e-9) * (u1 - u0), v0 + (co[b] - y0) / max(y1 - y0, 1e-9) * (v1 - v0))


def merge_rigid(collections, exclude_names=("_col-",)):
    """움직이는 부품(tuv_keep/tuv_anim/tuv_marker) 단위로 그 아래 정적 메시를 재질 조합별 1개로 병합.
    피벗·계층은 유지되고 메시 수만 줄어든다 (프롭 GLB 최적화). 반환: (병합 전, 병합 후) 메시 수."""
    dg = bpy.context.evaluated_depsgraph_get()

    def anchor(o):
        p = o.parent
        while p is not None:
            if "tuv_keep" in p or "tuv_anim" in p or "tuv_marker" in p:
                return p
            if p.parent is None:
                return p
            p = p.parent
        return None
    groups = {}
    objs = []
    for c in collections:
        for o in c.all_objects:
            if o.type not in {"MESH", "CURVE"} or any(e in o.name for e in exclude_names):
                continue
            if "tuv_keep" in o or "tuv_anim" in o:
                continue
            a = anchor(o)
            if a is None:
                continue
            key = (a.name, tuple(m.name for m in o.data.materials if m))
            groups.setdefault(key, []).append(o)
            objs.append(o)
    before = len(objs)
    after = 0
    for (aname, mats), members in groups.items():
        a = bpy.data.objects[aname]
        if len(members) == 1:
            after += 1
            continue
        bm = bmesh.new()
        inv = a.matrix_world.inverted()
        for o in members:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
            me.transform(inv @ o.matrix_world)
            if o.matrix_world.determinant() < 0:
                me.flip_normals()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        nm = bpy.data.meshes.new(f"{aname}_merged")
        bm.to_mesh(nm)
        bm.free()
        for mn in mats:
            nm.materials.append(bpy.data.materials[mn])
        no = bpy.data.objects.new(f"{aname}_mesh_{len(mats) and mats[0]}", nm)
        no.parent = a
        for c in members[0].users_collection:
            c.objects.link(no)
        for p_ in nm.polygons:
            p_.use_smooth = True
        for o in members:
            bpy.data.objects.remove(o, do_unlink=True)
        after += 1
    return before, after
