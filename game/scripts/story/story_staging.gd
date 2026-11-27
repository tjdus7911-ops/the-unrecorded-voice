class_name StoryStaging
extends Node
## 요구사항 16 연출 담당: EVENT 07~10 (복도 · 소은 · 소음 실루엣 괴물 · 따라오는 발소리 · 순차 소등)과 TAPE 01 (1998 아파트).
## PrologueStory.do_action 이 여기로 위임한다. 공격 없음 — 모든 존재는 연출용.
## 원칙: 캐릭터는 플레이어가 보고 있는 동안 생기거나 사라지지 않는다 (조명이 꺼진 순간·시야 밖에서만 바뀐다).

var lvl: Node3D
var story: Node

# --- 복도 (Blender 좌표 기준: 복도 x -5~13, y -2.0~-0.2, 작업실 문 x≈0.95, 기둥 x -1.35)
const COR_LIGHT_X := [-3.5, -0.5, 2.5, 5.5, 8.5, 11.5]
const SOEUN_COR := Vector3(12.15, -1.25, 0.0)
const NOISE_PEEK := Vector3(-1.84, -0.42, 0.0)    ## 기둥(x -1.58~-1.12, y -0.2~-0.84) 서쪽 뒤
const NOISE_HIDE := Vector3(-2.1, -0.38, 0.0)
const NOISE_LEAN := 9.0
var soeun_placed := false
var soeun_gone := false
var monster_state := ""          ## "" → placed → peeking → hiding → gone
var noise: Node3D
var noise_poser: CharacterPoser
var _noise_tape_mat: ShaderMaterial
var _noise_upright := Basis()
var follower_on := false
var follow_dist := 7.5
var _step_t := 0.0
var _foll_pos := Vector3.ZERO
var chase_on := false
var _chase_next := 0
var _glitch: ColorRect
var fragments := 0               ## TAPE 01 녹음 조각 (0~3)

func _ready() -> void:
	set_process(true)

func b2g(v: Vector3) -> Vector3:
	return lvl.b2g(v)

## Godot → Blender (복도 판정용)
func g2b(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y)

func in_corridor(p: Vector3) -> bool:
	var q := g2b(p)
	return q.x > -5.0 and q.x < 13.2 and q.y > -2.05 and q.y < -0.15

func point(name: String) -> Vector3:
	match name:
		"soeun_corridor":
			return b2g(SOEUN_COR) + Vector3(0, 1.0, 0)
		"monster_corner":
			if noise and noise.visible:
				return _noise_head()
			return b2g(Vector3(-1.2, -0.75, 1.75))
		"ear":
			var cam: Camera3D = lvl.player.camera
			return cam.global_position + cam.global_transform.basis.x * 0.22 + cam.global_transform.basis.z * 0.05
		"parcel":
			return lvl.parcel.global_position if lvl.parcel else Vector3.ZERO
		"photo":
			return lvl.photo.global_position if lvl.get("photo") else Vector3.ZERO
		"apt_soeun_end_head":
			if lvl.apt and lvl.apt.soeun:
				return lvl.apt.soeun.global_position + Vector3(0, 1.0, 0)
			return Vector3.ZERO
	if lvl.apt and name.begins_with("apt_"):
		return lvl.apt.point(name)
	return Vector3.INF

func check(cond: String) -> Variant:
	var p: Vector3 = lvl.player.global_position
	match cond:
		"door_open":
			return lvl.door_open
		"player_in_corridor":
			return in_corridor(p)
		"monster_hidden":
			return monster_state == "gone"
		"player_heading_east":
			return in_corridor(p) and g2b(p).x > 2.3
		"reached_corridor_end":
			return in_corridor(p) and g2b(p).x > 11.0
		"apt_soeun_visible":
			return lvl.apt != null and lvl.apt.soeun != null and lvl.apt.soeun.visible
		"in_apartment":
			return lvl.apt != null and lvl.apt.bounds().has_point(p)
	return null

# =========================================================== EVENT 07~08 소은
func place_soeun_corridor(instant: bool) -> void:
	lvl._soeun()
	var s: Node3D = lvl.soeun_node
	if s == null or soeun_gone:
		return
	var at := b2g(SOEUN_COR)
	s.global_position = at
	# 등을 돌리고 복도 끝(동쪽)을 바라본다
	s.look_at(at + Vector3(1, 0, 0.15), Vector3.UP, true)
	if lvl.soeun_poser:
		lvl.soeun_poser.mode = "idle"
		lvl.soeun_poser.head_raise = 0.0
	s.visible = not instant
	soeun_placed = true

