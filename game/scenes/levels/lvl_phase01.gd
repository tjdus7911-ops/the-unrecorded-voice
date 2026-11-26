extends Node3D
## PHASE 01 플레이 테스트 레벨 — 작업실(304호) + 외부 상가 복도 + 계단실 (로딩 없이 한 씬)
## 지오메트리: stu_studio.glb / cor_corridor.glb (같은 월드 좌표). 조명·사운드·상호작용은 여기서 구성한다.
## 좌표: Blender (x, y, z) → Godot (x, z, -y)

const PLAYER := preload("res://scenes/player/player.tscn")
const GLB_STUDIO := "res://assets/models/environments/stu_studio.gltf"
const GLB_CORRIDOR := "res://assets/models/environments/cor_corridor.gltf"
const PROPS := "res://assets/models/props/"
const RAIN_GLASS := preload("res://shaders/rain_glass.gdshader")
const CITY := preload("res://shaders/city_windows.gdshader")
const SPINE := preload("res://shaders/cassette_spine.gdshader")

@export var spawn_blender := Vector3(2.4, 2.0, 0.0)
@export var spawn_yaw := -0.24
@export var enable_thunder := true

var player: PlayerController
var hud: HUD
var stu: Node3D
var cor: Node3D
var env: Environment
var fx := {}                     ## 이름 → LightFixture
var door_hinge: Node3D
var door_body: AnimatableBody3D
var door_open := false
var door_busy := false
var window_light: SpotLight3D
var window_base_energy := 2.4
var recorder: Node3D
var recorder_state := "empty"    ## empty / loaded / playing
var recorder_tape: Node3D
var deck: Node3D
var deck_open := false
var parcel: Node3D
var parcel_open := false
var motor: AmbientEmitter
var hiss: AmbientEmitter
var clock_second: Node3D
var clock_minute: Node3D
var _tick := 0.0
var _tock := false
var _thunder_t := 20.0
var _ding_t := 75.0
var _reels: Array[Node3D] = []
var _vu: Array = []
var stats := {"interactions": 0}

static func b2g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

func _ready() -> void:
	_environment()
	stu = load(GLB_STUDIO).instantiate()
	stu.name = "Studio"
	add_child(stu)
	cor = load(GLB_CORRIDOR).instantiate()
	cor.name = "Corridor"
	add_child(cor)
	_fix_materials(self)
	_tag_surfaces()
	_cassette_multimesh()
	_lights()
	_reverb()
	_ambience()
	_rain()
	player = PLAYER.instantiate()
	add_child(player)
	player.global_position = b2g(spawn_blender) + Vector3(0, 0.05, 0)
	player.set("_yaw", spawn_yaw)
	player.footsteps.surface_zones.append({"aabb": AABB(Vector3(3.95, -0.2, -3.15), Vector3(1.7, 0.5, 2.3)), "surface": "rug"})
	hud = HUD.new()
	add_child(hud)
	hud.bind_player(player)
	_door()
	_switches_and_lamps()
	_furniture()
	_clock()
	_props()
	_locked_doors()
	if OS.get_cmdline_user_args().has("--benchmark"):
		enable_thunder = false
		var b := Benchmark.new()
		add_child(b)
		b.run(self)

# ======================================================================= 환경 · 재질
func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.017)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.40, 0.48)
	env.ambient_light_energy = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.sdfgi_enabled = true                  # 실시간 간접광 (벽·바닥에서 튀는 빛)
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.25
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.1
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.ssr_enabled = true                    # 젖은 유리·광택 바닥 반사
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_brightness = GameSettings.brightness
	env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	GameSettings.apply_quality(env, get_viewport())

func _fix_materials(root: Node) -> void:
	var cache := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var nm := m.resource_name
			var rep: Material = null
			if nm.contains("window_glass"):
				if not cache.has("rain"):
					var sm := ShaderMaterial.new()
					sm.shader = RAIN_GLASS
					cache["rain"] = sm
				rep = cache["rain"]
			elif nm.contains("city_bldg"):
				if not cache.has("city"):
					var cm := ShaderMaterial.new()
					cm.shader = CITY
					cache["city"] = cm
				rep = cache["city"]
			elif nm.contains("glass") or nm.contains("clear_plastic") or nm.contains("lens") or nm.contains("pet_bottle"):
				if not cache.has(nm):
					var g := (m as StandardMaterial3D).duplicate() as StandardMaterial3D if m is StandardMaterial3D else StandardMaterial3D.new()
					g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					g.albedo_color = Color(0.85, 0.9, 0.95, 0.16)
					g.roughness = 0.04
					g.metallic_specular = 0.8
					g.cull_mode = BaseMaterial3D.CULL_DISABLED
					cache[nm] = g
				rep = cache[nm]
			elif nm.contains("decal"):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if m is StandardMaterial3D:
					var d := (m as StandardMaterial3D)
					d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					d.render_priority = 1
			if rep:
				mi.set_surface_override_material(i, rep)
		# 작은 소품은 그림자 생략 (시각 차이 미미, 그림자 비용 절감)
		var aabb := mi.get_aabb()
		if aabb.size.length() < 0.12:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _tag_surfaces() -> void:
	for b in find_children("*", "StaticBody3D", true, false):
		var n := String(b.name)
		var s := ""
		if n.begins_with("stu_floor"):
			s = "wood"
		elif n.begins_with("cor_floor"):
			s = "tile"
		elif n.begins_with("cor_landing") or n.begins_with("cor_ramp"):
			s = "concrete"
		if s != "":
			b.set_meta("surface", s)

