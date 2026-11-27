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
## true: 스토리 진행(프롤로그 이벤트). false: 테스트·검토용 샌드박스 (모든 물건이 처음부터 접근 가능)
@export var story := true
## 테스트·영상 캡처용: 메인 씬이 아니어도 스토리를 진행
@export var force_story := false

var pause_menu: CanvasLayer
var director: EventDirector
var story_fx: PrologueStory
var apt: AptCorridor
var door_locked := false
var clock_running := true
var parcel_on_desk := false
var parcel_carried := false
var rain_emitters: Array = []
var pc_fan_emitter: AmbientEmitter
var monitor_screen: MeshInstance3D
var _monitor_mat_orig: Material
var flashlight_prop: Node3D
var drawer_open := [false, false, false]
var debug_menu: CanvasLayer
var monster_node: Node3D
var monster_poser: CharacterPoser
var soeun_node: Node3D
var soeun_poser: CharacterPoser
var clue_tape: Node3D
var _self_play := false
var _rewinding := false
var _dropout_t := 3.0
var _mon_breath: AmbientEmitter
var title_ui: CanvasLayer
var title_cam: Camera3D
var _title_t := 0.0

var player: PlayerController
var hud: HUD
var stu: Node3D
var cor: Node3D
var env: Environment
var exit_glow: OmniLight3D       ## 비상구 유도등 번짐 (정전 때 독립 전원으로 아주 희미하게만)
var _cor_emissive: Array = []   ## 복도 발광 재질 [mat, 기본값]
var fx := {}                     ## 이름 → LightFixture
var door_hinge: Node3D
var door_body: AnimatableBody3D
var door_open := false
var door_busy := false
var window_light: SpotLight3D
var window_base_energy := 2.4
const WINDOW_ENERGY := 2.4
var monitor_light: OmniLight3D
var probes: Array[ReflectionProbe] = []
var city_mat: ShaderMaterial
var lighting := "normal"
var _carry_tutorial_done := false           ## 조명 상태 (요구사항 12 §3)
var _emissive_mats: Array = []     ## 작업실 전자기기 발광 재질 [mat, energy]
var emergency_light: OmniLight3D
var _emergency_mesh: MeshInstance3D
var recorder: Node3D
var recorder_state := "empty"    ## empty / loaded / playing
var recorder_tape: Node3D
var recorder_tape_no := ""
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
	player.visibility_check = point_lit
	# 조사 화면을 일반 플레이 화면과 분리 (요구사항 14): 배경을 어둡게·흐리게
	player.inspect.opened.connect(func(_t): _inspect_view(true))
	player.inspect.closed.connect(func(_t, _p): _inspect_view(false))
	_door()
	_switches_and_lamps()
	_furniture()
	_clock()
	_props()
	_locked_doors()
	_setup_flow()
	GameSettings.changed.connect(_on_setting)
	if OS.get_cmdline_user_args().has("--input-probe"):
		# 실제 OS 입력 검증용: 0.5초마다 상태·시점 값을 출력 (xdotool 테스트)
		var t := Timer.new()
		t.wait_time = 0.5
		t.autostart = true
		t.process_mode = Node.PROCESS_MODE_ALWAYS
		t.timeout.connect(func(): print("PROBE state=%d paused=%s mouse_mode=%d popups=%d yaw=%.3f pitch=%.3f pos=%s focus=%s" % [
			GameFlow.state, get_tree().paused, Input.mouse_mode, ConfirmDialogUI.open_count, player.get("_yaw"), player.get("_pitch"), player.global_position, get_viewport().gui_get_focus_owner()]))
		add_child(t)
	if OS.get_cmdline_user_args().has("--benchmark"):
		enable_thunder = false
		var b := Benchmark.new()
		add_child(b)
		b.run(self)

# ======================================================================= 진행 흐름 (타이틀 · 일시정지 · 저장)
func _setup_flow() -> void:
	pause_menu = load("res://scripts/ui/pause_menu.gd").new()
	add_child(pause_menu)
	pause_menu.restart_checkpoint.connect(func():
		if SaveGame.has_save():
			SaveGame.pending = SaveGame.read()
			GameFlow.restart_level("continue")
		else:
			GameFlow.restart_level("new"))
	pause_menu.main_menu.connect(func(): GameFlow.restart_level("title"))
	var is_main := get_tree().current_scene == self
	var mode := GameFlow.start_mode
	if not is_main or GameFlow.skip_title:
		mode = "new" if mode == "title" else mode
	if mode == "title":
		_enter_title()
		return
	var story_on := story and (is_main or force_story)
	if not story_on:
		story = false
	player.recorder_key_pressed.connect(recorder_key)
	if story_on:
		_setup_story(mode)
	if mode == "continue" and not SaveGame.pending.is_empty():
		var st: Dictionary = SaveGame.pending.get("state", {})
		apply_save_state(st)
		if director:
			director.restore(st.get("done", []))
		SaveGame.pending = {}
	elif story_on:
		Inventory.clear()
		_on_new_game_started()
	GameFlow.set_state(GameFlow.State.PLAYING)

## 새 게임 시작 시점 (스토리 이벤트 디렉터가 연결)
func _on_new_game_started() -> void:
	if director:
		director.start_new()

func _enter_title() -> void:
	GameFlow.set_state(GameFlow.State.TITLE)
	player.input_enabled = false
	hud.visible = false
	player.breathing.process_mode = Node.PROCESS_MODE_DISABLED
	# 타이틀 연출: 천장등 끔 · 책상 스탠드만 · 녹음기에 테이프가 돌아간다
	fx["StudioCeiling"].switched_on = false
	fx["StudioCeiling"].set_state(fx["StudioCeiling"].state)
	if recorder:
		_load_tape_instant("1")
		recorder_state = "playing"
		motor.stream = Sounds.pick("amb_tape_motor")
		motor.base_volume_db = -20.0
		motor.play()
		hiss.stream = Sounds.pick("amb_tape_hiss")
		hiss.base_volume_db = -24.0
		hiss.play()
	title_cam = Camera3D.new()
	title_cam.fov = 48.0
	title_cam.near = 0.03
	add_child(title_cam)
	title_cam.current = true
	_title_cam_update(0.0)
	title_ui = load("res://scripts/ui/title_screen.gd").new()
	add_child(title_ui)
	title_ui.new_game.connect(func():
		SaveGame.pending = {}
		GameFlow.restart_level("new"))
	title_ui.continue_game.connect(func():
		SaveGame.pending = SaveGame.read()
		GameFlow.restart_level("continue"))

func _title_cam_update(delta: float) -> void:
	_title_t += delta
	var focus := recorder.global_position if recorder else b2g(Vector3(2.0, 4.6, 0.9))
	# 책상 옆에서 녹음기·창문 쪽을 천천히 (40초 주기) 흔들리듯 바라본다
	var k := sin(_title_t * TAU / 40.0)
	var k2 := sin(_title_t * TAU / 27.0 + 1.3)
	var eye := b2g(Vector3(3.05 + 0.22 * k, 3.35 + 0.08 * k2, 1.28 + 0.03 * k2))
	var look := focus + Vector3(-0.35 + 0.1 * k, 0.12, -0.25)
	title_cam.global_position = eye
	title_cam.look_at(look, Vector3.UP)

func _on_setting(key: StringName) -> void:
	match String(key):
		"brightness":
			env.adjustment_brightness = GameSettings.brightness
		"graphics_quality":
			GameSettings.apply_quality(env, get_viewport())
		"fov":
			player.camera.fov = GameSettings.fov

## 저장: 레벨 상태 스냅샷
func get_save_state() -> Dictionary:
	var lights := {}
	for k in fx:
		lights[k] = {"state": int(fx[k].state), "on": fx[k].switched_on}
	return {
		"player": {"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
			"yaw": player.get("_yaw"), "pitch": player.get("_pitch")},
		"items": Inventory.items.map(func(i): return String(i)),
		"has_flashlight": Inventory.has_flashlight,
		"lights": lights,
		"objects": _objects_state(),
		"done": director.done.keys() if director else [],
		"clues": ClueBook.found.keys(),
	}

func apply_save_state(st: Dictionary) -> void:
	Inventory.clear()
	for i in st.get("items", []):
		Inventory.items.append(StringName(i))
	Inventory.has_flashlight = st.get("has_flashlight", false)
	var pl: Dictionary = st.get("player", {})
	if pl.has("pos"):
		player.global_position = Vector3(pl.pos[0], pl.pos[1], pl.pos[2])
		player.set("_yaw", float(pl.get("yaw", 0.0)))
		player.set("_pitch", float(pl.get("pitch", 0.0)))
	for k in st.get("lights", {}):
		if fx.has(k):
			fx[k].switched_on = st.lights[k].get("on", true)
			fx[k].set_state(int(st.lights[k].get("state", 0)))
	_apply_objects_state(st.get("objects", {}))
	ClueBook.restore(st.get("clues", []))

func _objects_state() -> Dictionary:
	return {"door_open": door_open, "door_locked": door_locked, "parcel_open": parcel_open, "parcel_on_desk": parcel_on_desk,
		"parcel_visible": parcel.visible if parcel else false, "recorder_state": recorder_state,
		"recorder_held": player.held_recorder != null, "flashlight_taken": flashlight_prop == null or not is_instance_valid(flashlight_prop),
		"drawer0": drawer_open[0], "tapes_done": tapes_done, "recorder_tape_no": recorder_tape_no, "in_apartment": in_apartment,
		"photo": photo != null and photo.visible}

func _apply_objects_state(o: Dictionary) -> void:
	if o.get("door_open", false) and not door_open and door_hinge:
		door_hinge.rotation.y = deg_to_rad(100.0)
		door_open = true
	door_locked = o.get("door_locked", false)
	tapes_done.assign(o.get("tapes_done", []))
	if parcel:
		parcel.visible = o.get("parcel_visible", true)
		if o.get("parcel_on_desk", false):
			parcel.top_level = true
			parcel.global_transform = _desk_place_transform()
			parcel_on_desk = true
		if o.get("parcel_open", false):
			parcel_open = true
			for n in ["prop_parcel_seal_tape"]:
				var sl := parcel.find_child(n, true, false) as Node3D
				if sl:
					sl.visible = false
			var spec := [["prop_parcel_flap_long_a", Vector3(deg_to_rad(205), 0, 0)], ["prop_parcel_flap_long_b", Vector3(deg_to_rad(-205), 0, 0)],
					["prop_parcel_flap_short_a", Vector3(0, 0, deg_to_rad(195))], ["prop_parcel_flap_short_b", Vector3(0, 0, deg_to_rad(-195))]]
			for sp in spec:
				var fl := parcel.find_child(sp[0], true, false) as Node3D
				if fl:
					fl.rotation += sp[1]
			_parcel_contents_ready(false)
			var in_rec := String(o.get("recorder_tape_no", "1" if o.get("recorder_state", "empty") != "empty" else ""))
			if in_rec != "" or Inventory.has(&"tape_1"):
				var t1 := parcel.find_child("prop_tape_%s" % (in_rec if in_rec != "" else "1"), true, false)
				if t1:
					t1.queue_free()
			if Inventory.has(&"note_prologue"):
				var mm := parcel.find_child("prop_memo", true, false)
				if mm:
					mm.queue_free()
	if o.get("flashlight_taken", false) and flashlight_prop and is_instance_valid(flashlight_prop):
		flashlight_prop.queue_free()
		flashlight_prop = null
	if o.get("recorder_state", "empty") != "empty" and recorder:
		_load_tape_instant(String(o.get("recorder_tape_no", "1")) if String(o.get("recorder_tape_no", "")) != "" else "1")
	if o.get("photo", false):
		show_photo(true)
	if o.get("recorder_held", false):
		_pick_recorder.call_deferred()

