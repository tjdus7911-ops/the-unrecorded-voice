class_name ViewmodelArms
extends Node3D
## 1인칭 손·팔 (서정우). Blender 리그(chr_jungwoo_arms.gltf)를 카메라에 붙여 코드로 포즈를 만든다.
##
## - 팔: 해석적 2본 IK (어깨 → 팔꿈치 → 손목). 팔꿈치는 아래·바깥을 향하게(pole).
##   뼈 축 규약에 의존하지 않도록, 휴식 자세의 '방향 + 굽힘면'을 목표 방향으로 돌리는 회전으로 계산한다.
## - 손: 손 프레임(손가락 방향 F, 손등 N, 엄지 쪽 R)을 목표로 회전.
## - 손가락: data/characters/hand_poses.json 포즈를 부드럽게 보간 (굽힘 = 뼈 로컬 -X).
## - 왼손 = 손전등, 오른손 = 녹음기 (사용자 설정). 상호작용 시 해당 손이 도구를 내리고 대상에 손을 뻗는다.
## - 근접 클리핑 방지: 재질 z_clip_scale + 고정 FOV(fov_override) — 벽에 붙어도 손이 벽을 뚫고 사라지지 않는다.

signal contact(side: String, tag: String)       ## 손이 대상에 닿은 순간 (효과음·물체 애니메이션 동기화)

const SCENE := "res://assets/models/characters/chr_jungwoo_arms.gltf"
const POSES := "res://data/characters/hand_poses.json"
const VIEW_FOV := 62.0
const Z_CLIP := 0.45

## 손 상태
enum Mode { HIDDEN, IDLE_LOW, HOLD_FLASHLIGHT, HOLD_RECORDER, REACH, HOLD_OBJECT, CARRY, COVER_MOUTH }

var player: Node3D
var camera: Camera3D
var skel: Skeleton3D
var model: Node3D
var poses := {}
var sides := {}
var follow_stiffness := 16.0
var _t := 0.0
var _bob_phase := 0.0
var _lag_basis := Basis()
var tremble := 0.0          ## 공포 떨림 0~1
var exhaustion := 0.0       ## 달린 뒤 0~1
var enabled := true
## 외부 카메라 검토용: 1인칭 재질 보정(z_clip_scale·fov_override)을 끈다
static var plain_materials := false

class Hand:
	var name := "L"
	var sign := 1.0          ## 화면 기준 바깥쪽 방향 (L = -1, R = +1)
	var ids := {}
	var fingers := []        ## [[f1-1, f1-2, f1-3], ...]
	var a := 0.0             ## 위팔 길이
	var b := 0.0             ## 아래팔 길이
	var S0 := Vector3.ZERO   ## 휴식 어깨 위치 (스켈레톤 공간)
	var E0 := Vector3.ZERO
	var W0 := Vector3.ZERO
	var hinge0 := Vector3.ZERO
	var F0 := Vector3.ZERO   ## 휴식 손가락 방향
	var N0 := Vector3.ZERO   ## 휴식 손등 방향
	var R0 := Vector3.ZERO   ## 휴식 엄지 쪽
	var mode := 0
	var pos := Vector3.ZERO  ## 현재 손목 목표 (루트 공간, 보간됨)
	var F := Vector3.FORWARD
	var R := Vector3.RIGHT
	var want_pos := Vector3.ZERO
	var want_F := Vector3.FORWARD
	var want_R := Vector3.RIGHT
	var speed := 10.0
	var pose_now := {}       ## "f-s" → 각도(도)
	var pose_want := "relaxed"
	var held: Node3D = null
	var held_offset := Transform3D()   ## 손 프레임(R, N, F, 손목 원점) 기준 물체 변환
	var held_raw := false              ## true: 오프셋이 '보정된 손 프레임' 기준 (attach_at으로 계산)
	var hand_sign := 1.0               ## 손 프레임(R,N,F)의 행렬식 부호 (-1이면 R을 뒤집어 오른손 좌표계로)
	var hold := []                     ## 도구를 들고 있을 때의 기본 자세 [pos, F, R]
	var visible := false