func _cassette_multimesh() -> void:
	var f := FileAccess.open("res://data/levels/stu_cassettes.json", FileAccess.READ)
	if f == null or not ResourceLoader.exists(PROPS + "prop_cassette_shelf.gltf"):
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var src := (load(PROPS + "prop_cassette_shelf.gltf") as PackedScene).instantiate()
	var case_mi := src.find_child("stu_cassette_case_src", true, false) as MeshInstance3D
	var spine_mi := src.find_child("stu_cassette_spine_src_0", true, false) as MeshInstance3D
	for pair in [[case_mi, data["cases"], false], [spine_mi, data["spines"], true]]:
		var mi: MeshInstance3D = pair[0]
		if mi == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = pair[2]
		mm.mesh = mi.mesh
		var arr: Array = pair[1]
		mm.instance_count = arr.size()
		for i in arr.size():
			var t: Dictionary = arr[i]
			var basis := Basis(Vector3(t["x"][0], t["x"][1], t["x"][2]), Vector3(t["y"][0], t["y"][1], t["y"][2]),
					Vector3(t["z"][0], t["z"][1], t["z"][2]))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(t["o"][0], t["o"][1], t["o"][2])))
			if pair[2]:
				mm.set_instance_custom_data(i, Color(float(t["atlas"]) / 8.0, 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cassettes_" + ("Spines" if pair[2] else "Cases")
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if pair[2]:
			var sm := ShaderMaterial.new()
			sm.shader = SPINE
			sm.set_shader_parameter("atlas", load("res://assets/textures/props/prop_cassette_spine_atlas.png"))
			mmi.material_override = sm
		add_child(mmi)
	src.queue_free()

# ======================================================================= 조명
func _fixture(fname: String, state: LightFixture.State, emissive: Array[String] = []) -> LightFixture:
	var f := LightFixture.new()
	f.name = fname
	f.state = state
	add_child(f)
	fx[fname] = f
	for e in emissive:
		var n := find_child(e, true, false)
		if n:
			f.emissive_nodes.append(n)
	return f

func _spot(parent: Node, pos_b: Vector3, target_b: Vector3, color: Color, energy: float, angle: float, rng: float,
		shadow := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	parent.add_child(l)
	l.global_position = b2g(pos_b)
	var to := b2g(target_b)
	if absf((to - l.global_position).normalized().dot(Vector3.UP)) > 0.99:
		l.look_at(to, Vector3.FORWARD)
	else:
		l.look_at(to, Vector3.UP)
	l.light_color = color
	l.light_energy = energy
	l.spot_angle = angle
	l.spot_angle_attenuation = 1.4
	l.spot_range = rng
	l.shadow_enabled = shadow
	l.shadow_blur = 1.5
	l.shadow_bias = 0.06
	l.shadow_normal_bias = 1.6
	return l

func _lights() -> void:
	# 작업실 — 책상 스탠드 (2700K)
	var lamp := _fixture("DeskLamp", LightFixture.State.NORMAL, ["stu_lamp_bulb"])
	_spot(lamp, Vector3(1.98, 4.22, 1.22), Vector3(2.5, 4.4, 0.74), Color(1.0, 0.74, 0.46), 2.6, 64.0, 5.0)
	var bounce := OmniLight3D.new()          # 갓 안쪽에서 새는 빛
	lamp.add_child(bounce)
	bounce.global_position = b2g(Vector3(1.98, 4.3, 1.3))
	bounce.light_color = Color(1.0, 0.72, 0.45)
	bounce.light_energy = 0.45
	bounce.omni_range = 3.2
	# 플로어 스탠드
	var fl := _fixture("FloorLamp", LightFixture.State.NORMAL)
	# 갓 아래로 떨어지는 빛(그림자) + 갓을 투과해 번지는 은은한 빛(그림자 없음) — 옴니 그림자 2패스보다 저렴
	_spot(fl, Vector3(5.62, 0.62, 1.38), Vector3(5.62, 0.62, 0.0), Color(1.0, 0.68, 0.38), 3.0, 70.0, 4.0)
	var o := OmniLight3D.new()
	fl.add_child(o)
	o.global_position = b2g(Vector3(5.62, 0.62, 1.68))
	o.light_color = Color(1.0, 0.7, 0.42)
	o.light_energy = 0.7
	o.omni_range = 4.5
	# 창밖 차가운 도시광 (블라인드 그림자가 방에 드리운다)
	window_light = _spot(self, Vector3(3.0, 5.9, 2.1), Vector3(3.0, 2.2, 0.4), Color(0.58, 0.68, 0.88), window_base_energy, 62.0, 9.0)
	window_light.name = "WindowFill"
	window_light.shadow_blur = 3.5               # 블라인드 살 그림자의 모아레 완화
	window_light.shadow_normal_bias = 2.0
	# 모니터 화면 빛
	var mon := OmniLight3D.new()
	add_child(mon)
	mon.global_position = b2g(Vector3(3.0, 4.45, 1.05))
	mon.light_color = Color(0.75, 0.8, 0.9)
	mon.light_energy = 0.35
	mon.omni_range = 1.8
	# 천장 LED 패널 2개 — 현관 옆 스위치로 켜고 끔 (SCENE 02: 꺼짐)
	var ceil := _fixture("StudioCeiling", LightFixture.State.NORMAL, ["stu_ceiling_panel_0_diffuser", "stu_ceiling_panel_1_diffuser"])
	ceil.switched_on = false
	ceil.emissive_color = Color(0.93, 0.96, 1.0)
	for x in [2.1, 4.5]:
		var s := _spot(ceil, Vector3(x, 2.7, 2.6), Vector3(x, 2.7, 0.0), Color(0.93, 0.96, 1.0), 3.2, 80.0, 4.5)
		s.distance_fade_enabled = false
	ceil._apply()
	# 복도 형광등 6개 (하나는 깜빡임) + 계단실 (하행 고장 / 상행 정상)
	for i in 6:
		var st := LightFixture.State.FLICKER if i == 4 else LightFixture.State.NORMAL
		var f := _fixture("CorLight%d" % i, st, ["cor_fluorescent_%d_tube_0" % i, "cor_fluorescent_%d_tube_1" % i])
		f.emissive_color = Color(0.92, 0.97, 1.0)
		var x: float = [-3.5, -0.5, 2.5, 5.5, 8.5, 11.5][i]
		var s := _spot(f, Vector3(x, -1.1, 2.4), Vector3(x, -1.1, 0.0), Color(0.9, 0.95, 1.0), 2.6, 84.0, 4.2)
		s.shadow_bias = 0.09                    # 벽면 줄무늬(섀도 애크니) 방지
		s.shadow_normal_bias = 2.2
		s.distance_fade_enabled = true          # 멀리 있는 등은 그림자부터 끈다
		s.distance_fade_begin = 12.0
		s.distance_fade_shadow = 7.0
		s.distance_fade_length = 4.0
		f._apply()
	var down := _fixture("StairDown", LightFixture.State.DEAD, ["cor_fluorescent_stair_down_tube_0", "cor_fluorescent_stair_down_tube_1"])
	_spot(down, Vector3(13.73, 2.9, 0.2), Vector3(13.73, 2.9, -1.7), Color(0.9, 0.95, 1.0), 2.0, 80.0, 4.0)
	down._apply()
	var up := _fixture("StairUp", LightFixture.State.NORMAL, ["cor_fluorescent_stair_up_tube_0", "cor_fluorescent_stair_up_tube_1"])
	up.emissive_color = Color(0.92, 0.97, 1.0)
	_spot(up, Vector3(14.95, 2.9, 3.35), Vector3(14.95, 2.9, 1.7), Color(0.9, 0.95, 1.0), 2.2, 80.0, 4.5)
	up._apply()
	# 비상구 유도등의 녹색 번짐
	var ex := OmniLight3D.new()
	add_child(ex)
	ex.global_position = b2g(Vector3(12.9, -1.1, 2.25))
	ex.light_color = Color(0.3, 1.0, 0.5)
	ex.light_energy = 0.25
	ex.omni_range = 2.2
	# 반사 프로브 (작업실·복도)
	for spec in [[Vector3(3.0, 2.5, 1.32), Vector3(6.0, 2.65, 5.0)], [Vector3(4.0, -1.1, 1.25), Vector3(18.0, 2.5, 1.8)]]:
		var rp := ReflectionProbe.new()
		add_child(rp)
		rp.global_position = b2g(spec[0])
		rp.size = Vector3(spec[1].x, spec[1].z, spec[1].y)
		rp.box_projection = true
		rp.interior = true
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED

# ======================================================================= 사운드
func _reverb() -> void:
	for spec in [["RoomStudio", 0.35, 0.55, 0.12], ["RoomCorridor", 0.62, 0.35, 0.22], ["RoomStair", 0.85, 0.25, 0.3]]:
		if AudioServer.get_bus_index(spec[0]) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, spec[0])
		AudioServer.set_bus_send(idx, &"Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = spec[1]
		rv.damping = spec[2]
		rv.wet = spec[3]
		rv.dry = 0.0
		rv.spread = 0.8
		AudioServer.add_bus_effect(idx, rv)
	for z in [["RoomStudio", Vector3(3.0, 2.5, 1.3), Vector3(6.0, 2.65, 5.0), 0.5],
			["RoomCorridor", Vector3(4.0, -1.1, 1.25), Vector3(18.0, 2.5, 1.8), 0.75],
			["RoomStair", Vector3(14.3, 1.6, 0.8), Vector3(2.6, 3.6, 6.0), 0.85]]:
		var a := Area3D.new()
		a.name = "Reverb_" + z[0]
		a.collision_layer = 0
		a.collision_mask = 0
		add_child(a)
		a.global_position = b2g(z[1])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(z[2].x, z[2].z, z[2].y)
		cs.shape = bs
		a.add_child(cs)
		a.reverb_bus_enabled = true
		a.reverb_bus_name = z[0]
		a.reverb_bus_amount = z[3]
		a.reverb_bus_uniformity = 0.4

func _emitter(id: String, pos_b: Vector3, vol: float, unit: float, bus := &"Ambience") -> AmbientEmitter:
	var e := AmbientEmitter.new()
	e.sound_id = id
	e.base_volume_db = vol
	e.unit_size = unit
	e.bus = bus
	e.max_db = 2.0
	add_child(e)
	e.global_position = b2g(pos_b)
	return e

func _ambience() -> void:
	_emitter("amb_rain_window", Vector3(2.2, 5.05, 1.5), -4.0, 3.0)
	_emitter("amb_rain_window", Vector3(3.9, 5.05, 1.5), -4.0, 3.0)
	_emitter("amb_rain_heavy", Vector3(3.0, 9.0, 2.0), -6.0, 6.0)
	var pc := find_child("stu_spawn_sound_pc_fan", true, false) as Node3D
	var e := _emitter("amb_pc_fan", Vector3(2.25, 4.5, 0.3), -15.0, 1.2)
	if pc:
		e.global_position = pc.global_position
	for i in 6:
		var x: float = [-3.5, -0.5, 2.5, 5.5, 8.5, 11.5][i]
		_emitter("amb_fluorescent_buzz" if i == 4 else "amb_fluorescent_hum", Vector3(x, -1.1, 2.42), -20.0 if i != 4 else -14.0, 1.4)
	_emitter("amb_fluorescent_hum", Vector3(14.95, 2.9, 3.4), -20.0, 1.4)
	_emitter("amb_rain_muffled", Vector3(15.4, 3.2, 1.2), -10.0, 3.0)
	_emitter("amb_rain_muffled", Vector3(-4.8, -1.1, 1.5), -14.0, 3.0)
	if fx.has("CorLight4"):
		fx["CorLight4"].flickered.connect(func(on): if on and randf() < 0.35:
			Sounds.play_at("sfx_flicker_zap", b2g(Vector3(8.5, -1.1, 2.4)), &"SFX", -12.0))

func _process(delta: float) -> void:
	# 벽시계 초침: 1초마다 한 칸 + 째깍 소리 (시계 위치에서)
	_tick += delta
	if _tick >= 1.0 and clock_second:
		_tick -= 1.0
		clock_second.rotate_object_local(Vector3.UP, -deg_to_rad(6.0))
		if clock_minute:
			clock_minute.rotate_object_local(Vector3.UP, -deg_to_rad(0.1))
		_tock = not _tock
		Sounds.play_at("sfx_clock_tick", clock_second.global_position, &"SFX", -15.0, null, 0.0, "", 1.0)
	# 천둥
	if enable_thunder:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(28.0, 60.0)
			_thunder()
	# 멀리서 들리는 엘리베이터
	_ding_t -= delta
	if _ding_t <= 0.0:
		_ding_t = randf_range(70.0, 140.0)
		Sounds.play_at("sfx_elevator_ding", b2g(Vector3(-4.9, -1.1, 1.3)), &"SFX", -16.0, null, 0.0, "멀리서 엘리베이터 소리", 2.0)
	# 재생 중 릴 회전 · VU 바늘
	if recorder_state == "playing":
		for r in _reels:
			if is_instance_valid(r):
				r.rotate_object_local(Vector3.UP, -delta * 3.2)
		for v in _vu:
			var n: Node3D = v[0]
			n.rotation.z = v[1] - deg_to_rad(randf_range(15.0, 55.0)) * 0.6
	_door_light_leak()

func _thunder() -> void:
	var reduce: bool = GameSettings.reduce_flashes
	var tw := create_tween()
	var peaks := [6.0, 0.6, 4.0, 0.8] if not reduce else [1.6, 1.0]
	for k in peaks.size():
		tw.tween_property(window_light, "light_energy", window_base_energy * peaks[k], 0.05 if not reduce else 0.4)
	tw.tween_property(window_light, "light_energy", window_base_energy, 0.6)
	var delay := randf_range(0.8, 2.6)
	get_tree().create_timer(delay).timeout.connect(func():
		var t := AmbientEmitter.new()
		t.stream = Sounds.pick("sfx_thunder")
		t.bus = &"Ambience"
		t.base_volume_db = -2.0
		t.unit_size = 40.0
		t.occluded_cutoff_hz = 400.0
		add_child(t)
		t.global_position = b2g(Vector3(3.0, 40.0, 15.0))
		t.finished.connect(t.queue_free)
		Sounds.caption.emit("천둥", "창밖"))

func _rain() -> void:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	add_child(p)
	p.global_position = b2g(Vector3(3.0, 9.5, 2.0))
	p.amount = 5000
	p.lifetime = 1.3
	p.preprocess = 2.0
	p.visibility_aabb = AABB(Vector3(-12, -12, -8), Vector3(24, 24, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 6.0, 4.2)
	pm.direction = Vector3(0.08, -1.0, 0.03)
	pm.spread = 3.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3(0, -6, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.42)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.7, 0.82, 0.22)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	p.draw_pass_1 = q

func _physics_process(_d: float) -> void:
	if door_body and door_hinge:
		door_body.global_transform = door_hinge.global_transform

func _door_light_leak() -> void:
	pass

# ======================================================================= 문 · 스위치 · 가구
func _door() -> void:
	door_hinge = find_child("stu_door", true, false) as Node3D
	if door_hinge == null:
		push_warning("stu_door not found")
		return
	# 문 충돌체: 경첩의 자식이 아니라 레벨에 두고 매 물리 프레임 경첩 변환을 따라가게 한다
	# (AnimatableBody3D는 '자기 자신'의 변환이 바뀔 때만 물리 서버에 반영되기 때문)
	door_body = AnimatableBody3D.new()
	var body := door_body
	body.name = "DoorBody"
	body.sync_to_physics = false
	add_child(body)
	body.global_transform = door_hinge.global_transform
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.89, 2.09, 0.05)
	cs.shape = bs
	cs.position = Vector3(0.445, 1.05, 0.0)
	body.add_child(cs)
	var it := Interactable.attach_to(door_hinge, "문 열기", 0.03)
	it.prompt_fn = func(): return "문 닫기" if door_open else "문 열기"
	it.action = toggle_door
	it.max_distance = 2.2

func toggle_door() -> void:
	if door_busy or door_hinge == null:
		return
	door_busy = true
	stats.interactions += 1
	var target := 0.0 if door_open else deg_to_rad(100.0)
	var pos := door_hinge.global_position + Vector3(0.6, 1.0, 0.0)
	if not door_open:
		Sounds.play_at("sfx_door_open", pos, &"SFX", -2.0, null, 0.03, "문 열리는 소리")
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(door_hinge, "rotation:y", target, 1.0 if not door_open else 0.8)
	if door_open:
		get_tree().create_timer(0.45).timeout.connect(func(): Sounds.play_at("sfx_door_close", pos, &"SFX", 0.0, null, 0.03, "문 닫히는 소리"))
	tw.tween_callback(func():
		door_open = not door_open
		door_busy = false)

func knock() -> void:
	Sounds.play_at("sfx_knock_3", b2g(Vector3(0.95, -0.4, 1.3)), &"SFX", 0.0, null, 0.0, "문 두드리는 소리")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_knock"):
		knock()

func _switches_and_lamps() -> void:
	var sw := find_child("stu_light_switch", true, false) as Node3D
	if sw:
		var it := Interactable.attach_to(sw, "전등 스위치", 0.03, 0.1)
		it.prompt_fn = func(): return "전등 끄기" if fx["StudioCeiling"].switched_on else "전등 켜기"
		it.action = func():
			stats.interactions += 1
			fx["StudioCeiling"].press_switch()
			Sounds.play_at("sfx_light_switch", sw.global_position, &"SFX", -4.0, null, 0.05, "스위치 소리")
			for k in 2:
				var r := sw.find_child("stu_light_switch_rocker_%d" % k, true, false) as Node3D
				if r:
					r.rotation.x = deg_to_rad(8.0 if fx["StudioCeiling"].switched_on else -8.0)
	# 책상 스탠드 (갓 주변을 바라보고 E)
	var lamp_it := Interactable.new()
	lamp_it.name = "DeskLampSwitch"
	add_child(lamp_it)
	lamp_it.global_position = b2g(Vector3(1.98, 4.3, 1.15))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, 0.35, 0.3)
	cs.shape = bs
	lamp_it.add_child(cs)
	lamp_it.prompt_fn = func(): return "스탠드 끄기" if fx["DeskLamp"].switched_on else "스탠드 켜기"
	lamp_it.action = func():
		stats.interactions += 1
		fx["DeskLamp"].press_switch()
		Sounds.play_at("sfx_light_switch", lamp_it.global_position, &"SFX", -8.0)

func _furniture() -> void:
	for i in 3:
		var dr := find_child("stu_desk_drawer_%d" % i, true, false) as Node3D
		if dr == null:
			continue
		var base := dr.position
		var it := Interactable.attach_to(dr, "서랍 열기", 0.01)
		var open := [false]
		it.prompt_fn = func(): return "서랍 닫기" if open[0] else "서랍 열기"
		it.action = func():
			stats.interactions += 1
			open[0] = not open[0]
			var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(dr, "position", base + (Vector3(0, 0, 0.3) if open[0] else Vector3.ZERO), 0.45)
			Sounds.play_at("sfx_drawer_open" if open[0] else "sfx_drawer_close", dr.global_position, &"SFX", -6.0)
	for i in 2:
		var cd := find_child("stu_cabinet_door_%d" % i, true, false) as Node3D
		if cd == null:
			continue
		var base_r := cd.rotation.y
		var it := Interactable.attach_to(cd, "수납장 열기", 0.01)
		var open := [false]
		var sign_ := 1.0 if i == 0 else -1.0
		it.prompt_fn = func(): return "수납장 닫기" if open[0] else "수납장 열기"
		it.action = func():
			stats.interactions += 1
			open[0] = not open[0]
			var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(cd, "rotation:y", base_r + (deg_to_rad(100.0) * sign_ if open[0] else 0.0), 0.5)
			Sounds.play_at("sfx_drawer_open" if open[0] else "sfx_drawer_close", cd.global_position, &"SFX", -8.0, null, 0.1)

func _clock() -> void:
	clock_second = find_child("stu_clock_hand_second", true, false) as Node3D
	clock_minute = find_child("stu_clock_hand_minute", true, false) as Node3D

func _locked_doors() -> void:
	for spec in [["303", Vector3(-2.6, -0.3, 1.0)], ["305", Vector3(9.0, -0.3, 1.0)], ["308", Vector3(2.0, -1.9, 1.0)],
			["306", Vector3(9.5, -1.9, 1.0)], ["셔터", Vector3(5.4, -1.9, 1.0)]]:
		var it := Interactable.new()
		it.name = "Locked_" + spec[0]
		add_child(it)
		it.global_position = b2g(spec[1])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.9 if spec[0] != "셔터" else 2.2, 2.0, 0.12)
		cs.shape = bs
		it.add_child(cs)
		it.prompt = ("%s호 문" % spec[0]) if spec[0] != "셔터" else "셔터"
		it.action = func():
			Sounds.play_at("sfx_door_locked", it.global_position, &"SFX", -4.0, null, 0.05, "잠긴 문")
			hud.show_toast("잠겨 있다.")
	var el := Interactable.new()
	el.name = "ElevatorButton"
	add_child(el)
	el.global_position = b2g(Vector3(-4.93, -0.32, 1.15))
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(0.15, 0.3, 0.2)
	cs2.shape = bs2
	el.add_child(cs2)
	el.prompt = "엘리베이터 호출"
	el.action = func():
		Sounds.play_at("sfx_light_switch", el.global_position, &"SFX", -6.0)
		hud.show_toast("버튼에 불이 들어오지 않는다.")

