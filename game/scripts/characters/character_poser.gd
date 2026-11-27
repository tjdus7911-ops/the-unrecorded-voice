class_name CharacterPoser
extends Node
## 전신 캐릭터(MakeHuman 리그) 절차적 포즈·애니메이션 — 소은·괴물 공용.
## 뼈 회전은 '스켈레톤 공간 축 + 각도'로 지정한다 (뼈 로컬 축 규약에 의존하지 않음). 캐릭터 정면 = +Z.
## 모드: idle(숨쉬기) · head_down/head_up(고개 들기) · walk · run · grab · peek(옆에서 고개 내밀기)

var skel: Skeleton3D
var mode := "idle"
var t := 0.0
var head_raise := 0.0          ## 0 = 고개 숙임, 1 = 정면 (괴물 EVENT 09)
var hunch := 0.0               ## 괴물 굽은 자세 0~1
var speed := 1.0
var twitch := 0.0             ## 불규칙한 관절 경련 0~1 (요구사항 17 괴물) — 짧게 멈췄다 튀는 움직임
var _tw_hold := 0.0
var _tw_vals := {}
var _ids := {}
var _rest_local := {}
var _rest_global := {}

func setup(s: Skeleton3D) -> void:
	skel = s
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		_ids[n] = i
		_rest_local[n] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_rest_global[n] = skel.get_bone_global_rest(i).basis.get_rotation_quaternion()

func has(n: String) -> bool:
	return _ids.has(n)

func reset() -> void:
	for n in _ids:
		skel.set_bone_pose_rotation(_ids[n], _rest_local[n])

## 스켈레톤 공간 축 기준 회전을 뼈 로컬 회전으로 누적
func rot(n: String, axis: Vector3, deg: float) -> void:
	if not _ids.has(n) or absf(deg) < 0.001:
		return
	# 부모의 현재 전역 회전 P 기준: L' = P⁻¹ · Q(축, 각) · P · L  (축은 스켈레톤 공간 고정축)
	var id: int = _ids[n]
	var cur := skel.get_bone_pose_rotation(id)
	var par := skel.get_bone_parent(id)
	var P := Quaternion.IDENTITY
	if par >= 0:
		P = skel.get_bone_global_pose(par).basis.get_rotation_quaternion()
	var q := Quaternion(axis.normalized(), deg_to_rad(deg))
	skel.set_bone_pose_rotation(id, (P.inverse() * q * P * cur).normalized())

func _process(delta: float) -> void:
	if skel == null:
		return
	t += delta * speed
	reset()
	_arms_down()
	match mode:
		"idle":
			_breath(1.0)
		"walk":
			_breath(0.6)
			_gait(1.6, 22.0, 0.0)
		"run":
			_breath(0.4)
			_gait(3.2, 38.0, 1.0)
		"grab":
			_breath(0.5)
			for s in ["L", "R"]:
				var sg := 1.0 if s == "L" else -1.0
				rot("upperarm01." + s, Vector3.RIGHT, -70.0)
				rot("upperarm01." + s, Vector3.BACK, 12.0 * sg)
				rot("lowerarm01." + s, Vector3.RIGHT, -15.0)
		"peek":
			_breath(0.5)
			rot("spine03", Vector3.BACK, 14.0)
			rot("neck01", Vector3.BACK, 18.0)
			rot("head", Vector3.BACK, 10.0)
	# 괴물: 굽은 등·고개
	if hunch > 0.0:
		rot("spine02", Vector3.RIGHT, 14.0 * hunch)
		rot("spine04", Vector3.RIGHT, 18.0 * hunch)
		rot("neck01", Vector3.RIGHT, 20.0 * hunch)
	if twitch > 0.0:
		_twitch(delta)
	var down := 1.0 - head_raise
	if hunch > 0.0 or mode == "idle":
		rot("neck02", Vector3.RIGHT, 35.0 * down * hunch)
		rot("head", Vector3.RIGHT, 40.0 * down * hunch - 18.0 * head_raise * hunch)
		# 고개를 들 때 목이 꺾이며 비틀림 (기괴한 관절 움직임)
		rot("neck03", Vector3.BACK, sin(clampf(head_raise, 0, 1) * PI) * 22.0 * hunch)

func _arms_down() -> void:
	# MakeHuman 휴식 자세(A자) → 팔을 몸 옆으로
	for s in ["L", "R"]:
		var sg := 1.0 if s == "L" else -1.0
		rot("upperarm01." + s, Vector3.BACK, -38.0 * sg)
		rot("lowerarm01." + s, Vector3.RIGHT, -6.0)

func _breath(k: float) -> void:
	var b := sin(t * 1.4) * k
	rot("spine04", Vector3.RIGHT, b * 1.6)
	rot("clavicle.L", Vector3.BACK, b * 1.2)
	rot("clavicle.R", Vector3.BACK, -b * 1.2)
	rot("head", Vector3.RIGHT, -b * 0.8)

func _gait(freq: float, amp: float, lean: float) -> void:
	var p := t * freq * TAU / 2.0
	rot("upperleg01.L", Vector3.RIGHT, sin(p) * amp)
	rot("upperleg01.R", Vector3.RIGHT, -sin(p) * amp)
	rot("lowerleg01.L", Vector3.RIGHT, maxf(0.0, -cos(p)) * amp * 1.3)
	rot("lowerleg01.R", Vector3.RIGHT, maxf(0.0, cos(p)) * amp * 1.3)
	rot("upperarm01.L", Vector3.RIGHT, -sin(p) * amp * 0.7)
	rot("upperarm01.R", Vector3.RIGHT, sin(p) * amp * 0.7)
	rot("spine01", Vector3.RIGHT, 8.0 * lean)
	rot("spine03", Vector3.UP, sin(p) * 6.0)

## 경련: 일정 시간 같은 각도를 유지했다가 갑자기 다른 각도로 튄다 (부드러운 사인 흔들림이 아님 → 비정상적인 관절)
func _twitch(delta: float) -> void:
	_tw_hold -= delta
	if _tw_hold <= 0.0:
		_tw_hold = randf_range(0.12, 0.7)
		for b in ["neck02", "head", "clavicle.L", "clavicle.R", "lowerarm01.L", "lowerarm01.R", "spine05"]:
			_tw_vals[b] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	var amp := {"neck02": 22.0, "head": 28.0, "clavicle.L": 14.0, "clavicle.R": 14.0, "lowerarm01.L": 26.0, "lowerarm01.R": 26.0, "spine05": 8.0}
	for b in _tw_vals:
		if not has(b):
			continue
		var v: Vector3 = _tw_vals[b]
		rot(b, Vector3.RIGHT, v.x * amp[b] * twitch)
		rot(b, Vector3.BACK, v.y * amp[b] * 0.6 * twitch)
		rot(b, Vector3.UP, v.z * amp[b] * 0.5 * twitch)