func checkpoint(id: String) -> void:
	if not story:
		return
	SaveGame.write(id, get_save_state())
	if hud:
		hud.show_toast(tr("자동 저장됨 · ") + tr(SaveGame.LABELS.get(id, id)), 2.5, true)

## 녹음기에 테이프를 애니메이션 없이 바로 넣는다 (타이틀 연출·불러오기)
func _load_tape_instant(n: String) -> void:
	var slot := recorder.find_child("prop_recorder_tape_slot", true, false) as Node3D
	var src := (load(PROPS + "prop_tapes.gltf") as PackedScene).instantiate()
	var tape := src.find_child("prop_tape_" + n, true, false) as Node3D
	tape.get_parent().remove_child(tape)
	src.queue_free()
	recorder_tape = tape
	recorder_tape_no = n
	slot.add_child(tape)
	tape.transform = Transform3D.IDENTITY
	_fix_materials(tape)
	_reels = []
	for side in ["l", "r"]:
		var r := tape.find_child("prop_tape_%s_reel_%s" % [n, side], true, false) as Node3D
		if r:
			_reels.append(r)
	recorder_state = "loaded"

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
					city_mat = cm
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
	monitor_light = mon
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
	exit_glow = ex
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
		probes.append(rp)

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
	rain_emitters.append(_emitter("amb_rain_window", Vector3(2.2, 5.05, 1.5), -4.0, 3.0))
	rain_emitters.append(_emitter("amb_rain_window", Vector3(3.9, 5.05, 1.5), -4.0, 3.0))
	rain_emitters.append(_emitter("amb_rain_heavy", Vector3(3.0, 9.0, 2.0), -6.0, 6.0))
	var pc := find_child("stu_spawn_sound_pc_fan", true, false) as Node3D
	var e := _emitter("amb_pc_fan", Vector3(2.25, 4.5, 0.3), -15.0, 1.2)
	pc_fan_emitter = e
	if pc:
		e.global_position = pc.global_position
	for i in 6:
		var x: float = [-3.5, -0.5, 2.5, 5.5, 8.5, 11.5][i]
		_emitter("amb_fluorescent_buzz" if i == 4 else "amb_fluorescent_hum", Vector3(x, -1.1, 2.42), -20.0 if i != 4 else -14.0, 1.4)
	_emitter("amb_fluorescent_hum", Vector3(14.95, 2.9, 3.4), -20.0, 1.4)
	rain_emitters.append(_emitter("amb_rain_muffled", Vector3(15.4, 3.2, 1.2), -10.0, 3.0))
	rain_emitters.append(_emitter("amb_rain_muffled", Vector3(-4.8, -1.1, 1.5), -14.0, 3.0))
	if fx.has("CorLight4"):
		fx["CorLight4"].flickered.connect(func(on): if on and randf() < 0.35:
			Sounds.play_at("sfx_flicker_zap", b2g(Vector3(8.5, -1.1, 2.4)), &"SFX", -12.0))

func _process(delta: float) -> void:
	if title_cam and title_cam.current:
		_title_cam_update(delta)
	if flashlight_prop and is_instance_valid(flashlight_prop) and flashlight_prop.get_parent() and flashlight_prop.get_parent().name == "stu_desk_drawer_0":
		var fit := flashlight_prop.find_child("FlashlightInteract", false, false) as Interactable
		if fit:
			fit.enabled = drawer_open[0]
	# 벽시계 초침: 1초마다 한 칸 + 째깍 소리 (시계 위치에서)
	_tick += delta
	if _tick >= 1.0 and clock_second and clock_running:
		_tick -= 1.0
		clock_second.rotate_object_local(Vector3.UP, -deg_to_rad(6.0))
		if clock_minute:
			clock_minute.rotate_object_local(Vector3.UP, -deg_to_rad(0.1))
		_tock = not _tock
		Sounds.play_at("sfx_clock_tick", clock_second.global_position, &"SFX", -15.0, null, 0.0, "", 1.0)
	# 천둥
	if enable_thunder and (story_fx == null or story_fx.rain_on):
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
	if _rewinding:
		for r in _reels:
			if is_instance_valid(r):
				r.rotate_object_local(Vector3.UP, delta * 14.0)
	# (요구사항 20: 재생 중 무작위 잡음 튐 제거 — 대사 재생 중 반복 잡음 금지)
	if recorder_state == "playing" or _self_play:
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
	# 손: 안쪽 레버를 잡고 내렸다가 문이 열리는 동안 잠깐 따라간다
	var lever := door_hinge.find_child("stu_door_lever_in", true, false) as Node3D
	if lever:
		it.reach = "grab"
		it.reach_target = lever
		it.reach_hold = 0.45
		it.reach_follow = func(_k: float) -> Vector3: return lever.global_position

var _locked_rattle_ms := 0
func toggle_door() -> void:
	if door_busy or door_hinge == null:
		return
	if door_locked and not door_open:
		# 잠김: 손잡이만 덜컥거린다 (요구사항 20: 연타해도 덜컥 소리·손잡이 동작이 겹치지 않게 0.35초 간격)
		var now := Time.get_ticks_msec()
		if now - _locked_rattle_ms < 350 and _locked_rattle_ms > 0:
			_notify("door_locked_try")
			return
		_locked_rattle_ms = now
		Sounds.play_at("sfx_door_locked", door_hinge.global_position + Vector3(0.6, 1.0, 0.0), &"SFX", -2.0, null, 0.03, "잠긴 문이 덜컥거리는 소리")
		var lev := door_hinge.find_child("stu_door_lever_in", true, false) as Node3D
		if lev:
			var r0 := lev.rotation
			var tw0 := create_tween()
			for k in 2:
				tw0.tween_property(lev, "rotation:z", r0.z - deg_to_rad(25), 0.08)
				tw0.tween_property(lev, "rotation:z", r0.z, 0.1)
		if story_fx:
			story_fx.tried_door = true
		_notify("door_locked_try")
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
		door_busy = false
		if door_open:
			_notify("door_opened"))

## 문이 저절로 쾅 닫힌다 (스토리 연출)
func slam_door(instant := false) -> void:
	if door_hinge == null or not door_open:
		return
	door_open = false
	if instant:
		door_hinge.rotation.y = 0.0
		return
	door_busy = true
	var tw := create_tween()
	tw.tween_property(door_hinge, "rotation:y", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		Sounds.play_at("sfx_door_close", door_hinge.global_position + Vector3(0.6, 1.0, 0.0), &"SFX", 4.0, null, 0.0, "문이 쾅 닫히는 소리")
		door_busy = false)

func knock_debug() -> void:
	knock("normal")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_knock"):
		knock_debug()