# ======================================================================= 주요 오브젝트
func _place(scene_name: String, marker: String, offset := Vector3.ZERO) -> Node3D:
	var mk := find_child(marker, true, false) as Node3D
	if mk == null or not ResourceLoader.exists(PROPS + scene_name + ".gltf"):
		push_warning("prop/marker missing: %s %s" % [scene_name, marker])
		return null
	var inst := (load(PROPS + scene_name + ".gltf") as PackedScene).instantiate() as Node3D
	mk.add_child(inst)
	inst.position = offset
	_fix_materials(inst)
	return inst

func _props() -> void:
	# 손전등 — 수납장 위. 정전 때 찾게 되는 위치 (요구사항 03 §2)
	var fl := _place("prop_flashlight", "stu_spawn_prop_flashlight", Vector3(0, 0.0285, 0))
	if fl:
		var it := Interactable.attach_to(fl, "손전등", 0.02, 0.08)
		it.inspectable = true
		it.inspect_visual = fl
		it.inspect_title = "손전등"
		it.inspect_text = "검은 금속 손전등. 손잡이 홈의 도장이 군데군데 벗겨져 있다.\n위쪽 버튼으로 켜고 끈다."
		it.pickup_item = &"flashlight"
	# 녹음기 (책상) — 테이프를 넣고 재생
	recorder = _place("prop_recorder", "stu_spawn_prop_recorder")
	if recorder:
		var it := Interactable.attach_to(recorder, "녹음기", 0.015, 0.08)
		it.prompt_fn = _recorder_prompt
		it.action = _recorder_use
		motor = AmbientEmitter.new()
		motor.bus = &"SFX"
		motor.unit_size = 1.0
		motor.base_volume_db = -12.0
		recorder.add_child(motor)
		hiss = AmbientEmitter.new()
		hiss.bus = &"SFX"
		hiss.unit_size = 1.0
		hiss.base_volume_db = -16.0
		recorder.add_child(hiss)
	# 테이프 재생 장비 (책상 좌측)
	deck = _place("prop_tape_deck", "stu_spawn_prop_tape_deck")
	if deck:
		var it := Interactable.attach_to(deck, "테이프 데크", 0.015)
		it.prompt_fn = func(): return "데크 도어 닫기" if deck_open else "데크 도어 열기"
		it.action = _deck_toggle
		for i in 2:
			var nd := deck.find_child("prop_deck_vu_%d_needle" % i, true, false) as Node3D
			if nd:
				_vu.append([nd, nd.rotation.z])
	# 택배 상자 (복도, 문 앞)
	parcel = _place("prop_parcel", "stu_spawn_prop_parcel")
	if parcel:
		var it := Interactable.attach_to(parcel, "택배 상자", 0.015)
		it.name = "ParcelInteract"
		it.prompt_fn = func(): return "상자 열기" if not parcel_open else "택배 상자"
		it.action = _parcel_open
		var wb := parcel.find_child("prop_parcel_waybill", true, false) as Node3D
		if wb:
			var wit := Interactable.attach_to(wb, "운송장", 0.01, 0.03)
			wit.inspectable = true
			wit.inspect_visual = wb
			wit.inspect_title = "운송장"
			wit.inspect_text = "받는 분: 서정우 님 — 이 작업실 주소.\n보내는 분 칸이 비어 있다."
	# 어둠 속 단서 1: 책상 아래 떨어진 라벨 없는 카세트
	var mk := find_child("stu_spawn_clue_under_desk", true, false) as Node3D
	if mk and ResourceLoader.exists(PROPS + "prop_cassette_shelf.gltf"):
		var c := (load(PROPS + "prop_cassette_shelf.gltf") as PackedScene).instantiate() as Node3D
		mk.add_child(c)
		c.rotation = Vector3(deg_to_rad(90), 0, 0)
		c.position = Vector3(0, 0.009, 0)
		var it := Interactable.attach_to(c, "카세트테이프", 0.02, 0.08)
		it.inspectable = true
		it.inspect_visual = c
		it.inspect_title = "라벨 없는 카세트테이프"
		it.inspect_text = "책상 아래 어둠 속에 떨어져 있었다.\n케이스 등에 아무것도 적혀 있지 않다."
		it.pickup_item = &"cassette_unlabeled"
	# 어둠 속 단서 2: 불이 나간 하행 계단참의 열쇠 꾸러미
	var keys := _place("prop_keys", "cor_spawn_clue_dark_landing")
	if keys:
		var it := Interactable.attach_to(keys, "열쇠", 0.02, 0.1)
		it.inspectable = true
		it.inspect_visual = keys
		it.inspect_title = "열쇠 꾸러미"
		it.inspect_text = "불 꺼진 계단참에 떨어져 있었다. 파란 플라스틱 태그에는 아무것도 적혀 있지 않다."
		it.pickup_item = &"keys_stairwell"