func _ready() -> void:
	top_level = true
	var f := FileAccess.open(POSES, FileAccess.READ)
	if f:
		poses = JSON.parse_string(f.get_as_text()).get("poses", {})
	if not ResourceLoader.exists(SCENE):
		push_warning("ViewmodelArms: model missing — " + SCENE)
		enabled = false
		return
	model = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	model.rotation.y = PI              # 리그 정면(+Z) → 카메라 정면(-Z)
	skel = model.find_child("*", true, false) as Skeleton3D
	if skel == null:
		for c in model.find_children("*", "Skeleton3D", true, false):
			skel = c
			break
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = 2
		m.extra_cull_margin = 3.0          # 스키닝 자세가 휴식 자세 AABB를 벗어나도 컬링되지 않게
		for s in m.get_surface_override_material_count():
			var src := m.get_active_material(s)
			if src is BaseMaterial3D:
				var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				_viewmodel_material(mat)
				# 실제 화면 검토 후 보정: 피부는 조금 더 따뜻하고 덜 창백하게, 카디건은 더 짙은 회색으로
				var nm := String(src.resource_name)
				if "skin" in nm:
					mat.albedo_color = Color(0.86, 0.78, 0.72)
				elif "cardigan" in nm or "knit" in nm or "rib" in nm:
					mat.albedo_color = Color(0.55, 0.55, 0.57)
					mat.roughness = 1.0
				m.set_surface_override_material(s, mat)
	for side in ["L", "R"]:
		sides[side] = _make_hand(side)
	# 어깨 중앙을 카메라 기준 아래·약간 뒤에
	var sh: Vector3 = ((sides["L"] as Hand).S0 + (sides["R"] as Hand).S0) * 0.5
	var sh_world := model.transform * sh
	model.position = Vector3(0, -0.27, 0.11) - (sh_world - model.position)
	for side in sides:
		var h: Hand = sides[side]
		h.pos = _low_pos(h)
		h.want_pos = h.pos
		set_mode(side, Mode.HIDDEN)
	_lag_basis = Basis()

## 1인칭 재질: 근접 클리핑 방지 + 고정 FOV
static func _viewmodel_material(mat: BaseMaterial3D) -> void:
	if plain_materials:
		return
	mat.use_z_clip_scale = true
	mat.z_clip_scale = Z_CLIP
	mat.use_fov_override = true
	mat.fov_override = VIEW_FOV