func _switches_and_lamps() -> void:
	var sw := find_child("stu_light_switch", true, false) as Node3D
	if sw:
		var it := Interactable.attach_to(sw, "전등 스위치", 0.03, 0.1)
		it.reach = "press"
		it.reach_target = sw.find_child("stu_light_switch_rocker_0", true, false) as Node3D
		it.reach_hold = 0.12
		it.prompt_fn = func(): return "전등 끄기" if fx["StudioCeiling"].switched_on else "전등 켜기"
		it.action = func():
			stats.interactions += 1
			fx["StudioCeiling"].press_switch()
			Sounds.play_at("sfx_light_switch", sw.global_position, &"SFX", -4.0, null, 0.05, "스위치 소리")
			_notify("switch", "on" if fx["StudioCeiling"].switched_on else "off")
			if fx["StudioCeiling"].switched_on and not fx["StudioCeiling"].is_emitting():
				hud.show_toast("…켜지지 않는다.")
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
	lamp_it.reach = "press"
	lamp_it.reach_hold = 0.1
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
		# 판정 상자는 서랍 앞판에만 (열린 서랍 안의 물건을 가리지 않게)
		var front := dr.find_child("stu_desk_drawer_%d_front" % i, true, false) as Node3D
		var it := Interactable.attach_to(front if front else dr, "서랍 열기", 0.01)
		var open := [false]
		var idx := i
		var pull := dr.find_child("stu_desk_drawer_%d_pull" % i, true, false) as Node3D
		if pull:
			it.reach = "pull"
			it.reach_target = pull
			it.reach_hold = 0.42
			it.reach_follow = func(_k: float) -> Vector3: return pull.global_position
		it.prompt_fn = func(): return "서랍 닫기" if open[0] else "서랍 열기"
		it.action = func():
			stats.interactions += 1
			open[0] = not open[0]
			drawer_open[idx] = open[0]
			_notify("drawer", str(idx))
			# 요구사항 14: 손 대신 서랍 자체의 물리적인 움직임 — 열 때 레일 끝에서 살짝 튕기고, 닫을 때 끝에서 '탁'
			var tw := create_tween()
			if open[0]:
				tw.tween_property(dr, "position", base + Vector3(0, 0, 0.39), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(dr, "position", base + Vector3(0, 0, 0.38), 0.08)
			else:
				tw.tween_property(dr, "position", base, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(dr, "position", base + Vector3(0, 0, 0.004), 0.05)
				tw.tween_property(dr, "position", base, 0.06)
			Sounds.play_at("sfx_drawer_open" if open[0] else "sfx_drawer_close", dr.global_position, &"SFX", -6.0)
	for i in 2:
		var cd := find_child("stu_cabinet_door_%d" % i, true, false) as Node3D
		if cd == null:
			continue
		var base_r := cd.rotation.y
		var it := Interactable.attach_to(cd, "수납장 열기", 0.01)
		var knob := cd.find_child("stu_cabinet_door_%d_knob" % i, true, false) as Node3D
		if knob:
			it.reach = "pull"
			it.reach_target = knob
			it.reach_hold = 0.35
			it.reach_follow = func(_k: float) -> Vector3: return knob.global_position
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
		it.prompt = (tr("%s호 문") % spec[0]) if spec[0] != "셔터" else "셔터"
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
	# 손전등 — 책상 맨 위 서랍 안 (요구사항 08 EVENT 06). 서랍이 열려 있을 때만 집을 수 있다
	var fl: Node3D = null
	var dr0 := find_child("stu_desk_drawer_0", true, false) as Node3D
	if dr0 and ResourceLoader.exists(PROPS + "prop_flashlight.gltf"):
		fl = (load(PROPS + "prop_flashlight.gltf") as PackedScene).instantiate() as Node3D
		dr0.add_child(fl)
		_fix_materials(fl)
		# 요구사항 20: 서랍 앞쪽 중앙, 바닥판 위에 옆으로 눕힘 (스위치가 위, 머리는 왼쪽).
		# 서랍 원점 = 앞판 중앙. 서랍 안쪽은 Godot -Z. 앞판에서 10 cm 안쪽 = 열었을 때 책상 상판에 가리지 않는 구간
		var floor_y := -0.05
		var bottom := dr0.find_child("stu_desk_drawer_0_bottom", true, false) as MeshInstance3D
		if bottom:
			var bb := (dr0.global_transform.affine_inverse() * bottom.global_transform) * bottom.get_aabb()
			floor_y = bb.end.y
		fl.rotation = Vector3(0, deg_to_rad(90), 0)
		fl.position = Vector3(0.115, floor_y + 0.03, -0.10)
		# 실제 메시 경계로 바닥판 위에 정확히 올린다 (머리 베젤이 바닥에 닿음 — 파묻히지 않게)
		var fb := (dr0.global_transform.affine_inverse() * fl.global_transform) * Interactable.local_aabb(fl)
		fl.position.y += floor_y + 0.0015 - fb.position.y
		fl.position.x -= fb.get_center().x
		for c in fl.find_children("*", "CollisionObject3D", true, false):
			c.queue_free()
	else:
		fl = _place("prop_flashlight", "stu_spawn_prop_flashlight", Vector3(0, 0.0285, 0))
	flashlight_prop = fl
	if fl:
		var it := Interactable.attach_to(fl, "손전등", 0.02, 0.08)
		it.name = "FlashlightInteract"
		it.reach = "pick"
		# 요구사항 20: E 한 번에 바로 획득 (예전엔 조사 화면이 먼저 열려 E를 두 번 눌러야 했다)
		it.action = func():
			if Inventory.has_flashlight:
				return
			stats.interactions += 1
			Inventory.add(&"flashlight")
			Sounds.play("sfx_pickup", &"SFX", -2.0)
			if is_instance_valid(fl):
				fl.queue_free()
			flashlight_prop = null
	# 녹음기 (책상) — 테이프를 넣고 재생
	recorder = _place("prop_recorder", "stu_spawn_prop_recorder")
	if recorder:
		_rec_home = recorder.global_transform
		var it := Interactable.attach_to(recorder, "녹음기", 0.015, 0.08)
		it.name = "RecorderInteract"
		it.prompt_fn = func(): return "녹음기 들기" if _hands_on() else _recorder_prompt()
		it.action = func():
			if _hands_on():
				_pick_recorder()
			else:
				_recorder_use()
		it.reach = "pick"
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
		it.prompt_fn = func():
			if parcel_open:
				return "택배 상자"
			return "상자 열기" if (parcel_on_desk or not story) else "상자 들기"
		it.action = func():
			if parcel_open:
				return
			if story and not parcel_on_desk:
				_parcel_pick_up()
			elif _hands_on():
				_parcel_open_hands()
			else:
				_parcel_open()
		var wb := parcel.find_child("prop_parcel_waybill", true, false) as Node3D
		if wb:
			var wit := Interactable.attach_to(wb, "운송장", 0.01, 0.03)
			wit.inspectable = true
			wit.inspect_visual = wb
			wit.inspect_title = "운송장"
			wit.inspect_text = "받는 분: 서정우 — 이 작업실 주소.\n보내는 분 칸은 비어 있다."
			wit.reach = "pick"
	# 어둠 속 단서 1: 책상 아래 떨어진 라벨 없는 카세트
	var mk := find_child("stu_spawn_clue_under_desk", true, false) as Node3D
	if mk and ResourceLoader.exists(PROPS + "prop_cassette_shelf.gltf"):
		var c := (load(PROPS + "prop_cassette_shelf.gltf") as PackedScene).instantiate() as Node3D
		mk.add_child(c)
		c.rotation = Vector3(deg_to_rad(90), 0, 0)
		c.position = Vector3(0, 0.009, 0)
		clue_tape = c
		var it := Interactable.attach_to(c, "카세트테이프", 0.02, 0.08)
		it.inspectable = true
		it.inspect_visual = c
		it.inspect_title = "라벨 없는 카세트테이프"
		it.inspect_text = "상자에서 사라졌던 테이프다.\n왜 책상 아래에…"
		it.inspect_text_back = "뒷면 — 연필 자국이 희미하다.\n'B면은 끝까지 들어.'"
		it.clue_back = &"clue_pro_tape_back"
		it.reach = "pick"
		it.pickup_item = &"cassette_unlabeled"
	# 어둠 속 단서 2: 불이 나간 하행 계단참의 열쇠 꾸러미
	var keys := _place("prop_keys", "cor_spawn_clue_dark_landing")
	if keys:
		var it := Interactable.attach_to(keys, "열쇠", 0.02, 0.1)
		it.inspectable = true
		it.inspect_visual = keys
		it.inspect_title = "열쇠 꾸러미"
		it.inspect_text = "불 꺼진 계단참에 떨어져 있었다.\n파란 태그에는 아무것도 적혀 있지 않다."
		it.reach = "pick"
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

func _parcel_contents_ready(fresh := true) -> void:
	var box_it := parcel.find_child("ParcelInteract", false, false) as Interactable
	if box_it:
		box_it.enabled = false
	for n in range(1, 8):
		var t := parcel.find_child("prop_tape_%d" % n, true, false) as Node3D
		if t == null:
			continue
		var it := Interactable.attach_to(t, ("첫 번째 테이프 획득" if n == 1 else "TAPE 0%d" % n), 0.006, 0.03)
		it.inspectable = true
		it.inspect_visual = t
		it.highlight = true
		it.inspect_title = tr("카세트테이프 %d번") % n
		it.inspect_text = (tr("라벨에 매직으로 크게 'TAPE 0%d'.\n투명 창 너머로 감긴 테이프가 보인다.") % n) if n == 1 else (tr("라벨에 'TAPE 0%d'.\n1번부터 들어 보자.") % n)
		it.reach = "pick"
		# 테이프는 순서대로만 가져간다 (요구사항 16: 테이프 순서 상태) — 다음 차례가 아니면 살펴보기만
		it.pickup_item = StringName("tape_%d" % n) if (n == next_tape() or not story) else &""
		it.set_meta("tape_no", n)
	var memo := parcel.find_child("prop_memo", true, false) as Node3D
	if memo:
		var it := Interactable.attach_to(memo, "메모", 0.005, 0.03)
		it.inspectable = true
		it.inspect_visual = memo
		it.inspect_title = "손으로 쓴 편지"
		it.highlight = true
		it.inspect_text = DialogueDB.text_of("PRO_E03_NOTE")
		it.pickup_item = &"note_prologue"
		it.reach = "pick"
	# 개봉하면 몸을 숙여 상자 안을 들여다본다 — 테이프 7개가 한눈에 보이는 시점 (이동하면 원래 자세로)
	if not fresh:
		return
	if player and player.global_position.distance_to(parcel.global_position) < 1.6:
		player.lean_into(parcel.global_position + Vector3(0, 0.05, 0))
	_notify("parcel_opened")

func _held_tape() -> String:
	for n in range(1, 8):
		if Inventory.has(StringName("tape_%d" % n)):
			return "%d" % n
	return ""

func _recorder_prompt() -> String:
	match recorder_state:
		"empty":
			return (tr("테이프 %s 넣기") % _held_tape()) if _held_tape() != "" else "녹음기 (테이프 없음)"
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
			if tapes_done.has(recorder_tape_no):
				_eject_tape()            # 다 들은 테이프는 꺼낸다 (요구사항 16: TAPE 01 → TAPE 02)
			else:
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
	_fix_materials(tape)
	var by_hand := _hands_on() and player.held_recorder != null and not Inventory.has_flashlight
	if by_hand:
		# 왼손이 테이프를 집어 녹음기 도어로 가져온다 (도어가 먼저 열림)
		add_child(tape)
		var d0 := door.rotation.x
		Sounds.play_at("sfx_cassette_door", recorder.global_position, &"SFX", -6.0)
		var twd := create_tween()
		twd.tween_property(door, "rotation:x", d0 - deg_to_rad(55), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		player.arms.press_thumb("R")
		await _hand_bring(tape, slot)
		tape.get_parent().remove_child(tape)
		slot.add_child(tape)
		tape.transform = Transform3D.IDENTITY
		tape.position = Vector3(0, 0.01, 0)
	else:
		slot.add_child(tape)
		tape.transform = Transform3D.IDENTITY
		tape.position = Vector3(0, 0.07, 0)
	_reels = []
	for side in ["l", "r"]:
		var r := tape.find_child("prop_tape_%s_reel_%s" % [n, side], true, false) as Node3D
		if r:
			_reels.append(r)
	var base_r := door.rotation.x if not by_hand else door.rotation.x + deg_to_rad(55)
	var tw := create_tween()
	if not by_hand:
		tw.tween_callback(func(): Sounds.play_at("sfx_cassette_door", recorder.global_position, &"SFX", -6.0))
		tw.tween_property(door, "rotation:x", base_r - deg_to_rad(55), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tape, "position", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): Sounds.play_at("sfx_cassette_insert", recorder.global_position, &"SFX", -4.0, null, 0.0, "테이프 넣는 소리"))
	tw.tween_interval(0.25)
	tw.tween_property(door, "rotation:x", base_r, 0.22)
	tw.tween_callback(func(): Sounds.play_at("sfx_cassette_door", recorder.global_position, &"SFX", -4.0))
	# 처음으로 되감기 (요구사항 15: 되감기 소리 + 릴이 거꾸로 빠르게 돈다)
	tw.tween_callback(func():
		_rewinding = true
		Sounds.play_at("amb_tape_rewind", recorder.global_position, &"SFX", -8.0, null, 0.0, "테이프 되감는 소리", 3.0, 1.05))   # 요구사항 20: 되감기 1.1초 뒤 반드시 끝남
	tw.tween_interval(1.1)
	tw.tween_callback(func():
		_rewinding = false
		Sounds.play_at("sfx_tape_stop", recorder.global_position, &"SFX", -10.0)
		Inventory.items.erase(StringName("tape_" + n))
		recorder_state = "loaded"
		recorder_tape_no = n
		_notify("tape_inserted", n)
		hud.show_toast(tr("테이프 %s번을 넣었다.  R: 재생") % n))

## 왼손으로 물건을 집어 target 노드 위치로 가져간다 (target 바로 위 → 안으로)
func _hand_bring(obj: Node3D, target: Node3D) -> void:
	var arms := player.arms
	var start := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-20)), Vector3(-0.22, -0.42, -0.30))
	obj.top_level = true
	obj.global_transform = arms.global_transform * start
	var F := Vector3(0.35, 0.85, -0.4).normalized()
	var R := Vector3(0.0, 0.3, 1.0)
	R = (R - F * R.dot(F)).normalized()
	arms.attach_at("L", obj, start, start.origin - F * 0.12, F, R)
	var h: ViewmodelArms.Hand = arms.sides["L"]
	h.mode = ViewmodelArms.Mode.HOLD_OBJECT
	h.pose_want = "pinch"
	h.pos = arms.hold_pos_for(start, "L")
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var tgt := arms.global_transform.affine_inverse() * target.global_transform * Transform3D(Basis(), Vector3(0, 0.07, 0))
		arms.hold_object_at("L", start.interpolate_with(tgt, k), 30.0), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float):
		var tgt := arms.global_transform.affine_inverse() * target.global_transform * Transform3D(Basis(), Vector3(0, 0.07 * (1.0 - k) + 0.01 * k, 0))
		arms.hold_object_at("L", tgt, 40.0), 0.0, 1.0, 0.35)
	await tw.finished
	arms.detach("L")
	arms.set_mode("L", ViewmodelArms.Mode.HIDDEN)