func _parcel_open() -> void:
	if parcel_open:
		return
	parcel_open = true
	stats.interactions += 1
	var seal := parcel.find_child("prop_parcel_seal_tape", true, false) as Node3D
	Sounds.play_at("sfx_tape_rip", parcel.global_position + Vector3(0, 0.2, 0), &"SFX", -4.0, null, 0.0, "테이프 뜯는 소리")
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func(): if seal: seal.visible = false)
	# 긴 덮개 → 짧은 덮개 순서 (실제 상자 접힘 순서)
	var spec := [["prop_parcel_flap_long_a", Vector3(deg_to_rad(205), 0, 0)], ["prop_parcel_flap_long_b", Vector3(deg_to_rad(-205), 0, 0)],
			["prop_parcel_flap_short_a", Vector3(0, 0, deg_to_rad(195))], ["prop_parcel_flap_short_b", Vector3(0, 0, deg_to_rad(-195))]]
	for s in spec:
		var fl := parcel.find_child(s[0], true, false) as Node3D
		if fl == null:
			continue
		var target: Vector3 = fl.rotation + s[1]
		tw.tween_callback(func(): Sounds.play_at("sfx_cardboard_flap", fl.global_position, &"SFX", -6.0))
		tw.tween_property(fl, "rotation", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_parcel_contents_ready)