func apply_viewmodel_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = 2
		for s in m.get_surface_override_material_count():
			var src := m.get_active_material(s)
			if src is BaseMaterial3D and not (src as BaseMaterial3D).use_z_clip_scale:
				var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				_viewmodel_material(mat)
				m.set_surface_override_material(s, mat)
		if m.material_override is BaseMaterial3D:
			var mo := (m.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			_viewmodel_material(mo)
			m.material_override = mo

func _bone(n: String) -> int:
	return skel.find_bone(n)

func _make_hand(side: String) -> Hand:
	var h := Hand.new()
	h.name = side
	h.sign = -1.0 if side == "L" else 1.0
	for b in ["upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist"]:
		h.ids[b] = _bone("%s.%s" % [b, side])
	for f in range(1, 6):
		var row := []
		for s in range(1, 4):
			row.append(_bone("finger%d-%d.%s" % [f, s, side]))
		h.fingers.append(row)
	var g := func(n: String) -> Vector3: return skel.get_bone_global_rest(_bone("%s.%s" % [n, side])).origin
	h.S0 = g.call("upperarm01")
	h.E0 = g.call("lowerarm01")
	h.W0 = g.call("wrist")
	h.a = h.S0.distance_to(h.E0)
	h.b = h.E0.distance_to(h.W0)
	h.hinge0 = (h.E0 - h.S0).cross(h.W0 - h.E0).normalized()
	var mcp3: Vector3 = g.call("finger3-1")
	h.F0 = (mcp3 - h.W0).normalized()
	var tip: Vector3 = skel.get_bone_global_rest(h.fingers[2][2]).origin
	var ref := tip - (h.W0 + h.F0 * (tip - h.W0).dot(h.F0))
	h.N0 = -(ref - h.F0 * ref.dot(h.F0)).normalized()     # 휴식 자세에서 손가락이 살짝 굽은 반대쪽 = 손등
	var th: Vector3 = g.call("finger1-1")
	var rad := h.N0.cross(h.F0)
	h.R0 = rad if rad.dot(th - h.W0) > 0.0 else -rad
	for f in 5:
		for s in 3:
			h.pose_now["%d-%d" % [f + 1, s + 1]] = Vector3.ZERO     # (curl, spread, twist)
	h.hand_sign = signf(Basis(h.R0, h.N0, h.F0).determinant())
	return h

## ------------------------------------------------------------------ 외부 API
func set_mode(side: String, mode: int) -> void:
	var h: Hand = sides.get(side)
	if h == null:
		return
	h.mode = mode
	match mode:
		Mode.HIDDEN, Mode.IDLE_LOW:
			h.want_pos = _low_pos(h)
			h.want_F = Vector3(0, -1, -0.2).normalized()
			h.want_R = Vector3(0, 0, -1) if side == "L" else Vector3(0, 0, -1)
			h.pose_want = "relaxed"
			h.speed = 6.0
		Mode.HOLD_FLASHLIGHT:
			h.pose_want = "grip_flashlight"
			h.speed = 9.0
			if not h.hold.is_empty():
				aim(side, h.hold[0], h.hold[1], h.hold[2], 9.0)
		Mode.HOLD_RECORDER:
			h.pose_want = "grip_recorder"
			h.speed = 9.0
			if not h.hold.is_empty():
				aim(side, h.hold[0], h.hold[1], h.hold[2], 9.0)
		Mode.COVER_MOUTH:
			h.pose_want = "flat"
			h.speed = 7.0

func set_pose(side: String, pose: String) -> void:
	if sides.has(side):
		(sides[side] as Hand).pose_want = pose

func hand_mode(side: String) -> int:
	return (sides[side] as Hand).mode if sides.has(side) else Mode.HIDDEN

## 물체를 손에 쥔다. offset: 손 프레임(R=엄지 쪽, N=손등, F=손가락) 기준 위치·회전
func attach(side: String, obj: Node3D, offset: Transform3D) -> void:
	var h: Hand = sides[side]
	h.held = obj
	h.held_offset = offset
	if obj:
		apply_viewmodel_materials(obj)

func detach(side: String) -> Node3D:
	var h: Hand = sides[side]
	var o := h.held
	h.held = null
	return o

## 손을 루트(카메라) 공간의 목표로 — pos: 손목, fwd: 손가락 방향, thumb: 엄지 쪽 방향
func aim(side: String, pos: Vector3, fwd: Vector3, thumb: Vector3, speed := 10.0) -> void:
	var h: Hand = sides[side]
	h.want_pos = pos
	h.want_F = fwd.normalized()
	h.want_R = (thumb - h.want_F * thumb.dot(h.want_F)).normalized()
	h.speed = speed

## 월드 좌표 → 루트 공간
func to_root(p: Vector3) -> Vector3:
	return global_transform.affine_inverse() * p

func dir_to_root(d: Vector3) -> Vector3:
	return (global_transform.basis.inverse() * d).normalized()

## 손을 월드 지점으로 뻗었다가 돌아온다. at_contact: 닿는 순간 호출 (물체 애니메이션·소리)
## grip_world: 손바닥(손가락 뿌리 안쪽)이 닿을 월드 위치, fwd_world·thumb_world: 손 방향
func reach(side: String, grip_world: Vector3, fwd_world: Vector3, thumb_world: Vector3, pose := "grab_handle",
		at_contact := Callable(), hold := 0.25, follow := Callable()) -> void:
	var h: Hand = sides[side]
	var prev_mode := h.mode
	h.mode = Mode.REACH
	h.pose_want = "open"
	var f := dir_to_root(fwd_world)
	var r := dir_to_root(thumb_world)
	var palm_off := _palm_offset(h, f, r)
	var tw := create_tween()
	var start := h.pos
	# 1) 손을 편 채 목표 앞 6 cm까지
	tw.tween_method(func(k: float):
		var tgt := to_root(grip_world) - palm_off - f * 0.06
		aim(side, start.lerp(tgt, k), f, r, 40.0), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 2) 닿기 + 쥐기
	tw.tween_callback(func(): h.pose_want = pose)
	tw.tween_method(func(k: float):
		var tgt := to_root(grip_world) - palm_off - f * 0.06 * (1.0 - k)
		aim(side, tgt, f, r, 40.0), 0.0, 1.0, 0.12)
	tw.tween_callback(func(): contact.emit(side, pose))
	await tw.finished
	if at_contact.is_valid():
		at_contact.call()
	if h.mode != Mode.REACH:
		return          # 닿는 순간 다른 동작(조사·쥐기)이 손을 넘겨받음
	var tw2 := create_tween()
	# 3) 물체를 따라 움직이기 (문 손잡이·서랍) 또는 잠시 유지
	if follow.is_valid():
		tw2.tween_method(func(k: float):
			var gp: Vector3 = follow.call(k)
			aim(side, to_root(gp) - palm_off, f, r, 40.0), 0.0, 1.0, hold)
	else:
		tw2.tween_interval(hold)
	# 4) 놓고 돌아가기
	tw2.tween_callback(func():
		h.pose_want = "open"
		set_mode(side, prev_mode if prev_mode != Mode.REACH else Mode.IDLE_LOW))
	await tw2.finished

## 손목 → 손바닥 중심(물체가 닿는 곳) 벡터 (루트 공간, 주어진 손 방향 기준)
func _palm_offset(h: Hand, f: Vector3, r: Vector3) -> Vector3:
	var n := _dorsal_for(h, f, r)
	return f * 0.075 - n * 0.028

func _dorsal_for(h: Hand, f: Vector3, r: Vector3) -> Vector3:
	var s := signf(h.N0.dot(h.F0.cross(h.R0)))
	return (f.cross(r) * s).normalized()

func _low_pos(h: Hand) -> Vector3:
	return Vector3(0.24 * h.sign, -0.78, 0.02)

## 손 프레임 기준 오프셋으로 물체 변환을 계산할 때 쓰는 현재 손 프레임 (월드)
func hand_frame_world(side: String) -> Transform3D:
	var h: Hand = sides[side]
	var n := _dorsal_for(h, h.F, h.R)
	var b := Basis(h.R, n, h.F)
	return global_transform * Transform3D(b, h.pos)

## ------------------------------------------------------------------ 매 프레임
func follow_camera(delta: float) -> void:
	if camera == null:
		return
	# 관성: 시점을 빠르게 돌리면 손이 살짝 늦게 따라온다 (과하지 않게)
	var target_q := camera.global_transform.basis.get_rotation_quaternion()
	var w := clampf(delta * follow_stiffness, 0.0, 1.0)
	var q := global_transform.basis.get_rotation_quaternion().slerp(target_q, w)
	global_transform = Transform3D(Basis(q), camera.global_position)

func _process(delta: float) -> void:
	if not enabled or skel == null:
		return
	follow_camera(delta)
	_carry_update()
	_t += delta
	# 걷기·숨쉬기·떨림 (모든 손 공통 미세 움직임)
	var speed := 0.0
	if player and player is CharacterBody3D:
		speed = Vector2((player as CharacterBody3D).velocity.x, (player as CharacterBody3D).velocity.z).length()
	_bob_phase += delta * (1.8 + speed * 1.35)
	var walk := clampf(speed / 4.5, 0.0, 1.0)
	var shake := float(GameSettings.camera_shake)
	for side in sides:
		var h: Hand = sides[side]
		var k := clampf(delta * h.speed, 0.0, 1.0)
		h.pos = h.pos.lerp(h.want_pos, k)
		h.F = _nlerp(h.F, h.want_F, k)
		h.R = _nlerp(h.R, h.want_R, k)
		var off := Vector3.ZERO
		if h.mode != Mode.REACH:
			var ph := _bob_phase + (0.0 if side == "L" else PI)
			off.y += sin(ph * 2.0) * 0.010 * walk + sin(_t * 1.6) * 0.0025 * (1.0 + exhaustion * 2.5)
			off.x += cos(ph) * 0.008 * walk
			off.z += sin(_t * 1.6 + 0.5) * 0.0015 * (1.0 + exhaustion * 2.0)
			var tr := tremble * 0.0025 * shake
			off += Vector3(sin(_t * 31.0 + h.sign), sin(_t * 27.0), sin(_t * 23.0 + 2.0)) * tr
		_solve(h, h.pos + off, h.F, h.R)
		_fingers(h, delta)
		_place_held(h)

func _solve(h: Hand, wrist: Vector3, F: Vector3, R: Vector3) -> void:
	# 루트 공간 → 스켈레톤 공간
	var to_skel := (skel.global_transform.affine_inverse() * global_transform)
	var Wt := to_skel * wrist
	var Fs := (to_skel.basis * F).normalized()
	var Rs := (to_skel.basis * R).normalized()
	var S := h.S0
	var d := Wt - S
	var dist := clampf(d.length(), 0.08, h.a + h.b - 0.003)
	var dn := d.normalized()
	Wt = S + dn * dist
	# 팔꿈치: 아래·바깥·약간 뒤 (pole)
	var pole := (to_skel.basis * Vector3(0.55 * h.sign, -1.0, 0.25)).normalized()
	var cos_a := clampf((h.a * h.a + dist * dist - h.b * h.b) / (2.0 * h.a * dist), -1.0, 1.0)
	var along := h.a * cos_a
	var up := sqrt(maxf(h.a * h.a - along * along, 0.0))
	var pole_perp := (pole - dn * pole.dot(dn))
	if pole_perp.length() < 1e-4:
		pole_perp = dn.cross(Vector3.UP)
	pole_perp = pole_perp.normalized()
	var E := S + dn * along + pole_perp * up
	# 위팔
	var u0 := (h.E0 - h.S0).normalized()
	var l0 := (h.W0 - h.E0).normalized()
	var u1 := (E - S).normalized()
	var l1 := (Wt - E).normalized()
	var hinge1 := u1.cross(l1)
	if hinge1.length() < 1e-4:
		hinge1 = h.hinge0
	hinge1 = hinge1.normalized()
	if hinge1.dot(_rot_between(u0, u1) * h.hinge0) < 0.0:
		hinge1 = -hinge1
	var q_up := _frame_rot(u0, h.hinge0, u1, hinge1)
	var rest_up := skel.get_bone_global_rest(h.ids.upperarm01)
	skel.set_bone_pose(h.ids.upperarm02, skel.get_bone_rest(h.ids.upperarm02))
	skel.set_bone_global_pose(h.ids.upperarm01, Transform3D(q_up * rest_up.basis, S))
	var q_lo := _frame_rot(l0, h.hinge0, l1, hinge1)
	var rest_lo := skel.get_bone_global_rest(h.ids.lowerarm01)
	skel.set_bone_pose(h.ids.lowerarm02, skel.get_bone_rest(h.ids.lowerarm02))
	skel.set_bone_global_pose(h.ids.lowerarm01, Transform3D(q_lo * rest_lo.basis, E))
	# 손: 휴식 손 프레임 → 목표 손 프레임
	var s := signf(h.N0.dot(h.F0.cross(h.R0)))
	var N1 := (Fs.cross(Rs) * s).normalized()
	var R1 := N1.cross(Fs) * s
	var B0 := Basis(h.R0, h.N0, h.F0)
	var B1 := Basis(R1.normalized(), N1, Fs)
	var q_hand := B1 * B0.inverse()
	var rest_w := skel.get_bone_global_rest(h.ids.wrist)
	var hand_basis := q_hand.orthonormalized() * rest_w.basis
	skel.set_bone_global_pose(h.ids.wrist, Transform3D(hand_basis, Wt))

static func _nlerp(a: Vector3, b: Vector3, k: float) -> Vector3:
	var v := a.lerp(b, k)
	if v.length() < 1e-4:
		return b.normalized()
	return v.normalized()

static func _rot_between(a: Vector3, b: Vector3) -> Basis:
	var c := a.cross(b)
	if c.length() < 1e-6:
		return Basis()
	return Basis(c.normalized(), a.angle_to(b))

## 방향 d0 + 기준축 h0 프레임을 d1 + h1 프레임으로 돌리는 회전
static func _frame_rot(d0: Vector3, h0: Vector3, d1: Vector3, h1: Vector3) -> Basis:
	var x0 := (h0 - d0 * h0.dot(d0)).normalized()
	var x1 := (h1 - d1 * h1.dot(d1)).normalized()
	var A := Basis(x0, d0, x0.cross(d0))
	var B := Basis(x1, d1, x1.cross(d1))
	return B * A.inverse()

static func _twist_angle(q: Quaternion, axis: Vector3) -> float:
	var p := Vector3(q.x, q.y, q.z).project(axis)
	var tw := Quaternion(p.x, p.y, p.z, q.w)
	if tw.length() < 1e-6:
		return 0.0
	tw = tw.normalized()
	var ang := 2.0 * acos(clampf(tw.w, -1.0, 1.0))
	if Vector3(tw.x, tw.y, tw.z).dot(axis) < 0.0:
		ang = -ang
	return wrapf(ang, -PI, PI)

func _fingers(h: Hand, delta: float) -> void:
	var pose: Dictionary = poses.get(h.pose_want, poses.get("relaxed", {})).get("fingers", {})
	var k := clampf(delta * 14.0, 0.0, 1.0)
	var mirror := 1.0 if h.name == "L" else -1.0
	for f in 5:
		var spec: Dictionary = pose.get(str(f + 1), {})
		var curls: Array = spec.get("curl", [10, 12, 8])
		for s in 3:
			var key := "%d-%d" % [f + 1, s + 1]
			var want := Vector3(float(curls[s]), float(spec.get("spread", 0.0)) if s == 0 else 0.0,
					float(spec.get("twist", 0.0)) if s == 0 else 0.0)
			var now: Vector3 = h.pose_now[key]
			now = now.lerp(want, k)
			h.pose_now[key] = now
			var id: int = h.fingers[f][s]
			if id < 0:
				continue
			var rest_q := skel.get_bone_rest(id).basis.get_rotation_quaternion()
			var q := Quaternion(Vector3.RIGHT, deg_to_rad(-now.x)) * Quaternion(Vector3.UP, deg_to_rad(now.z) * mirror) \
					* Quaternion(Vector3.BACK, deg_to_rad(now.y) * mirror)
			skel.set_bone_pose_rotation(id, rest_q * q)

func _place_held(h: Hand) -> void:
	if h.held == null or not is_instance_valid(h.held):
		return
	var wt := skel.global_transform * skel.get_bone_global_pose(h.ids.wrist)
	# 손 프레임 = 손목 뼈 휴식 프레임을 따라 회전한 (R, N, F)
	var rest_w := skel.get_bone_global_rest(h.ids.wrist)
	var q := wt.basis.orthonormalized() * (skel.global_transform.basis.orthonormalized() * rest_w.basis).orthonormalized().inverse()
	var sb := skel.global_transform.basis.orthonormalized()
	var R := (q * (sb * h.R0)).normalized()
	var N := (q * (sb * h.N0)).normalized()
	var F := (q * (sb * h.F0)).normalized()
	var frame := Transform3D(Basis(R, N, F), wt.origin)
	var off := h.held_offset
	if h.held_raw:
		if frame.basis.determinant() < 0.0:
			frame.basis.x = -frame.basis.x
		h.held.global_transform = frame * off
		return
	if frame.basis.determinant() < 0.0:
		# 왼손 좌표계가 되는 쪽: 엄지 축을 뒤집고 오프셋도 같은 거울 변환 (물체가 뒤집혀 보이지 않게)
		frame.basis.x = -frame.basis.x
		var M := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
		off = Transform3D(M * off.basis * M, M * off.origin)
	h.held.global_transform = frame * off

## 손 프레임에서 원통(축 A = 0.8R + 0.6F 대각선)을 쥐는 손의 R·F를 계산 — 손전등처럼 손바닥을 비스듬히 가로지르는 파지
func grip_axes(side: String, axis: Vector3, dorsal: Vector3) -> Array:
	var h: Hand = sides[side]
	var A := axis.normalized()
	var N := (dorsal - A * dorsal.dot(A)).normalized()
	var P := N.cross(A)
	for sgn: float in [1.0, -1.0]:
		var R := (A * 0.8 + P * 0.6 * sgn).normalized()
		var F := (A * 0.6 - P * 0.8 * sgn).normalized()
		if _dorsal_for(h, F, R).dot(N) > 0.0:
			return [F, R]
	return [A, N.cross(A)]

## ------------------------------------------------------------------ 도구 · 물체 쥐기 프리셋
## 왼손 손전등: 원통 축이 손바닥을 대각선(0.8R + 0.6F)으로 가로지르고 스위치(+Y)가 손등 쪽
const FL_CENTER := Vector3(-0.165, -0.175, -0.47)
const REC_CENTER := Vector3(0.15, -0.195, -0.44)

func hold_flashlight(rig: Node3D) -> void:
	var beam := Vector3(0.10, 0.05, -1).normalized()
	var axes := grip_axes("L", beam, Vector3(-0.55, 0.83, 0.1))
	var F: Vector3 = axes[0]
	var R: Vector3 = axes[1]
	var N := _dorsal_for(sides["L"], F, R)
	var h: Hand = sides["L"]
	h.hold = [FL_CENTER - F * 0.065 + N * 0.042, F, R]
	var a_local := Vector3(0.8, 0.0, 0.6).normalized()
	var y_local := Vector3(0, 1, 0)
	var z_local := -a_local
	attach("L", rig, Transform3D(Basis(y_local.cross(z_local), y_local, z_local), Vector3(0, -0.042, 0.065)))
	set_mode("L", Mode.HOLD_FLASHLIGHT)

## 오른손 녹음기: 손바닥 위에 눕혀 들고 버튼 면이 플레이어 쪽, 엄지로 버튼을 누른다
func hold_recorder(rec: Node3D) -> void:
	var rN := Vector3(-0.1, -0.84, 0.53).normalized()
	var rF := Vector3(-0.35, 0.45, -0.82)
	rF = (rF - rN * rF.dot(rN)).normalized()
	var rR := -rN.cross(rF)
	if _dorsal_for(sides["R"], rF, rR).dot(rN) < 0:
		rR = -rR
	var h: Hand = sides["R"]
	h.hold = [REC_CENTER - rF * 0.07 + rN * 0.032, rF, rR]
	attach("R", rec, Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), Vector3(0, -0.049, 0.07)))
	set_mode("R", Mode.HOLD_RECORDER)

