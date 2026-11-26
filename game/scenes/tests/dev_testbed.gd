extends Node3D
## PHASE 01 시스템 테스트베드 (그레이박스 — 아트 에셋 아님).
## 밝은 방(A) → 깜빡이는 복도 → 조명이 고장 난 어두운 방(B).
## 검증: 1인칭 이동·충돌, 손전등 획득·F 토글·그림자, 조명 상태, 어둠 속 단서 획득, 호흡·심장 박동.

const PLAYER := preload("res://scenes/player/player.tscn")
const H := 2.6   # 천장고

var player: PlayerController
var hud: HUD
var fixture_a: LightFixture
var fixture_corridor: LightFixture
var fixture_b: LightFixture
var switch_b: LightSwitch
var flashlight_pickup: PickupItem
var clue_cassette: PickupItem

func _ready() -> void:
	_build_environment()
	_build_shell()
	_build_lights()
	_build_props()
	player = PLAYER.instantiate()
	add_child(player)
	player.global_position = Vector3(-0.5, 0.05, 0.8)
	player.set("_yaw", -PI / 2.0)   # +X 방향(복도 쪽)을 바라봄
	hud = HUD.new()
	add_child(hud)
	hud.bind_player(player)

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.005, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.13, 0.15)
	env.ambient_light_energy = 0.05     # 거의 암흑 — 손전등 의존 확인용
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_shell() -> void:
	var csg := CSGCombiner3D.new()
	csg.name = "Shell"
	csg.use_collision = true
	add_child(csg)
	var wall := _mat(Color(0.62, 0.6, 0.55))
	var outer := CSGBox3D.new()
	outer.size = Vector3(13.6, H + 0.4, 4.4)
	outer.position = Vector3(4.0, H / 2.0, 0.0)
	outer.material = wall
	csg.add_child(outer)
	# 내부 공간 (subtract)
	for spec in [
		[Vector3(5.0, H, 4.0), Vector3(0.0, H / 2.0, 0.0)],       # Room A
		[Vector3(3.8, H, 1.5), Vector3(4.5, H / 2.0, 0.0)],       # Corridor
		[Vector3(4.0, H, 4.0), Vector3(8.5, H / 2.0, 0.0)],       # Room B
		[Vector3(0.4, 2.1, 0.9), Vector3(2.5, 1.05, 0.0)],        # Door A
		[Vector3(0.4, 2.1, 0.9), Vector3(6.5, 1.05, 0.0)],        # Door B
	]:
		var b := CSGBox3D.new()
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
		b.size = spec[0]
		b.position = spec[1]
		b.material = wall
		csg.add_child(b)
	# 벽 사이 칸막이 (복도 폭을 방보다 좁게)
	for x in [2.5, 6.5]:
		for z in [-1.4, 1.4]:
			var w := CSGBox3D.new()
			w.size = Vector3(0.2, H, 1.2)
			w.position = Vector3(x, H / 2.0, z)
			w.material = wall
			csg.add_child(w)
	# 바닥 재질 구분용
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(13.0, 4.0)
	floor_mesh.mesh = pm
	floor_mesh.position = Vector3(4.0, 0.002, 0.0)
	floor_mesh.material_override = _mat(Color(0.32, 0.3, 0.28), 0.7)
	add_child(floor_mesh)

func _fixture(pos: Vector3, energy: float, state: LightFixture.State, rng := 4.5) -> LightFixture:
	var f := LightFixture.new()
	f.state = state
	add_child(f)
	f.position = pos
	var l := OmniLight3D.new()
	l.light_color = Color(0.93, 0.97, 1.0)   # 형광등 색
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = true
	f.add_child(l)
	# 형광등 커버 (발광 메시)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.05, 0.15)
	mi.mesh = bm
	var m := _mat(Color(0.9, 0.9, 0.9))
	m.emission_enabled = true
	m.emission = Color(0.93, 0.97, 1.0)
	m.emission_energy_multiplier = 2.0
	bm.material = m
	mi.position = Vector3(0, 0.12, 0)
	f.add_child(mi)
	f.emissive_mesh = mi
	return f

func _build_lights() -> void:
	fixture_a = _fixture(Vector3(0, H - 0.2, 0), 1.2, LightFixture.State.NORMAL)
	fixture_corridor = _fixture(Vector3(4.5, H - 0.2, 0), 0.8, LightFixture.State.FLICKER, 2.6)
	fixture_b = _fixture(Vector3(8.5, H - 0.2, 0), 1.2, LightFixture.State.DEAD)
	fixture_a.name = "Fixture_A"
	fixture_corridor.name = "Fixture_Corridor"
	fixture_b.name = "Fixture_B"
	# 방 B 스위치 (눌러도 켜지지 않음)
	switch_b = LightSwitch.new()
	switch_b.name = "Switch_B"
	add_child(switch_b)
	switch_b.position = Vector3(6.54, 1.25, 0.75)
	_box_collider(switch_b, Vector3(0.08, 0.12, 0.04), Color(0.85, 0.83, 0.78))
	switch_b.fixtures = [switch_b.get_path_to(fixture_b)]

func _box_collider(body: Node3D, size: Vector3, color: Color) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size.max(Vector3(0.12, 0.08, 0.12))  # 너무 작은 물체도 조준 가능하게
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color, 0.5)
	mi.mesh = bm
	body.add_child(mi)

func _build_props() -> void:
	# 방 A 작은 테이블 위 손전등 (그레이박스 — 최종 모델: art/blender/props/prop_flashlight)
	var table := StaticBody3D.new()
	add_child(table)
	table.position = Vector3(-1.6, 0.37, -1.3)
	_box_collider(table, Vector3(0.9, 0.74, 0.6), Color(0.35, 0.24, 0.16))
	flashlight_pickup = PickupItem.new()
	flashlight_pickup.name = "FlashlightPickup"
	flashlight_pickup.item_id = &"flashlight"
	flashlight_pickup.prompt = "손전등 줍기"
	add_child(flashlight_pickup)
	flashlight_pickup.position = Vector3(-1.6, 0.78, -1.3)
	_box_collider(flashlight_pickup, Vector3(0.22, 0.045, 0.045), Color(0.05, 0.05, 0.05))

	# 방 B 바닥, 책상 아래쪽에 떨어진 카세트테이프 — 표시 아이콘·외곽선 없음
	clue_cassette = PickupItem.new()
	clue_cassette.name = "ClueCassette"
	clue_cassette.item_id = &"cassette_test"
	clue_cassette.prompt = "카세트테이프 줍기"
	add_child(clue_cassette)
	clue_cassette.position = Vector3(9.6, 0.01, 1.3)
	_box_collider(clue_cassette, Vector3(0.1, 0.012, 0.064), Color(0.85, 0.55, 0.15))