func _parcel_contents_ready() -> void:
	var box_it := parcel.find_child("ParcelInteract", false, false) as Interactable
	if box_it:
		box_it.enabled = false
	for n in range(1, 8):
		var t := parcel.find_child("prop_tape_%d" % n, true, false) as Node3D
		if t == null:
			continue
		var it := Interactable.attach_to(t, "테이프 %d" % n, 0.003, 0.03)
		it.inspectable = true
		it.inspect_visual = t
		it.inspect_title = "카세트테이프 %d번" % n
		it.inspect_text = "C-60 카세트. 라벨에 손으로 쓴 숫자 '%d'.\n창 너머로 감긴 테이프가 보인다." % n
		it.pickup_item = StringName("tape_%d" % n)
	var memo := parcel.find_child("prop_memo", true, false) as Node3D
	if memo:
		var it := Interactable.attach_to(memo, "메모", 0.005, 0.03)
		it.inspectable = true
		it.inspect_visual = memo
		it.inspect_title = "손으로 쓴 메모"
		it.inspect_text = "잡음을 제거하지 말아 주세요.\n그 안에 목소리가 있습니다."
		it.pickup_item = &"note_prologue"

func _held_tape() -> String:
	for n in range(1, 8):
		if Inventory.has(StringName("tape_%d" % n)):
			return "%d" % n
	return ""