func _play_tape() -> void:
	recorder_state = "playing"
	if player.held_recorder and _hands_on():
		player.arms.press_thumb("R")
	_notify("recorder_play", recorder_tape_no)
	_press("prop_recorder_btn_play", recorder, Vector3(0, 0, -0.003))
	Sounds.play_at("sfx_deck_button", recorder.global_position, &"SFX", -4.0, null, 0.0, "재생 버튼")
	motor.stream = Sounds.pick("amb_tape_motor")
	motor.play()
	# 요구사항 20: 재생 내내 깔리던 지지직(amb_tape_hiss) 반복을 없앤다 — 잡음은 PLAY 직후 짧게 한 번(tape_sequence)뿐, 릴 기계음(motor)만 남는다
	hiss.stop()
	_set_tape_audio_paused(false)
	# 테이프 음성 (VoiceTape 버스: 대역 제한·미세 왜곡) — 임시 TTS 가이드 음성
	if director == null:
		get_tree().create_timer(1.6, false).timeout.connect(func():
			if recorder_state == "playing":
				_play_line_at("PRO_E04_T01", recorder))

func _stop_tape() -> void:
	recorder_state = "loaded"
	if player.held_recorder and _hands_on():
		player.arms.press_thumb("R")
	_notify("recorder_stop")
	_press("prop_recorder_btn_stop", recorder, Vector3(0, 0, -0.003))
	Sounds.play_at("sfx_tape_stop", recorder.global_position, &"SFX", -4.0, null, 0.0, "정지 버튼")
	motor.stop()
	hiss.stop()
	_set_tape_audio_paused(true)          # 요구사항 20: 정지하면 테이프 속 소리(잡음·음성·놀이터 소리)도 함께 멈춘다 → 다시 재생하면 이어서

## 녹음기에서 나는 '테이프 속' 소리 (도입 잡음·음성·놀이터 소리) — 정지/재생에 맞춰 함께 멈추고 이어진다
func _tape_players() -> Array:
	var out: Array = []
	if recorder:
		for c in recorder.find_children("*", "AudioStreamPlayer3D", true, false):
			if c.has_meta(&"tuv_tape"):
				out.append(c)
	return out

func _set_tape_audio_paused(on: bool) -> void:
	for c in _tape_players():
		(c as AudioStreamPlayer3D).stream_paused = on

## 테이프 속 소리를 모두 끝낸다 (테이프를 꺼낼 때·공간 전환 때)
func stop_tape_audio() -> void:
	for c in _tape_players():
		(c as AudioStreamPlayer3D).stop()
		c.queue_free()

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
	if at == recorder:
		p.set_meta(&"tuv_tape", true)
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


# ======================================================================= 스토리 (프롤로그 EVENT 01~08)
func _hands_on() -> bool:
	return player != null and player.arms != null and player.arms.enabled and player.hands_animate

func _notify(sig: String, arg := "") -> void:
	if director:
		director.notify(sig, arg)

func _setup_story(mode: String) -> void:
	story_fx = PrologueStory.new()
	story_fx.name = "PrologueStory"
	story_fx.lvl = self
	add_child(story_fx)
	director = EventDirector.new()
	director.name = "EventDirector"
	director.story = story_fx
	director.player = player
	story_fx.director = director
	add_child(director)
	director.load_file("res://data/events/prologue_events.json")
	director.load_file("res://data/events/tape01_events.json")
	if OS.is_debug_build():
		var dbg := StoryDebugOverlay.new()
		dbg.lvl = self
		add_child(dbg)
	if mode == "new":
		ClueBook.reset()
	Inventory.item_added.connect(func(id):
		_notify("item:" + String(id))
		if id == &"note_prologue":
			ClueBook.add(&"clue_pro_memo")
		if id == &"flashlight":
			_notify("flashlight_pickup"))
	player.flashlight.toggled.connect(func(on): _notify("flashlight_on" if on else "flashlight_off"))
	player.inspect.opened.connect(func(t):
		_notify("inspect:" + t.inspect_title)
		if t.inspect_title == "운송장":
			ClueBook.add(&"clue_pro_waybill"))
	director.event_finished.connect(func(id): if id == "EV04_first_recording": ClueBook.add(&"clue_pro_tape01"))
	player.interacted_any.connect(func(): _notify("interact"))
	if clue_tape and mode == "new":
		clue_tape.visible = false
		var cit := clue_tape.find_child("Interact", true, false) as Interactable
		if cit:
			cit.enabled = false
	if parcel and mode == "new":
		parcel.visible = false
		var pit := parcel.find_child("ParcelInteract", false, false) as Interactable
		if pit:
			pit.enabled = false
		for c in parcel.find_children("*", "Interactable", true, false):
			(c as Interactable).enabled = false
	if OS.is_debug_build():
		debug_menu = load("res://scripts/ui/debug_menu.gd").new()
		debug_menu.lvl = self
		add_child(debug_menu)

## EVENT 02: 노크와 함께 문 앞에 택배가 놓인다
func show_parcel_at_door() -> void:
	if parcel == null or parcel_on_desk or parcel_carried:
		return
	parcel.visible = true
	for c in parcel.find_children("*", "Interactable", true, false):
		var it := c as Interactable
		it.enabled = it.name == "ParcelInteract" or it.inspect_title == "운송장"

func in_studio(p: Vector3) -> bool:
	return p.x > 0.05 and p.x < 5.95 and p.z < -0.05 and p.z > -4.95

func clamp_to_studio(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, 0.5, 5.5), p.y, clampf(p.z, -4.5, -0.5))

func door_inside_point() -> Vector3:
	return b2g(Vector3(0.95, 0.5, 1.1))

## 3D 위치에서 대사 재생 (등 뒤 목소리·문 너머 목소리). 자막은 DialogueDB 신호로.
func play_line_world(line_id: String, pos: Vector3, at_player := false, bus := "Voice") -> void:
	var stream := DialogueDB.audio_of(line_id)
	DialogueDB.line_started.emit(DialogueDB.get_line(line_id))
	if stream == null:
		return
	_duck_for(stream.get_length())
	if at_player:
		# 정우 독백은 한 번에 하나만 (겹치면 앞 대사를 짧게 줄이고 새 대사) — 요구사항 12 §8 중복 재생 방지
		if is_instance_valid(_jw_voice) and _jw_voice.playing:
			var old := _jw_voice
			var tw0 := create_tween()
			tw0.tween_property(old, "volume_db", -40.0, 0.15)
			tw0.tween_callback(old.queue_free)
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.bus = &"Voice"
		add_child(p2)
		p2.play()
		p2.finished.connect(p2.queue_free)
		_jw_voice = p2
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = StringName(bus) if AudioServer.get_bus_index(StringName(bus)) >= 0 else &"Voice"
	p.unit_size = 2.0
	p.max_db = 4.0
	p.volume_db = 1.0
	p.attenuation_filter_cutoff_hz = 9000.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func play_tape_sound(id: String, db: float, bus := &"VoiceTape") -> AudioStreamPlayer3D:
	var s := Sounds.pick(id)
	if s == null or recorder == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"SFX"
	p.unit_size = 1.5
	p.volume_db = db
	p.set_meta(&"tuv_tape", true)
	recorder.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p

## 조명 상태 문자열 → LightFixture
func set_light(name: String, st: String, instant := false) -> void:
	if not fx.has(name):
		return
	var f: LightFixture = fx[name]
	match st:
		"normal":
			f.switched_on = true
			f.set_state(LightFixture.State.NORMAL)
		"flicker":
			f.switched_on = true
			f.set_state(LightFixture.State.FLICKER)
		"flicker_once":
			if instant:
				return
			f._set_lit(false)
			get_tree().create_timer(0.09, false).timeout.connect(func(): f._set_lit(true, 0.6))
			get_tree().create_timer(0.16, false).timeout.connect(func(): f._set_lit(false))
			get_tree().create_timer(0.30, false).timeout.connect(func(): f._apply())
		"story_off":
			f.set_state(LightFixture.State.STORY_OFF)
		"dead":
			f.set_state(LightFixture.State.DEAD)
		"needs_power":
			f.set_state(LightFixture.State.NEEDS_POWER)
		"restore":
			f.set_state(LightFixture.State.NORMAL)

func set_rain(on: bool, fade: float) -> void:
	for e in rain_emitters:
		var em := e as AmbientEmitter
		if fade <= 0.0:
			em.playing = on
			continue
		if on and not em.playing:
			em.gain_db = -60.0
			em.play()
		var tw := create_tween()
		tw.tween_property(em, "gain_db", 0.0 if on else -60.0, fade)
		if not on:
			tw.tween_callback(em.stop)
	var r := find_child("Rain", false, false) as GPUParticles3D
	if r:
		r.emitting = on
	# 유리의 빗물은 남지만 흐름을 멈춘다
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m and m.shader == RAIN_GLASS:
			m.set_shader_parameter("rain_amount", 0.6 if on else 0.15)

func _find_monitor() -> void:
	if monitor_screen == null:
		monitor_screen = find_child("stu_monitor_screen", true, false) as MeshInstance3D
		if monitor_screen == null:
			var n := find_child("stu_monitor_screen", true, false)
			if n:
				for c in n.find_children("*", "MeshInstance3D", true, false):
					monitor_screen = c
					break
		if monitor_screen:
			_monitor_mat_orig = monitor_screen.material_override