## 루트 공간 물체 변환 objT를 원하는 손 자세(wrist, F, R)로 쥐도록 오프셋 계산 (held_raw)
func attach_at(side: String, obj: Node3D, objT: Transform3D, wrist: Vector3, F: Vector3, R: Vector3) -> void:
	var h: Hand = sides[side]
	var N := _dorsal_for(h, F, R)
	var b := Basis(R * h.hand_sign, N, F)
	var frame := Transform3D(b, wrist)
	h.held = obj
	h.held_raw = true
	h.held_offset = frame.affine_inverse() * objT
	if obj:
		apply_viewmodel_materials(obj)

## 쥔 물체(held_raw)를 루트 공간 objT에 두도록 손을 움직인다
func hold_object_at(side: String, objT: Transform3D, speed := 14.0) -> void:
	var h: Hand = sides[side]
	var frame := objT * h.held_offset.affine_inverse()
	var R := frame.basis.x.normalized() * h.hand_sign
	aim(side, frame.origin, frame.basis.z.normalized(), R, speed)

## 오른손 엄지로 녹음기 버튼 누르기
func press_thumb(side := "R") -> void:
	var h: Hand = sides[side]
	var keep := h.pose_want
	h.pose_want = "press_recorder"
	await get_tree().create_timer(0.16).timeout
	h.pose_want = keep