## 보는 순간 형광등이 깜빡이고, 다시 켜졌을 때 소은은 없다 (손전등도 같은 순간 꺼진다)
func soeun_vanish_flicker(light: String, instant: bool) -> void:
	var s: Node3D = lvl.soeun_node
	if instant:
		if s:
			s.visible = false
		soeun_gone = true
		return
	var f: LightFixture = lvl.fx.get(light)
	var fl: Flashlight = lvl.player.flashlight
	if f:
		f._set_lit(false)
	await get_tree().create_timer(0.09, false).timeout
	if f:
		f._set_lit(true, 0.55)
	await get_tree().create_timer(0.07, false).timeout
	if f:
		f._set_lit(false)
	var fl_was := fl != null and fl.is_on
	if fl_was:
		fl.spot.visible = false
	Sounds.play_at("sfx_flicker_zap", b2g(Vector3(11.5, -1.1, 2.4)), &"SFX", -10.0)
	await get_tree().create_timer(0.38, false).timeout
	if s:
		s.visible = false
	soeun_gone = true
	await get_tree().create_timer(0.12, false).timeout
	if fl_was and fl.is_on:
		fl.spot.visible = true
	if f:
		f._apply()

# =========================================================== EVENT 09 소음 실루엣
func _ensure_noise() -> void:
	if noise:
		return
	var path := "res://assets/models/characters/gst_noise_silhouette.gltf"
	if not ResourceLoader.exists(path):
		path = "res://assets/models/characters/gst_prologue_monster.gltf"
	var r: Array = lvl._character(path)
	noise = r[0]
	noise_poser = r[1]
	if noise == null:
		return
	noise.name = "NoiseSilhouette"
	var sh := load("res://shaders/noise_tape.gdshader") as Shader
	for mi in noise.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat == null:
				continue
			if mat.resource_name.contains("noise_tape") and sh:
				_noise_tape_mat = ShaderMaterial.new()
				_noise_tape_mat.shader = sh
				m.set_surface_override_material(i, _noise_tape_mat)
			elif mat.resource_name.contains("noise_body"):
				var bm := StandardMaterial3D.new()
				bm.albedo_color = Color(0.012, 0.012, 0.014)
				bm.roughness = 0.95
				bm.metallic_specular = 0.2
				m.set_surface_override_material(i, bm)

func _noise_head() -> Vector3:
	var sk := noise.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var s := sk[0] as Skeleton3D
		var id := s.find_bone("head")
		if id >= 0:
			return s.global_transform * s.get_bone_global_pose(id).origin
	return noise.global_position + Vector3(0, 1.8, 0)

func place_monster_corner(instant: bool) -> void:
	if instant:
		monster_state = "gone"
		return
	_ensure_noise()
	if noise == null:
		monster_state = "gone"
		return
	var at := b2g(NOISE_PEEK)
	noise.global_position = at
	noise.scale = Vector3.ONE
	noise.look_at(at + Vector3(1, 0, 0), Vector3.UP, true)      # 기둥 동쪽(작업실 문 쪽)을 바라본다
	noise_poser.mode = "peek"
	noise_poser.hunch = 0.5
	noise_poser.head_raise = 0.6
	noise.visible = true
	monster_state = "peeking"
	# 기둥 뒤에서 몸을 옆으로 기울여 머리·어깨만 복도 쪽으로 내민다 (발은 기둥 뒤에 고정).
	# 포즈의 기울기 방향을 모델마다 확신할 수 없으므로 양쪽을 재 보고 머리가 복도 쪽(남쪽)으로 더 나오는 쪽을 쓴다
	await get_tree().process_frame
	var base_t := noise.global_transform
	var best := 0.0
	var best_y := 99.0
	for sgn in [1.0, -1.0]:
		noise.global_transform = base_t
		noise.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(NOISE_LEAN) * sgn)
		await get_tree().process_frame
		var hy := g2b(_noise_head()).y
		if hy < best_y:
			best_y = hy
			best = sgn
	noise.global_transform = base_t
	_noise_upright = base_t.basis
	noise.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(NOISE_LEAN) * best)
	await get_tree().process_frame
	Sounds.play_at("sfx_tape_rip", _noise_head(), &"SFX", -22.0)