func set_monitor_noise(on: bool) -> void:
	_find_monitor()
	if monitor_screen == null:
		return
	if on:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 g = floor(UV * vec2(320.0, 200.0));
	float n = h(g + floor(TIME * 30.0));
	float band = smoothstep(0.0, 0.08, abs(fract(UV.y * 3.0 - TIME * 0.7) - 0.5));
	ALBEDO = vec3(n * 0.55 * (0.6 + 0.4 * band));
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		monitor_screen.material_override = m
	else:
		monitor_screen.material_override = _monitor_mat_orig

func set_monitor_off() -> void:
	_find_monitor()
	if monitor_screen:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.015, 0.015, 0.017)
		m.roughness = 0.15
		monitor_screen.material_override = m

func set_pc_fan(on: bool) -> void:
	if pc_fan_emitter:
		if on:
			pc_fan_emitter.play()
		else:
			pc_fan_emitter.stop()

## ---- 택배: 두 손으로 들어 책상에 내려놓기
func _parcel_pick_up() -> void:
	if player.carrying or parcel == null:
		return
	parcel_carried = true
	var size := Interactable.local_aabb(parcel).size
	for c in parcel.find_children("*", "Interactable", true, false):
		(c as Interactable).enabled = false
	Sounds.play_at("sfx_cardboard_flap", parcel.global_position, &"SFX", -8.0)
	player.carrying = parcel
	player.carry_target_fn = _parcel_try_place
	if _hands_on():
		await player.arms.carry_begin(parcel, size)
	else:
		# 손 없이: 상자를 들어 품에 안은 것으로 처리 — 화면에 떠 있는 물체를 보이지 않는다 (요구사항 14)
		_set_parcel_carried_hidden(true)
	_notify("parcel_picked")
	if not _carry_tutorial_done:
		hud.show_toast("E 내려놓기", 3.0, true)     # 처음 한 번만 (튜토리얼)
		_carry_tutorial_done = true

func _desk_place_transform() -> Transform3D:
	# 책상 상판 오른쪽 빈 곳 (마우스 패드 오른쪽, 머그컵 앞). 상판 높이는 실제 규격 0.74 m
	# (정적 메시 병합 후 stu_desk 노드에는 서랍장만 남아 AABB로 높이를 구하면 상자가 책상에 파묻혔다 — 요구사항 12 QA에서 발견)
	var top: Vector3 = b2g(Vector3(3.86, 4.19, 0.741))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-12)), top)

func _parcel_try_place() -> void:
	if not player.carrying:
		return
	var t := _desk_place_transform()
	if player.global_position.distance_to(t.origin) > 1.7:
		hud.show_toast("책상 근처에서 내려놓자.", 2.0)
		return
	var size := Interactable.local_aabb(parcel).size
	if _hands_on():
		await player.arms.carry_end(t, size)
	else:
		parcel.top_level = true
		parcel.global_transform = t
		_set_parcel_carried_hidden(false)
	Sounds.play_at("sfx_cardboard_flap", t.origin, &"SFX", -6.0)
	player.carrying = null
	player.carry_target_fn = Callable()
	parcel_carried = false
	parcel_on_desk = true
	var pit := parcel.find_child("ParcelInteract", false, false) as Interactable
	if pit:
		pit.enabled = true
	for c in parcel.find_children("*", "Interactable", true, false):
		if (c as Interactable).inspect_title == "운송장":
			(c as Interactable).enabled = true
	_notify("parcel_placed")

## 두 손으로 테이프를 뜯고 덮개를 연다 (손 동작과 소리·덮개 애니메이션 동기화)
func _parcel_open_hands() -> void:
	if parcel_open or player.hands_busy:
		return
	player.hands_busy = true
	var seal := parcel.find_child("prop_parcel_seal_tape", true, false) as Node3D
	var p := seal.global_position if seal else parcel.global_position + Vector3(0, 0.25, 0)
	var fwd := (p - player.camera.global_position).normalized()
	await player.arms.reach("R", p + Vector3(0, 0.02, 0), (fwd + Vector3.DOWN).normalized(), -player.camera.global_transform.basis.x,
			"pinch", _parcel_open, 1.6, func(k: float) -> Vector3: return p + player.camera.global_transform.basis.x * (0.18 * k) + Vector3(0, 0.03 * k, 0))
	player.hands_busy = false

## ---- 녹음기: 오른손에 들고 R 키로 조작
func _pick_recorder() -> void:
	if recorder == null or player.held_recorder:
		return
	recorder.top_level = true
	player.held_recorder = recorder
	var it := recorder.find_child("RecorderInteract", false, false) as Interactable
	if it:
		it.enabled = false
	Sounds.play_at("sfx_pickup", recorder.global_position, &"SFX", -6.0)
	player.arms.hold_recorder(recorder)
	hud.show_toast("R 녹음기 (테이프 넣기 · 재생 · 정지)", 4.0, true)    # 처음 한 번 — 녹음기 조작 튜토리얼
	_schedule_recorder_lower(6.0)

## 플레이어 R 키
func recorder_key() -> void:
	if recorder == null:
		return
	if not _hands_on():
		# 요구사항 14: 녹음기는 책상 위에 둔 채 조작 (손에 들지 않음). R = 가까이 있을 때 녹음기 조작 단축키
		if recorder_state != "busy" and Vector2(recorder.global_position.x - player.global_position.x,
				recorder.global_position.z - player.global_position.z).length() <= player.interact_reach + 0.15:
			_recorder_use()
		return
	if not player.held_recorder and story:
		hud.show_toast("녹음기는 책상 위에 있다.", 2.0)
		return
	if player.hands_busy:
		return
	# 장비 상태: 내려 둔 녹음기는 먼저 꺼내 든 다음 조작한다 (요구사항 12 §3)
	if player.arms and player.arms.enabled and player.held_recorder and player.arms.is_lowered("R"):
		player.arms.raise_tool("R")
		await get_tree().create_timer(0.3, false).timeout
	_recorder_use()
	_schedule_recorder_lower()

var _rec_lower_token := 0
## 조작이 끝나고 몇 초 지나면 녹음기를 다시 내린다 (화면 중앙을 계속 가리지 않게)
func _schedule_recorder_lower(after := 4.0) -> void:
	_rec_lower_token += 1
	var tok := _rec_lower_token
	get_tree().create_timer(after, false).timeout.connect(func():
		if tok != _rec_lower_token or player.held_recorder == null or not player.arms or not player.arms.enabled:
			return
		if recorder_state == "busy" or player.hands_busy:
			_schedule_recorder_lower(1.5)
			return
		player.arms.lower_tool("R"))

func enter_apartment() -> void:
	if apt == null:
		apt = AptCorridor.new()
		apt.name = "AptCorridor1998"
		add_child(apt)
	in_apartment = true
	apt.enter(env)
	player.global_position = apt.point("apt_spawn") + Vector3(0, 0.05, 0)
	player.set("_yaw", apt.spawn_yaw)
	player.set("_pitch", 0.0)
	var z := {"aabb": apt.bounds(), "surface": "concrete"}
	if not player.footsteps.surface_zones.has(z):
		player.footsteps.surface_zones.append(z)
	set_rain(false, 0.0)
	set_world_quiet(0.0, 0.1)
	_space_mute(true)          # 요구사항 20: 작업실·상가 복도의 소리를 1998 공간으로 끌고 가지 않는다
	# 작업실·복도 조명은 이 공간과 무관 — 멀리 있으므로 그대로 둔다

## 공간 전환 때 이전 공간의 소리 정리: 반복음(환경음·형광등·녹음기 모터)은 멈춰 두었다가 돌아오면 다시, 원샷은 끊는다
var _muted_space: Array = []
func _space_mute(on: bool) -> void:
	if on:
		_muted_space.clear()
		if motor:
			motor.stop()
		if hiss:
			hiss.stop()
		stop_tape_audio()
		for c in find_children("*", "AudioStreamPlayer3D", true, false) + Sounds.find_children("*", "AudioStreamPlayer3D", true, false):
			var a := c as AudioStreamPlayer3D
			if apt and apt.is_ancestor_of(a):
				continue
			if not (a.playing or a.has_stream_playback()):
				continue
			if a.get_parent() is LightFixture:
				(a.get_parent() as LightFixture).muted = true
				_muted_space.append(a.get_parent())
			elif a is AmbientEmitter:
				a.stream_paused = true
				_muted_space.append(a)
			else:
				a.stop()
				if a.get_parent() == get_tree().current_scene or a.get_parent() == Sounds or a.get_parent() == self:
					a.queue_free()
		# 2D 원샷 (Sounds.play) 중 남은 것도 끊는다 — 호흡·심장·UI는 플레이어 몸/화면 소리라 유지
		for c in Sounds.get_children():
			if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing and String((c as AudioStreamPlayer).bus) in ["SFX", "Ambience", "Ghost", "VoiceTape"]:
				(c as AudioStreamPlayer).stop()
				c.queue_free()
	else:
		for a in _muted_space:
			if not is_instance_valid(a):
				continue
			if a is LightFixture:
				(a as LightFixture).muted = false
			else:
				(a as AudioStreamPlayer3D).stream_paused = false
		_muted_space.clear()


# ======================================================================= 요구사항 11 프롤로그 연출
func _character(path: String) -> Array:
	if not ResourceLoader.exists(path):
		return [null, null]
	var c := (load(path) as PackedScene).instantiate() as Node3D
	add_child(c)
	c.visible = false
	var sk := c.find_children("*", "Skeleton3D", true, false)
	var pz := CharacterPoser.new()
	c.add_child(pz)
	if not sk.is_empty():
		pz.setup(sk[0])
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).extra_cull_margin = 2.0
	return [c, pz]

func _monster() -> void:
	if monster_node == null:
		var r := _character("res://assets/models/characters/gst_prologue_monster.gltf")
		monster_node = r[0]
		monster_poser = r[1]
		if monster_poser:
			monster_poser.hunch = 1.0

func _soeun() -> void:
	if soeun_node == null:
		var r := _character("res://assets/models/characters/chr_soeun.gltf")
		soeun_node = r[0]
		soeun_poser = r[1]

## EVENT 01: 책상 의자에 앉아 작업하던 상태로 시작 → 헤드폰을 벗고 → 일어선다
var _chair_home: Transform3D
func _chair_bodies(on: bool) -> void:
	# 의자 충돌체는 의자 노드와 따로 익스포트됨 (stu_chair-colonly 등) → 이름으로 모두 찾는다
	for b in find_children("*", "CollisionObject3D", true, false):
		var nm := String(b.name) + "/" + String(b.get_parent().name)
		if nm.contains("stu_chair"):
			var co := b as CollisionObject3D
			co.set_meta("tuv_layer", co.get_meta("tuv_layer", co.collision_layer))
			co.collision_layer = co.get_meta("tuv_layer") if on else 0

