extends Node3D
## 현대 음성 복원 작업실 — PHASE 01 이동·충돌 테스트 레벨.
## 지오메트리: res://assets/models/environments/stu_studio.glb (tools/blender/build_studio.py)
## 조명은 Blender 검토 렌더와 같은 위치·색으로 Godot 쪽에서 재구성한다 (GLB에는 조명 미포함).
## 좌표 변환: Blender (x, y, z) → Godot (x, z, -y)

const PLAYER := preload("res://scenes/player/player.tscn")

@export var spawn_blender := Vector3(0.95, 0.75, 0.0)   ## 입구 안쪽
@export var spawn_yaw_deg := 0.0                        ## 0 = 북쪽(창문) 방향

var player: PlayerController
var hud: HUD
var ceiling_panels: Array[LightFixture] = []

static func b2g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

func _ready() -> void:
	_environment()
	_lights()
	player = PLAYER.instantiate()
	add_child(player)
	player.global_position = b2g(spawn_blender)
	player.set("_yaw", deg_to_rad(spawn_yaw_deg))
	hud = HUD.new()
	add_child(hud)
	hud.bind_player(player)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.44)
	env.ambient_light_energy = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssil_enabled = true
	env.sdfgi_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _spot(pos_b: Vector3, target_b: Vector3, color: Color, energy: float, angle: float, rng: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	add_child(l)
	l.global_position = b2g(pos_b)
	l.look_at(b2g(target_b), Vector3.UP)
	l.light_color = color
	l.light_energy = energy
	l.spot_angle = angle
	l.spot_range = rng
	l.shadow_enabled = true
	return l

func _lights() -> void:
	# 책상 스탠드 (2700K)
	var lamp := LightFixture.new()
	lamp.name = "Fixture_DeskLamp"
	add_child(lamp)
	var s := _spot(Vector3(1.98, 4.21, 1.23), Vector3(2.45, 4.35, 0.74), Color(1.0, 0.74, 0.46), 2.4, 55.0, 4.0)
	s.reparent(lamp)
	# 플로어 스탠드
	var fl := LightFixture.new()
	fl.name = "Fixture_FloorLamp"
	add_child(fl)
	var o := OmniLight3D.new()
	fl.add_child(o)
	o.global_position = b2g(Vector3(5.62, 0.62, 1.48))
	o.light_color = Color(1.0, 0.68, 0.38)
	o.light_energy = 1.6
	o.omni_range = 5.0
	o.shadow_enabled = true
	# 창밖 차가운 도시광
	var win := _spot(Vector3(3.0, 5.6, 1.7), Vector3(3.0, 2.0, 0.6), Color(0.58, 0.68, 0.86), 1.2, 70.0, 9.0)
	win.name = "WindowFill"
	# 천장 LED 패널 2개 — SCENE 02에서는 꺼짐 (STORY_OFF)
	for x in [2.1, 4.5]:
		var f := LightFixture.new()
		f.state = LightFixture.State.STORY_OFF
		add_child(f)
		f.global_position = b2g(Vector3(x, 2.7, 2.6))
		var a := OmniLight3D.new()
		a.light_color = Color(0.93, 0.96, 1.0)
		a.light_energy = 1.5
		a.omni_range = 5.0
		a.shadow_enabled = true
		f.add_child(a)
		ceiling_panels.append(f)