func _recorder_prompt() -> String:
	match recorder_state:
		"empty":
			return ("테이프 %s 넣기" % _held_tape()) if _held_tape() != "" else "녹음기 (테이프 없음)"
		"loaded":
			return "재생"
		_:
			return "정지"

func _press(node_name: String, root: Node3D, axis := Vector3(0, 0, 0.003)) -> void:
	var b := root.find_child(node_name, true, false) as Node3D
	if b == null:
		return
	var p := b.position
	var tw := create_tween()
	tw.tween_property(b, "position", p - axis, 0.06)
	tw.tween_property(b, "position", p, 0.1)

func _recorder_use() -> void:
	stats.interactions += 1
	match recorder_state:
		"empty":
			var n := _held_tape()
			if n == "":
				Sounds.play_at("sfx_deck_button", recorder.global_position, &"SFX", -10.0)
				hud.show_toast("넣을 테이프가 없다.")
				return
			_insert_tape(n)
		"loaded":
			_play_tape()
		"playing":
			_stop_tape()

func _insert_tape(n: String) -> void:
	recorder_state = "busy"
	var door := recorder.find_child("prop_recorder_door", true, false) as Node3D
	var slot := recorder.find_child("prop_recorder_tape_slot", true, false) as Node3D
	var src := (load(PROPS + "prop_tapes.gltf") as PackedScene).instantiate()
	var tape := src.find_child("prop_tape_" + n, true, false) as Node3D
	tape.get_parent().remove_child(tape)
	src.queue_free()
	recorder_tape = tape
	slot.add_child(tape)
	tape.transform = Transform3D.IDENTITY
	tape.position = Vector3(0, 0.07, 0)
	_fix_materials(tape)
	_reels = []
	for side in ["l", "r"]:
		var r := tape.find_child("prop_tape_%s_reel_%s" % [n, side], true, false) as Node3D
		if r:
			_reels.append(r)
	var base_r := door.rotation.x
	var tw := create_tween()
	tw.tween_callback(func(): Sounds.play_at("sfx_cassette_door", recorder.global_position, &"SFX", -6.0))
	tw.tween_property(door, "rotation:x", base_r - deg_to_rad(55), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tape, "position", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): Sounds.play_at("sfx_cassette_insert", recorder.global_position, &"SFX", -4.0, null, 0.0, "테이프 넣는 소리"))
	tw.tween_interval(0.25)
	tw.tween_property(door, "rotation:x", base_r, 0.22)
	tw.tween_callback(func():
		Sounds.play_at("sfx_cassette_door", recorder.global_position, &"SFX", -4.0)
		Inventory.items.erase(StringName("tape_" + n))
		recorder_state = "loaded"
		hud.show_toast("테이프 %s번을 넣었다." % n))