func intro_seated() -> void:
	var chair := find_child("stu_chair", true, false) as Node3D
	var mon := find_child("stu_monitor_screen", true, false) as Node3D
	if chair == null or mon == null:
		return
	_chair_home = chair.global_transform
	_chair_bodies(false)
	var to_desk := Vector3(mon.global_position.x - chair.global_position.x, 0, mon.global_position.z - chair.global_position.z).normalized()
	# 의자 좌판 위(등받이보다 조금 앞) — 시선은 모니터
	player.global_position = Vector3(chair.global_position.x, 0.02, chair.global_position.z) + to_desk * 0.06
	player.set_seated(true)
	player.look_at_point(mon.global_position + Vector3(0, -0.05, 0))

func intro_headphones() -> void:
	if player.arms:
		player.arms.headphones_off()
	Sounds.play("sfx_pickup", &"SFX", -10.0)        # 헤드폰을 벗어 책상에 내려놓는 소리

## 일어서며 의자를 뒤로 민다 (바퀴 굴러가는 소리)
func intro_stand_up() -> void:
	var chair := find_child("stu_chair", true, false) as Node3D
	var mon := find_child("stu_monitor_screen", true, false) as Node3D
	player.set_seated(false)
	Sounds.play_at("sfx_chair_creak", player.global_position, &"SFX", -6.0)
	if chair == null or mon == null:
		return
	var to_desk := Vector3(mon.global_position.x - chair.global_position.x, 0, mon.global_position.z - chair.global_position.z).normalized()
	var side := to_desk.cross(Vector3.UP)
	var shift := -to_desk * 0.3 - side * 0.5        # 서랍장 반대쪽으로 밀어 서랍 앞을 막지 않게
	var col := find_child("stu_chair_col", true, false) as Node3D
	if col:
		col.global_position += shift        # 충돌은 꺼져 있는 동안 미리 옮겨 둔다
	var tw := create_tween().set_parallel()
	tw.tween_property(chair, "global_position", chair.global_position + shift, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(chair, "rotation:y", chair.rotation.y + deg_to_rad(25), 0.9)
	tw.chain().tween_callback(func(): _chair_bodies(true))

## 복도 끝 등 지정 위치에 괴물이 잠깐 서 있다 사라짐 (연출용 — 공격 없음)
func show_monster_at(where: String, secs: float) -> void:
	_monster()
	if monster_node == null:
		return
	monster_node.global_position = story_fx.point(where) + Vector3(0, -1.1, 0)
	monster_node.look_at(Vector3(player.global_position.x, monster_node.global_position.y, player.global_position.z), Vector3.UP, true)
	monster_poser.mode = "idle"
	monster_poser.head_raise = 0.15
	monster_node.visible = true
	await get_tree().create_timer(secs, false).timeout
	monster_node.visible = false

## EVENT 03: 녹음이 갑자기 끊긴다 (음성·도입부 소리만 멈추고 테이프는 계속 돈다 → 플레이어가 정지)
func tape_cut() -> void:
	if recorder == null:
		return
	for c in recorder.find_children("*", "AudioStreamPlayer3D", true, false):
		var a := c as AudioStreamPlayer3D
		if a != motor and a != hiss and a.playing and a.bus == &"VoiceTape":
			a.stop()
	Sounds.play_at("sfx_tape_stop", recorder.global_position, &"SFX", -14.0)
	hiss.base_volume_db = -12.0

## EVENT 04: 문이 조금씩 열린다
var door_ajar := false
func door_creep(deg: float, secs: float) -> void:
	if door_hinge == null:
		return
	# 문이 열려 있었다면 스스로 닫히다가 틈만 남기고 멈춘다
	door_open = false
	door_ajar = true
	var tw := create_tween()
	tw.tween_property(door_hinge, "rotation:y", deg_to_rad(deg), secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func door_gap_point() -> Vector3:
	return door_hinge.global_transform * Vector3(0.88, 1.45, 0.0) if door_hinge else Vector3.ZERO

## 문틈 너머(복도)에서 무언가가 바라본다 — 긴 손가락이 문 모서리에, 머리카락 사이 얼굴
func presence_in_gap(on: bool) -> void:
	_monster()
	if monster_node == null:
		return
	if on:
		# 문은 안쪽으로 열린다 → 틈은 문짝 끝과 걸쇠 쪽 문틀 사이. 그 바로 바깥(복도)에 선다
		var outside: Vector3 = b2g(Vector3(0.95, -0.5, 0.0))
		monster_node.global_position = Vector3(door_hinge.global_position.x + 0.78, 0.0, outside.z)
		monster_node.look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
		monster_poser.mode = "peek"
		monster_poser.head_raise = 0.7
	monster_node.visible = on

func door_slam_presence() -> void:
	if door_hinge:
		var tw := create_tween()
		tw.tween_property(door_hinge, "rotation:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	door_ajar = false
	door_open = false
	get_tree().create_timer(0.18, false).timeout.connect(func():
		Sounds.play_at("sfx_door_bang", door_inside_point(), &"SFX", 2.0, null, 0.0, "문이 쾅 닫히는 소리")
		if monster_node:
			monster_node.visible = false
		player.camera_kick(0.5))

## EVENT 05: 정지한 녹음기가 혼자 돈다 — 손에 들고 있었다면, 돌아본 사이 녹음기는 손에서 사라져 책상 위에서 돌고 있다
var _rec_home: Transform3D
func recorder_self(on: bool, instant: bool) -> void:
	_self_play = on
	if recorder == null:
		return
	if on and player.held_recorder == recorder:
		player.arms.detach("R")
		player.arms.set_mode("R", ViewmodelArms.Mode.HIDDEN)
		player.arms.restore_world_materials(recorder)
		player.held_recorder = null
		recorder.global_transform = _rec_home
		var rit := recorder.find_child("RecorderInteract", false, false) as Interactable
		if rit:
			rit.enabled = true
	if on and not instant:
		motor.stream = Sounds.pick("amb_tape_motor")
		motor.base_volume_db = -18.0
		motor.play()
	elif not on:
		motor.stop()

## 시야 밖에서만 바뀌는 물건 (플레이어 눈앞에서 순간이동하지 않게)
func offsight_change(what: String, instant: bool) -> void:
	var target: Node3D = null
	match what:
		"chair_turn":
			target = find_child("stu_chair", true, false) as Node3D
		"tape_vanish":
			target = parcel.find_child("prop_tape_4", true, false) as Node3D if parcel else null
	if target == null:
		return
	if not instant:
		var cam := player.camera
		var el := 0.0
		while el < 120.0:
			await get_tree().create_timer(0.2, false).timeout
			el += 0.2
			var seen := cam.is_position_in_frustum(target.global_position) and \
					(-cam.global_transform.basis.z).angle_to((target.global_position - cam.global_position).normalized()) < deg_to_rad(55)
			if not seen:
				break
	match what:
		"chair_turn":
			target.rotation.y += deg_to_rad(150)
			if not instant:
				Sounds.play_at("sfx_chair_creak", target.global_position, &"SFX", -14.0)
		"tape_vanish":
			target.visible = false
			var it := target.find_child("Interact", true, false) as Interactable
			if it:
				it.enabled = false

## EVENT 06→07: 사라진 테이프가 책상 아래 어둠 속에 있다
func show_under_desk_tape() -> void:
	if clue_tape:
		clue_tape.visible = true
		var it := clue_tape.find_child("Interact", true, false) as Interactable
		if it:
			it.enabled = true

## EVENT 07: 테이프를 집는 순간 책상 반대편에서 소은의 얼굴이 나타났다 사라진다 (공격 없음, 1회)
func soeun_peek(secs: float) -> void:
	_soeun()
	if soeun_node == null or clue_tape == null:
		return
	var cam := player.camera
	var tp := clue_tape.global_position
	var away := Vector3(tp.x - cam.global_position.x, 0, tp.z - cam.global_position.z).normalized()
	soeun_node.global_position = Vector3(tp.x, 0.0, tp.z) + away * 0.55
	soeun_node.look_at(Vector3(cam.global_position.x, 0.0, cam.global_position.z), Vector3.UP, true)
	soeun_poser.mode = "peek"
	soeun_node.scale = Vector3.ONE
	soeun_node.visible = true
	# 조사 패널이 얼굴을 가리지 않도록 등장하는 동안 숨긴다
	if hud and hud.inspect_panel:
		hud.inspect_panel.modulate.a = 0.0
	await get_tree().create_timer(secs, false).timeout
	if hud and hud.inspect_panel:
		var tw := create_tween()
		tw.tween_property(hud.inspect_panel, "modulate:a", 1.0, 0.6)
	# 손전등이 한 번 끊기는 사이에 사라진다
	player.flashlight.spot.visible = false
	soeun_node.visible = false
	await get_tree().create_timer(0.12, false).timeout
	player.flashlight.spot.visible = player.flashlight.is_on

## EVENT 08: 문 밖 괴물
func monster_breath_door(on: bool) -> void:
	if on:
		if _mon_breath == null:
			_mon_breath = AmbientEmitter.new()
			_mon_breath.sound_id = "mon_breath"
			_mon_breath.base_volume_db = -4.0
			_mon_breath.unit_size = 2.0
			_mon_breath.bus = &"SFX"
			add_child(_mon_breath)
			_mon_breath.global_position = story_fx.point("door_outside")
		_mon_breath.play()
	elif _mon_breath:
		_mon_breath.stop()

func door_handle_rattle() -> void:
	Sounds.play_at("sfx_handle_rattle", door_inside_point(), &"SFX", -2.0, null, 0.0, "문손잡이가 덜컥거리는 소리")
	var lev := door_hinge.find_child("stu_door_lever_in", true, false) as Node3D if door_hinge else null
	if lev:
		var r0 := lev.rotation.z
		var tw := create_tween()
		for k in 4:
			tw.tween_property(lev, "rotation:z", r0 - deg_to_rad(28), 0.07)
			tw.tween_property(lev, "rotation:z", r0, 0.09)

func door_bang(strength: float) -> void:
	Sounds.play_at("sfx_door_bang", door_inside_point(), &"SFX", -4.0 + 5.0 * strength, null, 0.02, "철문을 세게 치는 소리")
	if door_hinge:
		var tw := create_tween()
		tw.tween_property(door_hinge, "rotation:y", deg_to_rad(1.4 * strength), 0.05)
		tw.tween_property(door_hinge, "rotation:y", deg_to_rad(-0.4 * strength), 0.08)
		tw.tween_property(door_hinge, "rotation:y", 0.0, 0.12)
	player.camera_kick(0.35 * strength)
	if player.arms:
		player.arms.flinch(0.5 * strength, 0.25)

## 모든 소리가 갑자기 멈춘다 (환경음 버스를 잠깐 끊었다가 천천히 복구)
func sudden_silence(secs: float) -> void:
	var idx := AudioServer.get_bus_index(&"Ambience")
	if idx < 0:
		return
	var base := AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, -60.0)
	await get_tree().create_timer(secs, false).timeout
	var tw := create_tween()
	tw.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), -60.0, base, 2.5)