## 다가가면 혹은 충분히 보였으면 기둥 뒤로 숨는다 → 시야에서 벗어난 뒤에만 사라진다
func monster_peek_watch(_hide_dist: float) -> void:
	if noise == null or monster_state != "peeking":
		monster_state = "gone"
		return
	# 다가오면 숨는다: 처음 본 거리보다 0.6 m 이상 가까워지거나, 1.6 m 안, 또는 3.5초 넘게 보이면
	var seen := 0.0
	var d0 := -1.0
	while monster_state == "peeking":
		await get_tree().process_frame
		var dt := get_process_delta_time()
		var head := _noise_head()
		var d: float = lvl.player.camera.global_position.distance_to(head)
		if _in_view(head, 30.0):
			seen += dt
			if d0 < 0.0:
				d0 = d
		if d0 > 0.0 and (d < d0 - 0.6 or d < 1.6 or seen > 3.5):
			break
		if d0 < 0.0 and d < 1.6:
			break
	monster_state = "hiding"
	Sounds.play_at("step_concrete", noise.global_position, &"SFX", -14.0, null, 0.05)
	noise_poser.mode = "idle"
	noise_poser.head_raise = 0.0
	var tw := create_tween()
	tw.tween_property(noise, "global_transform", Transform3D(_noise_upright, b2g(NOISE_HIDE)), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	# 시야 밖이 될 때까지 기다렸다가 제거 (보는 앞에서 사라지지 않음). 오래 지켜보면 손전등이 깜빡이는 순간에 사라진다
	var waited := 0.0
	while _in_view(noise.global_position + Vector3(0, 1.2, 0), 50.0) and waited < 6.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if waited >= 6.0:
		lvl.player.flashlight.anomaly_flicker(0.6)
		await get_tree().create_timer(0.25, false).timeout
	noise.visible = false
	monster_state = "gone"

## 화면 안에 있고 가려지지 않았는가
func _in_view(pt: Vector3, max_deg: float) -> bool:
	var cam: Camera3D = lvl.player.camera
	var to := pt - cam.global_position
	if rad_to_deg((-cam.global_transform.basis.z).angle_to(to.normalized())) > max_deg:
		return false
	return has_los(pt)

func has_los(pt: Vector3) -> bool:
	var cam: Camera3D = lvl.player.camera
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, pt, 1)
	q.exclude = [lvl.player.get_rid()]
	var hit := lvl.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(pt) < 0.35

# =========================================================== EVENT 09b 따라오는 발소리
func set_follower(on: bool) -> void:
	follower_on = on
	if on:
		follow_dist = 7.5
		_foll_pos = lvl.player.global_position + Vector3(-follow_dist, 0, 0)

func _process(delta: float) -> void:
	if follower_on:
		_follow(delta)
	if chase_on:
		_chase()
	if _noise_tape_mat:
		_noise_tape_mat.set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)

func _follow(delta: float) -> void:
	var p: PlayerController = lvl.player
	var v := Vector2(p.velocity.x, p.velocity.z)
	var spd := v.length()
	# 플레이어 서쪽(지나온 쪽) 뒤편, 복도 안에서만 따라온다
	var target := p.global_position + Vector3(-follow_dist, 0, 0)
	target.x = maxf(target.x, b2g(Vector3(-4.6, 0, 0)).x)
	target.z = clampf(target.z, b2g(Vector3(0, -0.4, 0)).z, b2g(Vector3(0, -1.8, 0)).z)
	_foll_pos = _foll_pos.lerp(target, clampf(delta * 3.0, 0, 1))
	# 돌아보면 멈춘다 (아무것도 없다)
	var looking_back := _in_view(_foll_pos + Vector3(0, 1.0, 0), 35.0)
	if spd < 0.4 or looking_back:
		_step_t = 0.18          # 멈추면 거의 같이 멈춘다 (아주 짧게 늦게)
		return
	var running := spd > 3.6
	var interval := 0.33 if running else 0.52
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = interval * randf_range(0.97, 1.05)
		var db := -8.0 + (7.5 - follow_dist) * 1.4
		Sounds.play_at("step_concrete", _foll_pos + Vector3(0, 0.05, 0), &"SFX", db, null, 0.04, "", 3.0)
		follow_dist = maxf(2.4, follow_dist - (0.22 if running else 0.14))
		p.danger = clampf(0.55 + (7.5 - follow_dist) * 0.07, 0.0, 0.95)

# =========================================================== EVENT 10 뒤에서부터 하나씩 꺼지는 형광등
func start_lights_chase() -> void:
	chase_on = true
	_chase_next = 0

