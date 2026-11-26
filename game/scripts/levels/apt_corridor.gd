class_name AptCorridor
extends Node3D
## [PH_ 블록아웃] 1998년 아파트 복도 — EVENT 08 공간 전환 도착 지점 (PHASE 02 본 제작 전 임시 공간)
## 기존 PBR 텍스처만 사용한 단순 구조: 연녹색 하단 벽 + 미색 상단 벽, 인조석(테라조) 바닥, 형광등, 철문.
## 시대 착오 물건 없음 (디지털 도어락·CCTV·평면 TV 없음). 정식 모델링은 승인 후 Blender로 제작.

const ORIGIN := Vector3(0.0, 0.0, 60.0)    ## 작업실·복도와 겹치지 않는 위치
const LEN := 22.0
const W := 2.1
const H := 2.45
var spawn_yaw := PI                          ## 복도 끝(-Z 방향)을 바라봄
var soeun: Node3D
var _tubes: Array = []

func _ready() -> void:
	position = ORIGIN
	var floor_m := _pbr("stair_terrazzo", 1.2)
	var low_m := _pbr("steel_door_paint_green", 1.5, Color(0.62, 0.82, 0.66))
	var up_m := _pbr("wall_paint_ivory", 2.0)
	var ceil_m := _pbr("concrete_paint", 2.0)
	var door_m := _pbr("steel_door_paint", 1.0, Color(0.55, 0.5, 0.42))
	_box(Vector3(W, 0.1, LEN), Vector3(0, -0.05, -LEN / 2), floor_m, true)
	_box(Vector3(W, 0.1, LEN), Vector3(0, H + 0.05, -LEN / 2), ceil_m, true)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.1, 1.1, LEN), Vector3(sx * (W / 2 + 0.05), 0.55, -LEN / 2), low_m, true)
		_box(Vector3(0.1, H - 1.1, LEN), Vector3(sx * (W / 2 + 0.05), 1.1 + (H - 1.1) / 2, -LEN / 2), up_m, true)
		# 하단 벽 경계 몰딩
		_box(Vector3(0.02, 0.04, LEN), Vector3(sx * (W / 2 - 0.01), 1.1, -LEN / 2), _flat(Color(0.2, 0.28, 0.22), 0.5), false)
	_box(Vector3(W + 0.2, H, 0.1), Vector3(0, H / 2, 0.05), up_m, true)
	_box(Vector3(W + 0.2, H, 0.1), Vector3(0, H / 2, -LEN - 0.05), up_m, true)
	# 철문 (호수 표지)
	for i in 5:
		var z := -2.5 - i * 4.2
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.06, 2.0, 0.9), Vector3(sx * (W / 2 - 0.01), 1.0, z), door_m, false)
			var lbl := Label3D.new()
			lbl.text = "%d0%d" % [12, i * 2 + (1 if sx < 0 else 2)]
			lbl.font_size = 64
			lbl.pixel_size = 0.0012
			lbl.modulate = Color(0.12, 0.12, 0.12)
			lbl.outline_size = 0
			add_child(lbl)
			lbl.position = Vector3(sx * (W / 2 - 0.045), 1.82, z)
			lbl.rotation.y = PI / 2 * (-sx)
	# 형광등 (막대 + 실제 빛) — 끝 쪽 하나는 꺼져 있다
	for i in 5:
		var z := -2.0 - i * 4.6
		var tube := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.05, 0.03, 1.2)
		tube.mesh = tm
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.9, 0.95, 0.92)
		em.emission_enabled = i != 4
		em.emission = Color(0.85, 0.95, 0.9)
		em.emission_energy_multiplier = 3.0
		tube.material_override = em
		add_child(tube)
		tube.position = Vector3(0, H - 0.04, z)
		if i != 4:
			var l := OmniLight3D.new()
			l.light_color = Color(0.86, 0.96, 0.9)
			l.light_energy = 0.9 if i < 3 else 0.45
			l.omni_range = 4.2
			l.shadow_enabled = i < 2
			add_child(l)
			l.position = Vector3(0, H - 0.15, z)
			_tubes.append(l)
	# 복도 끝 창 너머 약한 빛 (소은 실루엣 역광)
	var back := OmniLight3D.new()
	back.light_color = Color(0.7, 0.78, 0.95)
	back.light_energy = 1.2
	back.omni_range = 3.0
	add_child(back)
	back.position = Vector3(0, 1.4, -LEN + 0.4)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sounds.pick("amb_fluorescent_hum")
	hum.bus = &"Ambience"
	hum.volume_db = -14.0
	hum.autoplay = true
	add_child(hum)
	hum.position = Vector3(0, H - 0.2, -4.0)
	_soeun()

func _soeun() -> void:
	var path := "res://assets/models/characters/PH_chr_soeun_silhouette.gltf"
	if ResourceLoader.exists(path):
		soeun = (load(path) as PackedScene).instantiate()
	else:
		soeun = MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.16
		cm.height = 1.25
		(soeun as MeshInstance3D).mesh = cm
		soeun.position.y = 0.62
	var holder := Node3D.new()
	holder.name = "SoeunSilhouette"
	add_child(holder)
	holder.add_child(soeun)
	holder.position = Vector3(0.15, 0, -LEN + 1.3)
	holder.rotation.y = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.025)
	dark.roughness = 1.0
	for mi in holder.find_children("*", "MeshInstance3D", true, false) + ([soeun] if soeun is MeshInstance3D else []):
		(mi as MeshInstance3D).material_override = dark
	holder.visible = false
	soeun = holder

## 복도 끝에 소은이가 잠시 나타났다 사라진다 (연출용 — 공격 없음)
func show_soeun(secs: float) -> void:
	soeun.visible = true
	await get_tree().create_timer(secs, false).timeout
	# 사라질 때 가장 가까운 형광등이 한 번 깜빡
	if _tubes.size() > 3:
		_tubes[3].visible = false
	soeun.visible = false
	await get_tree().create_timer(0.12, false).timeout
	if _tubes.size() > 3:
		_tubes[3].visible = true

func point(name: String) -> Vector3:
	match name:
		"apt_spawn":
			return to_global(Vector3(0, 0.05, -0.8))
		"apt_light":
			return to_global(Vector3(0, H - 0.1, -2.0))
	return global_position

func bounds() -> AABB:
	return AABB(ORIGIN + Vector3(-W / 2, -0.3, -LEN), Vector3(W, 0.6, LEN))

func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)
		sb.position = pos

func _flat(c: Color, r: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = r
	return m

func _pbr(name: String, tile: float, tint := Color(1, 1, 1)) -> BaseMaterial3D:
	var base := "res://assets/textures/pbr/%s_" % name
	var m := ORMMaterial3D.new()
	m.albedo_color = tint
	if ResourceLoader.exists(base + "albedo.jpg"):
		m.albedo_texture = load(base + "albedo.jpg")
	if ResourceLoader.exists(base + "orm.jpg"):
		m.orm_texture = load(base + "orm.jpg")
	if ResourceLoader.exists(base + "normal.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "normal.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	return m