# ======================================================================= 조명 상태 (요구사항 12)
## normal 정상 점등 · partial 부분 소등 · broken 조명 고장(스위치 무반응) · blackout 완전 정전
## · emergency 비상등(붉은 조명만). 손전등과 초자연 깜빡임은 Flashlight가 따로 담당한다.
## 화면 필터가 아니라 실제 3D 조명·환경광·GI·반사·발광 재질을 바꾼다.
const LIGHTING_STATES := ["normal", "partial", "broken", "blackout", "emergency"]

func _collect_emissives() -> void:
	if not _emissive_mats.is_empty() or stu == null:
		return
	var seen := {}
	for n in stu.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled and not seen.has(m):
				seen[m] = true
				_emissive_mats.append([m, (m as BaseMaterial3D).emission_energy_multiplier])

func _ensure_emergency() -> void:
	if emergency_light:
		return
	# 출입문 위 비상등 (배터리식, 정전 시 붉게 점등)
	var pos: Vector3 = b2g(Vector3(0.95, 0.12, 2.32))
	_emergency_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.07, 0.06)
	_emergency_mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.04, 0.03)
	m.emission = Color(1.0, 0.08, 0.04)
	m.emission_energy_multiplier = 0.0
	m.emission_enabled = true
	m.roughness = 0.4
	_emergency_mesh.material_override = m
	add_child(_emergency_mesh)
	_emergency_mesh.global_position = pos
	emergency_light = OmniLight3D.new()
	emergency_light.light_color = Color(1.0, 0.12, 0.06)
	emergency_light.light_energy = 0.0
	emergency_light.omni_range = 5.5
	emergency_light.omni_attenuation = 1.6
	emergency_light.shadow_enabled = true
	emergency_light.visible = false
	add_child(emergency_light)
	emergency_light.global_position = pos + Vector3(0, -0.08, -0.12)

func set_lighting(st: String, instant := false) -> void:
	if not LIGHTING_STATES.has(st):
		return
	_collect_emissives()
	_ensure_emergency()
	lighting = st
	var studio_fixtures := ["StudioCeiling", "DeskLamp", "FloorLamp"]
	var powered := st == "normal" or st == "partial"
	match st:
		"normal":
			for n in studio_fixtures:
				set_light(n, "restore", instant)
			if fx.has("StudioCeiling"):
				fx["StudioCeiling"].switched_on = true
				fx["StudioCeiling"]._apply()
		"partial":
			set_light("StudioCeiling", "story_off", instant)
			set_light("FloorLamp", "story_off", instant)
			set_light("DeskLamp", "restore", instant)
		"broken":
			set_light("StudioCeiling", "dead", instant)
			set_light("FloorLamp", "story_off", instant)
			set_light("DeskLamp", "restore", instant)
		"blackout", "emergency":
			for n in studio_fixtures:
				set_light(n, "story_off", instant)
	# 요구사항 17 §08: 정전은 같은 층 전체 — 복도·계단 형광등도 함께 꺼지고 비상구 표지만 독립 전원으로 아주 희미하게
	var cor_dark := st == "blackout" or st == "emergency"
	for i in 6:
		if cor_dark:
			set_light("CorLight%d" % i, "story_off", instant)
		elif st == "normal" and fx.has("CorLight%d" % i) and fx["CorLight%d" % i].state == LightFixture.State.STORY_OFF:
			set_light("CorLight%d" % i, "normal", instant)
	for n in ["StairUp"]:
		if cor_dark:
			set_light(n, "story_off", instant)
	_corridor_emissive(0.12 if cor_dark else 1.0)
	if exit_glow:
		exit_glow.light_energy = 0.03 if cor_dark else 0.25
		exit_glow.omni_range = 1.0 if cor_dark else 2.2
	# 모니터·전자기기 발광 (정전이면 전부 꺼짐)
	var devices_on := powered or st == "broken"
	if monitor_light:
		monitor_light.visible = devices_on
	for e in _emissive_mats:
		(e[0] as BaseMaterial3D).emission_energy_multiplier = float(e[1]) if devices_on else 0.0
	if not devices_on:
		set_monitor_off()
	# 창밖 도시광: 정전 시 블록 전체가 꺼진 것처럼 거의 남기지 않는다 (먼 건물 몇 개만)
	var dark := st == "blackout" or st == "emergency"
	window_base_energy = WINDOW_ENERGY * (0.06 if dark else 1.0)
	if window_light:
		window_light.light_energy = window_base_energy
		window_light.shadow_enabled = not dark
	if city_mat:
		city_mat.set_shader_parameter("energy", 0.35 if dark else 1.6)
		city_mat.set_shader_parameter("lit_ratio", 0.08 if dark else 0.28)
	# 환경광·GI·반사: 잔여 광원 제거 (자동 노출은 사용하지 않음 — 노출 고정)
	if env:
		env.ambient_light_energy = 0.0 if dark else (0.05 if st != "normal" else 0.08)
		env.ambient_light_color = Color(0.36, 0.40, 0.48)
		env.sdfgi_energy = 0.55 if dark else 1.25
		env.ssil_intensity = 0.25 if dark else 0.6
		env.glow_intensity = 0.2 if dark else 0.35
		env.glow_hdr_threshold = 2.2 if dark else 1.2      # 손전등이 비춘 벽에 블룸이 번지지 않게 (요구사항 17 §09)
		env.tonemap_exposure = 1.15
	for rp in probes:
		rp.intensity = 0.03 if dark else 1.0
	# 비상등
	var em := st == "emergency"
	emergency_light.visible = em
	emergency_light.light_energy = 0.9 if em else 0.0
	(_emergency_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 2.5 if em else 0.0


## 정전·비상등 상태에서 그 지점이 실제로 빛을 받아 보이는가 (요구사항 13: 보이는 물건만 상호작용 아이콘)
func point_lit(pt: Vector3) -> bool:
	if lighting != "blackout" and lighting != "emergency":
		return true
	if in_apartment:
		return true                     # 1998 아파트는 정전과 무관
	var fl: Flashlight = player.flashlight
	if fl and fl.is_on and fl.spot.visible:
		var sp := fl.spot.global_position
		var dir := -fl.spot.global_transform.basis.z
		var to := pt - sp
		if to.length() < fl.spot.spot_range * 0.6 and rad_to_deg(dir.angle_to(to.normalized())) < fl.spot.spot_angle * 0.95 and _clear(sp, pt):
			return true
	if lighting == "emergency" and emergency_light and emergency_light.global_position.distance_to(pt) < 3.2 and _clear(emergency_light.global_position, pt):
		return true
	# P0: 손전등을 얻기 전에는 서랍·손전등 자체를 어둠 때문에 조작 못 하는 일이 없게 (요구사항 13 '첫 손전등은 어둠에 막히지 않음')
	if not Inventory.has_flashlight:
		var dr := find_child("stu_desk_drawer_0", true, false) as Node3D
		if dr and dr.global_position.distance_to(pt) < 0.9:
			return true
	# 손전등을 찾기 전 안내광 (서랍 주변만 희미하게 보인다)
	if story_fx and story_fx._guide and story_fx._guide.light_energy > 0.05 and story_fx._guide.global_position.distance_to(pt) < 1.1:
		return true
	return false

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(b) < 0.3


var _parcel_layers := {}
func _set_parcel_carried_hidden(on: bool) -> void:
	parcel.visible = not on
	for c in parcel.find_children("*", "CollisionObject3D", true, false):
		var co := c as CollisionObject3D
		if co is Interactable:
			continue
		if on:
			_parcel_layers[co] = co.collision_layer
			co.collision_layer = 0
		elif _parcel_layers.has(co):
			co.collision_layer = _parcel_layers[co]


var _cam_attr: CameraAttributesPractical
func _inspect_view(on: bool) -> void:
	if _cam_attr == null:
		_cam_attr = CameraAttributesPractical.new()
		_cam_attr.dof_blur_far_distance = 0.55
		_cam_attr.dof_blur_far_transition = 0.35
		_cam_attr.dof_blur_amount = 0.0
		player.camera.attributes = _cam_attr
	_cam_attr.dof_blur_far_enabled = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_cam_attr, "dof_blur_amount", 0.14 if on else 0.0, 0.35)
	if env:
		tw.tween_property(env, "adjustment_brightness", GameSettings.brightness * (0.45 if on else 1.0), 0.35)
	if not on:
		tw.chain().tween_callback(func(): _cam_attr.dof_blur_far_enabled = false)