func _chase() -> void:
	var x := g2b(lvl.player.global_position).x
	while _chase_next < 5 and x > float(COR_LIGHT_X[_chase_next]) + 1.6:
		var n := "CorLight%d" % _chase_next
		if lvl.fx.has(n) and lvl.fx[n].is_emitting():
			lvl.set_light(n, "story_off")
			Sounds.play_at("sfx_power_down", b2g(Vector3(COR_LIGHT_X[_chase_next], -1.1, 2.4)), &"SFX", -13.0, null, 0.06)
		_chase_next += 1
	if _chase_next >= 5:
		chase_on = false

func lights_off(names: Array, instant: bool) -> void:
	for n in names:
		if String(n) == "ExitSign":
			_exit_sign_dim(0.04)
			continue
		lvl.set_light(String(n), "story_off", instant)

## 비상구 표시등까지 꺼진다 (마지막 소등 — 초록빛이 벽을 물들이던 문제, 요구사항 16 영상 검수)
func _exit_sign_dim(k: float) -> void:
	for mi in lvl.cor.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat and mat.resource_name.contains("exit_sign") and mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if not bm.has_meta("base_em"):
					bm.set_meta("base_em", bm.emission_energy_multiplier)
				bm.emission_energy_multiplier = float(bm.get_meta("base_em")) * k

func flashlight_cut(instant: bool) -> void:
	var fl: Flashlight = lvl.player.flashlight
	if fl == null:
		return
	fl.blocked = true
	if fl.is_on and not instant:
		fl.set_on(false)
	elif fl.is_on:
		fl.is_on = false
		fl.spot.visible = false

# =========================================================== 테이프 잡음 (기억 속 공간이 흔들리는 순간)
func tape_glitch(secs: float) -> void:
	if _glitch == null:
		_glitch = ColorRect.new()
		_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/tape_glitch.gdshader")
		_glitch.material = sm
		story._fade_layer.add_child(_glitch)
		_glitch.move_to_front()
	_glitch.visible = true
	Sounds.play("amb_tape_hiss", &"SFX", -10.0)
	var t := 0.0
	while t < secs:
		(_glitch.material as ShaderMaterial).set_shader_parameter("amount", randf_range(0.5, 1.0))
		(_glitch.material as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)
		await get_tree().process_frame
		t += get_process_delta_time()
	_glitch.visible = false

# =========================================================== TAPE 01 (1998)
func apt_child_steps_up() -> void:
	# 계단 위층에서 아이가 뛰어 올라가는 발소리 (아무도 없다)
	var a: Vector3 = lvl.apt.point("apt_frag_2") + Vector3(0, 1.4, 0)
	var c: Vector3 = lvl.apt.point("apt_steps_up") + Vector3(0, 0.1, 0)
	for i in 9:
		Sounds.play_at("step_concrete", a.lerp(c, i / 8.0), &"SFX", -9.0 - i * 0.6, null, 0.05, "위층에서 들리는 작은 발소리" if i == 0 else "", 2.4)
		await get_tree().create_timer(0.21, false).timeout
	await get_tree().create_timer(0.4, false).timeout
	Sounds.play_at("sfx_child_laugh", c + Vector3(0, 1.0, 0), &"SFX", -18.0)

## 소은이 복도 끝에 서 있다 — 플레이어가 그쪽을 보고 있지 않을 때만 놓는다
func apt_place_soeun() -> void:
	var apt: AptCorridor = lvl.apt
	if apt == null or apt.soeun == null:
		return
	var at := apt.point("apt_soeun_end")
	var waited := 0.0
	while _in_view(at + Vector3(0, 1.0, 0), 60.0) and waited < 20.0:
		await get_tree().create_timer(0.2, false).timeout
		waited += 0.2
	apt.soeun.global_position = at
	apt.soeun.look_at(Vector3(lvl.player.global_position.x, at.y, lvl.player.global_position.z), Vector3.UP, true)
	apt.soeun_poser.mode = "idle"
	apt.soeun.visible = true

func apt_soeun_vanish() -> void:
	var apt: AptCorridor = lvl.apt
	if apt == null or apt.soeun == null:
		return
	await get_tree().create_timer(1.3, false).timeout
	# 테이프가 늘어지는 순간 (화면·소리 잡음) — 잡음이 걷히면 소은은 없다
	tape_glitch(0.45)
	apt.lamps_power(0.2)
	await get_tree().create_timer(0.2, false).timeout
	apt.soeun.visible = false
	await get_tree().create_timer(0.25, false).timeout
	apt.lamps_power(1.0)