## 도구를 든 손을 화면 밖으로 내렸다가(숨김) 돌려놓기
func lower_tool(side: String) -> void:
	var h: Hand = sides[side]
	aim(side, _low_pos(h), Vector3(0, -1, -0.3), Vector3(0, 0, -1), 9.0)
	await get_tree().create_timer(0.28).timeout
	if h.held:
		h.held.visible = false

func raise_tool(side: String) -> void:
	var h: Hand = sides[side]
	if h.held:
		h.held.visible = true
	set_mode(side, h.mode if h.mode != Mode.REACH else (Mode.HOLD_RECORDER if side == "R" else Mode.HOLD_FLASHLIGHT))

## ------------------------------------------------------------------ 두 손 운반 (택배 상자)
const CARRY_T := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8)), Vector3(0.0, -0.30, -0.46))
var carry_box: Node3D
var carry_T := Transform3D()
var carry_size := Vector3(0.4, 0.3, 0.3)
var _carry_saved := {}
var _carry_layers := {}
var _carry_follow := false

func carry_begin(box: Node3D, size: Vector3, dur := 0.7) -> void:
	carry_box = box
	carry_size = size
	box.top_level = true
	# 들고 있는 동안 상자의 충돌체를 끈다 (플레이어 캡슐과 겹쳐 플레이어를 밀어내던 문제)
	_carry_layers.clear()
	for c in box.find_children("*", "CollisionObject3D", true, false):
		if not (c is Interactable):
			_carry_layers[c] = (c as CollisionObject3D).collision_layer
			(c as CollisionObject3D).collision_layer = 0
	carry_T = global_transform.affine_inverse() * box.global_transform
	for side in sides:
		var h: Hand = sides[side]
		_carry_saved[side] = [h.mode, h.held]
		if h.held:
			h.held.visible = false
		h.held = null
		h.mode = Mode.CARRY
		h.pose_want = "flat"
	var from := carry_T
	var tw := create_tween()
	tw.tween_method(func(k: float):
		carry_T = from.interpolate_with(_carry_target(), k), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_carry_follow = true

## 운반 자세: 시점을 위아래로 돌려도 상자는 수평을 유지 (카메라 피치와 무관한 수직 자세)
func _carry_target() -> Transform3D:
	var yaw := global_transform.basis.get_euler().y
	var b := global_transform.basis.orthonormalized().inverse() * Basis(Vector3.UP, yaw) * CARRY_T.basis
	return Transform3D(b, CARRY_T.origin)

func carry_end(to_world: Transform3D, size: Vector3, dur := 0.7) -> void:
	_carry_follow = false
	var from := carry_T
	var tw := create_tween()
	tw.tween_method(func(k: float):
		carry_T = from.interpolate_with(global_transform.affine_inverse() * to_world, k), 0.0, 1.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	carry_box.global_transform = to_world
	for c in _carry_layers:
		if is_instance_valid(c):
			(c as CollisionObject3D).collision_layer = _carry_layers[c]
	carry_box = null
	for side in sides:
		var h: Hand = sides[side]
		var sv: Array = _carry_saved.get(side, [Mode.HIDDEN, null])
		h.held = sv[1]
		if h.held:
			h.held.visible = true
		set_mode(side, sv[0])

## 운반 중: 상자 양옆을 두 손바닥으로 받친다 (손가락은 아래·앞, 엄지는 위)
func _carry_update() -> void:
	if carry_box == null:
		return
	if _carry_follow:
		carry_T = carry_T.interpolate_with(_carry_target(), 0.25)
	carry_box.global_transform = global_transform * carry_T
	# 상자 원점이 바닥 중앙이라고 가정 (local_aabb 기준으로 중심 보정)
	var c := carry_T * Vector3(0, carry_size.y * 0.5, 0)
	var bx := carry_T.basis
	for side in sides:
		var h: Hand = sides[side]
		var out := bx.x * h.sign
		var contact := c + out * (carry_size.x * 0.5 + 0.012) + bx.z * (carry_size.z * 0.12) - bx.y * (carry_size.y * 0.08)
		var F := (bx.y * -0.35 + bx.z * -0.94).normalized()
		var thumb := bx.y
		if _dorsal_for(h, F, thumb).dot(out) < 0.0:
			thumb = -thumb
		var N := _dorsal_for(h, F, thumb)
		aim(side, contact - F * 0.075 + N * 0.028, F, thumb, 30.0)

## 물체(held_raw)를 objT에 둘 때의 손목 위치 (시작 프레임에서 손을 바로 그 자리에 두기 위함)
func hold_pos_for(objT: Transform3D, side: String) -> Vector3:
	var h: Hand = sides[side]
	return (objT * h.held_offset.affine_inverse()).origin
