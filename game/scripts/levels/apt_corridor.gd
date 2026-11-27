class_name AptCorridor
extends Node3D
## 1998년 복도식 아파트 (TAPE 01 「평범했던 하루」) — 요구사항 16 §6·REF 05
## 모델: tools/blender/build_apartment.py → assets/models/environments/apt_1998.gltf (Blender 좌표 → Godot (x, z, -y))
## 1층 외부 복도(남쪽 난간이 트임) · 동쪽 계단실(2층 참) · 현관 계단 · 놀이터(그네 2개). 시대 착오 물건 없음.
## 늦은 오후: 낮은 해 + 하늘빛, 복도등은 막 켜진 상태. 모델이 없으면(빌드 전) 단순 바닥만 만들어 진행이 막히지 않게 한다.

const ORIGIN := Vector3(0.0, 0.0, 60.0)    ## 작업실·복도와 겹치지 않는 위치
const MODEL := "res://assets/models/environments/apt_1998.gltf"
const SOEUN := "res://assets/models/characters/chr_soeun.gltf"
var spawn_yaw := -PI / 2                    ## 동쪽(+X)을 바라봄
var model: Node3D
var sun: DirectionalLight3D
var lamps: Array[OmniLight3D] = []
var lamp_mats: Array = []
var swings: Array[Node3D] = []
var soeun: Node3D
var soeun_poser: CharacterPoser
var _hum: AudioStreamPlayer3D
var _amb: AudioStreamPlayer
var _env_backup := {}

static func b(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

func _ready() -> void:
	position = ORIGIN
	if ResourceLoader.exists(MODEL):
		model = (load(MODEL) as PackedScene).instantiate()
		add_child(model)
		_colliders(model)
	else:
		push_warning("AptCorridor: %s 없음 — tools/blender/build_apartment.py 실행 필요" % MODEL)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(40, 0.2, 40)
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)
		sb.position = Vector3(12, -0.1, 0)
	for k in 2:
		var s := find_child("apt_swing_%d" % k, true, false) as Node3D
		if s:
			swings.append(s)
	_lights()
	_sounds()
	_soeun()
	visible = false

## glTF 임포트 힌트(-colonly)가 적용되지 않은 경우를 위한 보정: *_col-colonly 메시를 충돌체로
func _colliders(root: Node) -> void:
	for n in root.find_children("*col-colonly*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_convex_shape()
		sb.add_child(cs)
		mi.get_parent().add_child(sb)
		sb.transform = mi.transform
		mi.visible = false

func _lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "AptSun"
	sun.light_color = Color(1.0, 0.82, 0.62)            # 늦은 오후의 낮은 해
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-27, 38, 0)        # 남서쪽 낮은 해 → 건물 정면·복도 난간·놀이터에 빛
	sun.visible = false
	add_child(sun)
	# 복도등 (원형 유리 갓, 백열등 색) — 101~105호 앞 + 계단 참
	var xs := [2.1, 6.3, 10.5, 14.7, 18.9]
	for i in xs.size():
		_lamp(b(Vector3(xs[i], 0.85, 2.38)), 0.55, 4.0, i < 2)
	_lamp(b(Vector3(26.15, 5.05, 2.45)), 0.5, 4.5, false)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat and mat.resource_name.contains("apt_lamp_shade") and mat is BaseMaterial3D:
				lamp_mats.append(mat)

func _lamp(pos: Vector3, energy: float, rng: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.86, 0.66)
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	add_child(l)
	l.position = pos
	l.set_meta("base", energy)
	lamps.append(l)

func _sounds() -> void:
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sounds.pick("amb_fluorescent_hum")
	_hum.bus = &"Ambience"
	_hum.volume_db = -22.0
	add_child(_hum)
	_hum.position = b(Vector3(10.5, 0.85, 2.3))