func _play_tape() -> void:
	recorder_state = "playing"
	_press("prop_recorder_btn_play", recorder, Vector3(0, 0, -0.003))
	Sounds.play_at("sfx_deck_button", recorder.global_position, &"SFX", -4.0, null, 0.0, "재생 버튼")
	motor.stream = Sounds.pick("amb_tape_motor")
	motor.play()
	hiss.stream = Sounds.pick("amb_tape_hiss")
	hiss.play()
	# 테이프 음성 (VoiceTape 버스: 대역 제한·미세 왜곡) — 임시 TTS 가이드 음성
	get_tree().create_timer(1.6).timeout.connect(func():
		if recorder_state == "playing":
			_play_line_at("PRO_S05_001", recorder))

func _stop_tape() -> void:
	recorder_state = "loaded"
	_press("prop_recorder_btn_stop", recorder, Vector3(0, 0, -0.003))
	Sounds.play_at("sfx_tape_stop", recorder.global_position, &"SFX", -4.0, null, 0.0, "정지 버튼")
	motor.stop()
	hiss.stop()

func _play_line_at(line_id: String, at: Node3D) -> void:
	var stream := DialogueDB.audio_of(line_id)
	DialogueDB.line_started.emit(DialogueDB.get_line(line_id))
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"VoiceTape"
	p.unit_size = 1.5
	p.volume_db = 2.0
	at.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	player.breathing.duck(true)
	p.finished.connect(func(): player.breathing.duck(false))

func _deck_toggle() -> void:
	stats.interactions += 1
	var door := deck.find_child("prop_deck_door", true, false) as Node3D
	if door == null:
		return
	if not door.has_meta("base_x"):
		door.set_meta("base_x", door.rotation.x)
	var base_x: float = door.get_meta("base_x")
	deck_open = not deck_open
	_press("prop_deck_btn_eject", deck, Vector3(0, 0, -0.003))
	Sounds.play_at("sfx_cassette_door", deck.global_position, &"SFX", -5.0, null, 0.0, "카세트 도어")
	var tw := create_tween()
	tw.tween_property(door, "rotation:x", base_x + (deg_to_rad(25.0) if deck_open else 0.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