var _jw_voice: AudioStreamPlayer
var _duck_tw: Tween
var _duck_fx := {}
## 대사가 효과음·환경음에 묻히지 않게 잠깐 낮춘다 (대사 길이 동안 -5 dB).
## 설정의 버스 볼륨과 겹치지 않도록 버스에 증폭 이펙트를 하나 붙여 그것만 조절한다.
func _duck_for(secs: float) -> void:
	for bus in [&"Ambience", &"SFX"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0 or _duck_fx.has(bus):
			continue
		var amp := AudioEffectAmplify.new()
		AudioServer.add_bus_effect(idx, amp)
		_duck_fx[bus] = amp
	if _duck_tw:
		_duck_tw.kill()
	_duck_tw = create_tween()
	_duck_tw.tween_method(_set_duck, 0.0, 1.0, 0.2)
	_duck_tw.tween_interval(maxf(secs - 0.1, 0.3))
	_duck_tw.tween_method(_set_duck, 1.0, 0.0, 0.5)

func _set_duck(k: float) -> void:
	for bus in _duck_fx:
		(_duck_fx[bus] as AudioEffectAmplify).volume_db = -5.0 * k

func _exit_tree() -> void:
	# 레벨 재시작 시 버스 이펙트가 쌓이지 않게 제거
	for bus in _duck_fx:
		var idx := AudioServer.get_bus_index(bus)
		for i in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
			if AudioServer.get_bus_effect(idx, i) == _duck_fx[bus]:
				AudioServer.remove_bus_effect(idx, i)


# ======================================================================= 요구사항 16: 테이프 순서 · 작업실 복귀 · 사진
var tapes_done: Array[String] = []
var in_apartment := false
var photo: Node3D
const PHOTO_TEX := "res://assets/textures/apt/apt_tape01_photo.jpg"

## 다음에 들어야 할 테이프 번호 (1부터 순서대로)
func next_tape() -> int:
	for n in range(1, 8):
		if not tapes_done.has(str(n)):
			return n
	return 8

func mark_tape_finished(n: String) -> void:
	if not tapes_done.has(n):
		tapes_done.append(n)
	_refresh_box_tapes()

## 상자 안 테이프의 '가져가기' 가능 여부를 다음 차례에 맞춘다
func _refresh_box_tapes() -> void:
	if parcel == null:
		return
	for it in parcel.find_children("*", "Interactable", true, false):
		var i := it as Interactable
		if i.has_meta("tape_no"):
			var n := int(i.get_meta("tape_no"))
			var mine := n == next_tape() and recorder_tape_no != str(n)
			i.pickup_item = StringName("tape_%d" % n) if mine else &""
			i.prompt = ("TAPE 0%d" % n)

## 다 들은 테이프를 꺼내 상자의 제자리에 돌려놓는다
func _eject_tape() -> void:
	if recorder_tape == null:
		return
	recorder_state = "busy"
	var n := recorder_tape_no
	var door := recorder.find_child("prop_recorder_door", true, false) as Node3D
	var d0 := door.rotation.x if door else 0.0
	Sounds.play_at("sfx_cassette_door", recorder.global_position, &"SFX", -4.0, null, 0.0, "녹음기 덮개 여는 소리")
	var tw := create_tween()
	if door:
		tw.tween_property(door, "rotation:x", d0 - deg_to_rad(55), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(recorder_tape, "position", Vector3(0, 0.08, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		# 꺼낸 테이프는 상자의 원래 칸으로 (빌드 스크립트 build_props.py와 같은 배치: 한 줄에 4개)
		var tp := recorder_tape
		recorder_tape = null
		if parcel:
			var i := int(n) - 1
			var local := Vector3(-0.162 + (i % 4) * 0.108, 0.060, -(0.052 - (i / 4) * 0.100))
			tp.get_parent().remove_child(tp)
			parcel.add_child(tp)
			tp.transform = Transform3D(Basis(), local)
			var it := Interactable.attach_to(tp, "TAPE 0%s" % n, 0.006, 0.03)
			it.inspectable = true
			it.inspect_visual = tp
			it.inspect_title = tr("카세트테이프 %s번") % n
			it.inspect_text = ""
			it.set_meta("tape_no", int(n))
			Sounds.play_at("sfx_cassette_insert", parcel.global_position, &"SFX", -10.0, null, 0.0, "테이프를 상자에 넣는 소리")
		else:
			tp.queue_free())
	if door:
		tw.tween_property(door, "rotation:x", d0, 0.22)
	tw.tween_callback(func():
		recorder_state = "empty"
		recorder_tape_no = ""
		_refresh_box_tapes()
		_notify("tape_ejected", n))

## 소은의 목소리가 끝나는 순간 철제 출입문이 세게 닫힌다 (요구사항 17 §06)
## 문짝이 0.22초에 닫히고, 쾅 소리의 충격 지점(파일 0.14초)이 정확히 그 프레임에 오도록 미리 재생 → 이어서 잠금 '철컥'
func slam_door_story() -> void:
	if door_hinge == null:
		return
	var at := door_inside_point() + Vector3(0, 0.9, 0)
	const CLOSE_T := 0.22
	var impact: float = float(Sounds.meta("sfx_door_slam").get("impact_at", 0.14))
	if door_open:
		door_open = false
		door_busy = true
		var tw := create_tween()
		tw.tween_property(door_hinge, "rotation:y", 0.0, CLOSE_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			door_busy = false
			player.camera_kick(0.35))
		get_tree().create_timer(maxf(CLOSE_T - impact, 0.0), false).timeout.connect(func():
			_door_sfx("sfx_door_slam", at, -2.5, "쾅!"))
	else:
		# 이미 닫혀 있었다면 문짝이 문틀에 한 번 세게 부딪힌다
		var r0 := door_hinge.rotation.y
		var tw := create_tween()
		tw.tween_property(door_hinge, "rotation:y", r0 + deg_to_rad(2.0), 0.06)
		tw.tween_property(door_hinge, "rotation:y", r0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		get_tree().create_timer(maxf(0.14 - impact, 0.0), false).timeout.connect(func():
			_door_sfx("sfx_door_slam", at, -3.0, "쾅!"))
	get_tree().create_timer(CLOSE_T + 0.16, false).timeout.connect(func():
		_door_sfx("sfx_latch", at + Vector3(0.35, -0.2, 0), -4.0, "철컥"))

## 문 효과음: 잔향 구역을 거치지 않고(과한 잔향 방지) 문 위치에서 3D 재생
func _door_sfx(id: String, at: Vector3, db: float, cap := "") -> AudioStreamPlayer3D:
	var p := Sounds.play_at(id, at, &"SFX", db, null, 0.02, cap, 3.0)
	if p:
		p.area_mask = 0
	return p

## 노크 3회 (요구사항 17 §02): 같은 음원을 기계적으로 반복하지 않게 매번 다른 타격·강도·간격.
## normal = 초반 평범한 사람의 노크(짧고 묵직), late = 후반 초자연적인 노크(느리고 낮게 눌림).
## 방 안에서 문이 닫혀 있으면 문 너머 소리처럼 고음이 깎이고, 복도에서는 또렷하다.
func knock(style := "normal", count := 3) -> void:
	var pos := b2g(Vector3(0.95, -0.12, 1.3))
	var id := "sfx_knock_hit" if style == "normal" else "sfx_knock_late_hit"
	var gaps := [0.0, randf_range(0.31, 0.37), randf_range(0.33, 0.41)] if style == "normal" else [0.0, randf_range(0.7, 0.85), randf_range(0.8, 1.0)]
	var gains := [randf_range(-1.5, 0.0), randf_range(0.0, 1.0), randf_range(-2.5, -0.5)]
	for i in count:
		if i > 0:
			await get_tree().create_timer(gaps[mini(i, 2)], false).timeout
		var inside := in_studio(player.camera.global_position) and not door_open
		var p := _door_sfx(id, pos, gains[mini(i, 2)] + (2.0 if style == "normal" else -2.0), ("똑. 똑. 똑." if style == "normal" else "...똑. ...똑. ...똑.") if i == 0 else "")
		if p:
			p.attenuation_filter_cutoff_hz = 2200.0 if inside else 9000.0
			p.pitch_scale = randf_range(0.97, 1.03)

## 방 안의 생활 소음(시계·빗소리·환경음)을 줄인다 — '조용해짐' (요구사항 16 EVENT 05)
func set_world_quiet(db: float, fade: float) -> void:
	var idx := AudioServer.get_bus_index(&"Ambience")
	if idx < 0:
		return
	if not has_meta("amb_base_db"):
		set_meta("amb_base_db", AudioServer.get_bus_volume_db(idx))
	var base: float = get_meta("amb_base_db")
	var tw := create_tween()
	tw.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), AudioServer.get_bus_volume_db(idx), base + db, fade)

## TAPE 01이 끝나면 작업실 책상 앞(녹음기 앞)으로 돌아온다 — 1998년에서 돌아온 직후
func return_to_studio(instant: bool) -> void:
	if apt:
		apt.leave(env)
	in_apartment = false
	_space_mute(false)
	set_lighting("partial", true)          # 책상 스탠드만 켜져 있다 (Q-14 임시 결정)
	set_world_quiet(-6.0, 0.1)
	slam_door(true)
	door_locked = true
	if recorder and recorder_state == "playing":
		recorder_state = "loaded"
		motor.stop()
		hiss.stop()
	stop_tape_audio()
	if recorder:
		var to_desk := recorder.global_position
		var front := b2g(Vector3(3.55, 3.45, 0.0))     # 책상 앞 (의자 옆), 녹음기를 내려다보는 자리
		player.global_position = Vector3(front.x, 0.05, front.z)
		player.look_at_point(to_desk + Vector3(0, -0.05, 0))
	player.flashlight.blocked = false
	if player.flashlight.is_on:
		player.flashlight.set_on(false)

## 책상 위, 녹음기 옆에 놓인 사진 (TAPE 01 이후)
func show_photo(instant := false) -> void:
	if photo == null:
		photo = MeshInstance3D.new()
		photo.name = "prop_photo_tape01"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.127, 0.0012, 0.089)
		(photo as MeshInstance3D).mesh = bm
		var back := StandardMaterial3D.new()
		back.albedo_color = Color(0.93, 0.92, 0.88)       # 인화지 뒷면
		back.roughness = 0.8
		(photo as MeshInstance3D).material_override = back
		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.127, 0.089)
		face.mesh = qm
		var front := StandardMaterial3D.new()
		front.roughness = 0.3                             # 광택 인화지
		front.albedo_color = Color(0.5, 0.45, 0.4)
		if ResourceLoader.exists(PHOTO_TEX):
			front.albedo_texture = load(PHOTO_TEX)
			front.albedo_color = Color.WHITE
		face.material_override = front
		photo.add_child(face)
		face.position = Vector3(0, 0.00065, 0)
		face.rotation_degrees = Vector3(-90, 0, 0)
		add_child(photo)
		# 키보드 위에 놓여 있다 — 정우가 앉으면 바로 손이 닿는 자리 (책상 위 다른 물건과 겹치지 않음, 놓칠 수 없는 위치)
		var kb := b2g(Vector3(2.93, 4.2, 0.74 + 0.0235))
		photo.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-7)) * Basis(Vector3.RIGHT, deg_to_rad(1.5)), kb)
		var it := Interactable.attach_to(photo, "사진", 0.01, 0.06)
		it.inspectable = true
		it.inspect_visual = photo
		it.inspect_title = "사진"
		it.inspect_text = ""
	photo.visible = true


## 복도 발광 재질 (형광등 관·비상구 표지·엘리베이터 층 표시·버튼 LED): 정전 땐 비상구 표지만 아주 희미하게 남는다
func _corridor_emissive(k: float) -> void:
	if cor == null:
		return
	if _cor_emissive.is_empty():
		var seen := {}
		for n in cor.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled and not seen.has(m) and not m.resource_name.contains("fluorescent"):
					seen[m] = true
					_cor_emissive.append([m, (m as BaseMaterial3D).emission_energy_multiplier])
	for e in _cor_emissive:
		var keep: float = k if String((e[0] as Material).resource_name).contains("exit") else (0.0 if k < 1.0 else 1.0)
		(e[0] as BaseMaterial3D).emission_energy_multiplier = float(e[1]) * keep

## 요구사항 20 진행 안전장치: 녹음 도중 멈춘 채 오래 두면 녹음기가 스스로 다시 돈다 (재생 버튼이 내려가는 소리)
func recorder_resume_by_itself() -> void:
	if recorder == null or recorder_state != "loaded":
		return
	_play_tape()

## 진행 안전장치 (P0 2026-11-27): 플레이어가 녹음기를 멈추지 않아도 테이프가 끝나 스스로 멈춘다 — 정지 버튼이 튀어 오르고 철컥
func recorder_autostop() -> void:
	if recorder == null or recorder_state != "playing":
		return
	recorder_state = "loaded"
	_press("prop_recorder_btn_stop", recorder, Vector3(0, 0, -0.003))
	Sounds.play_at("sfx_tape_stop", recorder.global_position, &"SFX", -2.0, null, 0.0, "철컥 — 테이프가 끝나 멈추는 소리")
	motor.stop()
	hiss.stop()
	stop_tape_audio()
	_notify("recorder_stop")