func _soeun() -> void:
	if not ResourceLoader.exists(SOEUN):
		return
	soeun = (load(SOEUN) as PackedScene).instantiate() as Node3D
	add_child(soeun)
	soeun.visible = false
	var sk := soeun.find_children("*", "Skeleton3D", true, false)
	soeun_poser = CharacterPoser.new()
	soeun.add_child(soeun_poser)
	if not sk.is_empty():
		soeun_poser.setup(sk[0])
	for mi in soeun.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).extra_cull_margin = 2.0

## 들어올 때 / 나갈 때: 해·하늘·환경광을 이 공간에 맞게 바꾸고, 나갈 때 원래대로 되돌린다
func enter(env: Environment) -> void:
	visible = true
	sun.visible = true
	if env:
		for k in ["background_mode", "background_color", "ambient_light_source", "ambient_light_energy", "ambient_light_color",
				"sky", "tonemap_exposure", "sdfgi_energy", "fog_enabled"]:
			_env_backup[k] = env.get(k)
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.46, 0.56, 0.68)
		sm.sky_horizon_color = Color(0.86, 0.78, 0.66)
		sm.ground_horizon_color = Color(0.6, 0.55, 0.48)
		sm.ground_bottom_color = Color(0.25, 0.23, 0.2)
		sm.sun_angle_max = 20.0
		sky.sky_material = sm
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.42
		env.tonemap_exposure = 1.0
		env.sdfgi_energy = 1.0
	_hum.play()

func leave(env: Environment) -> void:
	visible = false
	sun.visible = false
	_hum.stop()
	if env:
		for k in _env_backup:
			env.set(k, _env_backup[k])

## 마커 (Blender empty) → 월드 좌표. 없으면 빌드 스크립트와 같은 값으로 계산
const MARKERS := {
	"apt_spawn": Vector3(3.0, 0.85, 0.0), "apt_frag_1": Vector3(12.6, -9.2, -0.4), "apt_frag_2": Vector3(26.15, 5.0, 1.42),
	"apt_frag_3": Vector3(14.0, 0.25, 1.12), "apt_soeun_end": Vector3(23.4, 0.95, 0.0), "apt_steps_up": Vector3(26.75, 2.2, 2.9),
	"apt_swing": Vector3(9.5, -9.5, 1.2), "apt_stair_base": Vector3(25.5, 1.4, 0.0), "apt_entrance": Vector3(25.1, -0.6, -0.3),
	"apt_corridor_mid": Vector3(12.0, 0.85, 1.2),
}
func point(name: String) -> Vector3:
	if name == "apt_light":
		return lamps[0].global_position if not lamps.is_empty() else global_position
	var n := find_child(name, true, false) as Node3D if model else null
	if n:
		return n.global_position
	if MARKERS.has(name):
		return to_global(b(MARKERS[name]))
	return global_position

## 아파트 전체(복도·계단·놀이터) 영역
func bounds() -> AABB:
	return AABB(ORIGIN + Vector3(-3, -1.0, -6), Vector3(34, 8, 26))

func corridor_bounds() -> AABB:
	return AABB(ORIGIN + Vector3(0, -0.2, -1.75), Vector3(24.2, 3.0, 1.75))

## 그네가 혼자 흔들린다 (TAPE 01 조각 1) — 진폭이 줄며 멈춘다
func swing_move(idx: int, secs: float, amp_deg := 24.0) -> void:
	if idx >= swings.size():
		return
	var s := swings[idx]
	var t := 0.0
	var base := s.rotation.x
	while t < secs:
		var k := 1.0 - t / secs
		s.rotation.x = base + deg_to_rad(amp_deg * k * sin(t * TAU / 2.1))
		await get_tree().process_frame
		t += get_process_delta_time()
	s.rotation.x = base

func lamps_power(k: float) -> void:
	for l in lamps:
		l.light_energy = float(l.get_meta("base")) * k
	for m in lamp_mats:
		(m as BaseMaterial3D).emission_energy_multiplier = 1.5 * k
