class_name PlayerController
extends CharacterBody3D
## 1인칭 플레이어 (서정우).
## 이동·달리기·앉기·시점·상호작용 + 호흡/심장 박동/카메라 연동의 기준 상태를 제공한다.

signal interact_target_changed(target: Interactable)

@export_group("Movement")
@export var walk_speed := 1.7        ## m/s — 공포 장르 기준 느린 보행
@export var run_speed := 3.8
@export var crouch_speed := 0.9
@export var acceleration := 9.0
@export var friction := 12.0

@export_group("Body")
@export var stand_height := 1.75
@export var crouch_height := 1.15
@export var eye_below_top := 0.11    ## 눈높이 = 키 - 0.11 → 서 있을 때 1.64 m (신장 175 cm, 요구사항 12 §1)
@export var radius := 0.28

@export_group("Stamina")
@export var stamina_max := 6.0       ## 연속 달리기 가능 시간(초)
@export var stamina_regen := 0.75    ## 초당 회복량
@export var exhausted_threshold := 2.0  ## 탈진 후 이만큼 회복해야 다시 달릴 수 있음

@export_group("Camera FX")
@export var bob_amount_walk := 0.006     ## 요구사항 12: 과도한 흔들림 방지 (이전 0.012)
@export var bob_amount_run := 0.014
@export var breath_sway := 0.0035

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var flashlight: Flashlight = $Flashlight
@onready var breathing: BreathingSystem = $BreathingSystem
@onready var heartbeat: HeartbeatSystem = $HeartbeatSystem

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var input_enabled := true
var stamina := 6.0
var is_running := false
var is_crouching := false
var is_exhausted := false
var is_hiding := false
## 0~1 위험도. 귀신 AI·스크립트 이벤트가 설정한다 (심장 박동·호흡·손 떨림에 반영).
var danger := 0.0

var _yaw := 0.0
var _pitch := 0.0
var _height := 1.75
var _bob_t := 0.0
var _breath_t := 0.0
var _interact_target: Interactable
signal look_moved(rel: Vector2)
signal recorder_key_pressed
signal interacted_any

var _lock_until := 0.0
var _game_t := 0.0             ## 게임 시간(일시정지·시간 배율을 따름) — 연출 중 상호작용 잠금용
## 미니멀 상호작용 (요구사항 13): 몸에서 수평 이 거리 안(약 0.8~1.2 m 접근) + 정확히 바라볼 때만
@export var interact_reach := 1.15
## 어두운 곳에서는 빛이 닿아 보이는 지점만 조작 가능 (레벨이 설정: Callable(point) -> bool)
var visibility_check := Callable()
var seated := false                  ## 의자에 앉아 있음 (이동 불가, 시점은 자유)
const seated_height := 1.28        ## 앉은 눈높이 약 1.17 m
var _kick := 0.0

## 앉기/일어서기 (EVENT 01 — 조작권은 시점만 잠깐 제한 없이 유지)
func set_seated(on: bool) -> void:
	seated = on
	if on:
		_height = seated_height
		_apply_height()

## 놀람·충격 시 카메라 순간 반동 (카메라 흔들림 설정을 따른다)
func camera_kick(amount: float) -> void:
	_kick = maxf(_kick, amount)

var footsteps: Footsteps
var arms: ViewmodelArms
var hands_busy := false
@export var use_hands := false          ## 1인칭 손·팔 표시 (요구사항 14로 기본 끔, 코드 보관)
var hands_animate := true            ## 테스트에서 즉시 동작시키려면 false
var carrying: Node3D = null          ## 두 손으로 옮기는 물건 (택배)
var held_recorder: Node3D = null     ## 오른손에 든 녹음기
var carry_target_fn: Callable        ## 운반 중 E: 내려놓기 시도
var inspect: InspectSystem

func _ready() -> void:
	camera.fov = GameSettings.fov
	footsteps = Footsteps.new()
	footsteps.name = "Footsteps"
	add_child(footsteps)
	# 요구사항 14: 1인칭 손·팔을 표시하지 않는다. (손 모델·리그·포즈 코드는 보관 — use_hands=true면 다시 켜짐)
	if use_hands:
		arms = ViewmodelArms.new()
		arms.name = "Arms"
		arms.player = self
		arms.camera = camera
		add_child(arms)
		flashlight.use_hands.call_deferred(arms)
	inspect = InspectSystem.new()
	inspect.name = "Inspect"
	inspect.player = self
	camera.add_child(inspect)
	stamina = stamina_max
	_height = stand_height
	_yaw = rotation.y
	_apply_height()
	# 마우스 캡처는 GameFlow가 상태에 따라 관리한다 (여기서 직접 바꾸지 않음)

## 마우스 시점: GUI보다 먼저 받는 _input에서 처리한다.
## (이전 버그: 화면 중앙의 조준점 ColorRect가 MOUSE_FILTER_STOP이라, 커서가 중앙에 고정된
##  캡처 모드에서 모든 마우스 이동 이벤트를 GUI가 소비 → _unhandled_input에 도달하지 못함)
## screen_relative: 창 크기·스트레치 배율과 무관한 화면 픽셀 단위 → 해상도·FPS와 관계없이 같은 감도.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_enabled and GameFlow.wants_look():
		var sens: float = GameSettings.mouse_sensitivity
		var rel: Vector2 = event.screen_relative
		_yaw -= rel.x * sens
		var dy := rel.y * sens * (-1.0 if GameSettings.invert_y else 1.0)
		_pitch = clampf(_pitch - dy, deg_to_rad(-85), deg_to_rad(85))
		look_moved.emit(rel)

## 테스트·연출용: 마우스 이동량(화면 픽셀)을 시점에 적용
func apply_look(rel: Vector2) -> void:
	var sens: float = GameSettings.mouse_sensitivity
	_yaw -= rel.x * sens
	_pitch = clampf(_pitch - rel.y * sens, deg_to_rad(-85), deg_to_rad(85))

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not GameFlow.is_playing():
		return
	if event.is_action_pressed("recorder_play"):
		if not hands_busy:
			recorder_key_pressed.emit()
	elif event.is_action_pressed("flashlight"):
		flashlight.toggle()
	elif event.is_action_pressed("interact"):
		try_interact()
	elif event.is_action_pressed("debug_danger") and OS.is_debug_build():
		danger = 0.0 if danger > 0.5 else 1.0

func _physics_process(delta: float) -> void:
	_game_t += delta
	rotation.y = _yaw
	head.rotation.x = _pitch

	var input_dir := Vector2.ZERO
	var want_run := false
	var want_crouch := false
	if input_enabled and not seated:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_run = Input.is_action_pressed("sprint")
		want_crouch = Input.is_action_pressed("crouch")

	_update_crouch(want_crouch, delta)
	_update_stamina(want_run and input_dir.length() > 0.1, delta)

	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_running:
		speed = run_speed

	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(input_dir.length(), 1.0)
	var target := dir * speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if target.length() > 0.01 else friction
	horiz = horiz.move_toward(target, rate * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)
	move_and_slide()
	_smooth_steps(delta)
	if leaning and input_dir.length() > 0.2:
		lean_out()
	_lean = _lean.lerp(_lean_goal, clampf(delta * 5.0, 0.0, 1.0))
	_apply_height()

	_update_camera_fx(delta)
	if input_enabled:
		_update_interact_target()
	breathing.update_from_player(self, delta)
	heartbeat.set_danger(danger)
	flashlight.set_tremble(danger)

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

# --- Crouch ---------------------------------------------------------------
func _update_crouch(want: bool, delta: float) -> void:
	if want:
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	var goal := crouch_height if is_crouching else stand_height
	if seated:
		goal = seated_height
	_height = move_toward(_height, goal, delta * (1.6 if seated or _height < seated_height + 0.2 else 3.0))
	_apply_height()

func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius * 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * (stand_height - radius))
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()

func _apply_height() -> void:
	var cap := collision.shape as CapsuleShape3D
	cap.height = _height
	cap.radius = radius
	collision.position.y = _height * 0.5
	head.position = Vector3(0.0, _height - eye_below_top + _step_off + _lean.y, _lean.z)

## ---- 계단·턱을 오를 때 시점이 튀지 않게: 바닥 높이 변화를 머리 오프셋으로 흡수했다가 부드럽게 따라간다
var _step_off := 0.0
var _last_floor_y := 0.0
func _smooth_steps(delta: float) -> void:
	var y := global_position.y
	var dy := y - _last_floor_y
	_last_floor_y = y
	if is_on_floor() and absf(dy) > 0.012 and absf(dy) < 0.45:
		_step_off = clampf(_step_off - dy, -0.4, 0.4)
	_step_off = lerpf(_step_off, 0.0, clampf(delta * 9.0, 0.0, 1.0))

## ---- 몸을 숙여 들여다보기 (상자 안 등). 이동 입력이 들어오면 원래 자세로
var _lean := Vector3.ZERO
var _lean_goal := Vector3.ZERO
var leaning := false
func lean_into(point: Vector3, forward := 0.34, down := 0.40) -> void:
	leaning = true
	_lean_goal = Vector3(0, -down, -forward)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var eye := global_position + Vector3.UP * (_height - eye_below_top - down)
	var flat := Vector3(point.x - global_position.x, 0, point.z - global_position.z).normalized()
	eye += flat * forward
	var d := point - eye
	var yaw := atan2(-d.x, -d.z)
	yaw = _yaw + wrapf(yaw - _yaw, -PI, PI)
	tw.tween_property(self, "_yaw", yaw, 0.7)
	tw.tween_property(self, "_pitch", atan2(d.y, Vector2(d.x, d.z).length()), 0.7)

func lean_out() -> void:
	leaning = false
	_lean_goal = Vector3.ZERO

# --- Stamina --------------------------------------------------------------
func _update_stamina(trying_to_run: bool, delta: float) -> void:
	if is_exhausted and stamina >= exhausted_threshold:
		is_exhausted = false
	is_running = trying_to_run and not is_exhausted and not is_crouching
	if is_running:
		stamina = maxf(stamina - delta, 0.0)
		if stamina <= 0.0:
			is_exhausted = true
			is_running = false
	else:
		var regen := stamina_regen * (1.4 if horizontal_speed() < 0.1 else 1.0)
		stamina = minf(stamina + regen * delta, stamina_max)

# --- Camera ---------------------------------------------------------------
func _update_camera_fx(delta: float) -> void:
	var shake: float = GameSettings.camera_shake
	var spd := horizontal_speed()
	var bob_amt := 0.0
	if is_on_floor() and spd > 0.2:
		var freq := 1.9 if not is_running else 2.6   # 걸음 주기(Hz)
		_bob_t += delta * freq * TAU * 0.5
		bob_amt = bob_amount_run if is_running else bob_amount_walk
	var bob_y := sin(_bob_t * 2.0) * bob_amt
	var bob_x := sin(_bob_t) * bob_amt * 0.5
	# 호흡에 따른 미세한 상하 움직임 — 호흡 시스템의 현재 속도를 따른다
	_breath_t += delta * TAU * breathing.breath_rate_hz()
	var sway := sin(_breath_t) * breath_sway * breathing.breath_depth()
	if is_hiding:
		bob_y *= 0.2
		bob_x *= 0.2
	camera.position = camera.position.lerp(Vector3(bob_x, bob_y + sway, 0.0) * shake, clampf(delta * 12.0, 0.0, 1.0))
	if _kick > 0.001:
		camera.rotation.x = sin(Time.get_ticks_msec() * 0.06) * 0.02 * _kick * shake
		camera.rotation.z = sin(Time.get_ticks_msec() * 0.045) * 0.012 * _kick * shake
		_kick = move_toward(_kick, 0.0, delta * 2.5)
	else:
		camera.rotation.x = 0.0
		camera.rotation.z = 0.0

# --- Interaction ----------------------------------------------------------
func _update_interact_target() -> void:
	var t: Interactable = null
	if interact_ray.is_colliding():
		var c := interact_ray.get_collider()
		var hp := interact_ray.get_collision_point()
		if c is Interactable and (c as Interactable).can_interact(self) and _line_of_sight(hp) \
				and Vector2(hp.x - global_position.x, hp.z - global_position.z).length() <= interact_reach \
				and (not visibility_check.is_valid() or visibility_check.call(hp)):
			t = c
	if t != _interact_target:
		_set_highlight(_interact_target, false)
		_interact_target = t
		_set_highlight(t, true)
		interact_target_changed.emit(t)

## 벽 너머 오브젝트는 조작할 수 없게: 월드 충돌체가 조사 지점보다 0.3 m 이상 앞에 있으면 가려진 것으로 본다
## (서랍처럼 가구 충돌 상자 바로 안쪽에 있는 부품은 허용)
func _line_of_sight(point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, point, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(point) < 0.3

## 테스트·컷신용: 특정 지점을 바라보게 한다
func look_at_point(pt: Vector3) -> void:
	var d := pt - head.global_position
	_yaw = atan2(-d.x, -d.z)
	_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	rotation.y = _yaw
	head.rotation.x = _pitch

## 스토리 연출 중 잠시 상호작용 금지
func lock_interaction(secs: float) -> void:
	_lock_until = _game_t + secs

func try_interact() -> bool:
	if _game_t < _lock_until:
		return false
	if hands_busy or carrying:
		if carrying and carry_target_fn.is_valid():
			carry_target_fn.call()
			return true
		return false
	head.force_update_transform()
	interact_ray.force_raycast_update()
	_update_interact_target()
	if _interact_target:
		interacted_any.emit()
		var it := _interact_target
		var then := func():
			if it.inspectable and not it.action.is_valid():
				inspect.open(it)
			else:
				it.interact(self)
		if arms and arms.enabled and it.reach != "" and hands_animate:
			_reach_then(it, then)
		else:
			then.call()
		return true
	return false

## 상호작용을 실제 손 동작으로: 오른손이 녹음기를 들고 있으면 잠시 내리고, 대상에 손을 뻗어 닿는 순간 동작 실행
func _reach_then(it: Interactable, then: Callable) -> void:
	hands_busy = true
	var rh: ViewmodelArms.Hand = arms.sides["R"]
	var had_tool := rh.held != null and rh.mode == ViewmodelArms.Mode.HOLD_RECORDER and not arms.is_lowered("R")
	if had_tool:
		await arms.lower_tool("R")
	var p := it.reach_point()
	var fwd := (p - camera.global_position).normalized()
	var thumb := Vector3.UP
	var pose := "grab_handle"
	var hold := it.reach_hold
	match it.reach:
		"press":
			pose = "point"
			p -= fwd * 0.085          # 검지 끝이 닿도록 손바닥 기준점을 뒤로
		"pick":
			pose = "pinch"
			fwd = (fwd + Vector3.DOWN * 0.5).normalized()
			thumb = -camera.global_transform.basis.x
		"grab", "pull":
			pose = "grab_handle"
	await arms.reach("R", p, fwd, thumb, pose, then, hold, it.reach_follow)
	if had_tool and rh.mode != ViewmodelArms.Mode.HOLD_OBJECT:
		arms.raise_tool("R")
	hands_busy = false


## 바라보는 필수 물건의 은은한 강조 (요구사항 12 §4) — 외곽선·아이콘이 아니라 표면이 살짝 밝아지는 정도
static var _hl_mat: ShaderMaterial
func _set_highlight(t, on: bool) -> void:
	if t == null or not is_instance_valid(t) or not (t is Interactable) or not t.highlight:
		return
	if on and not GameSettings.interaction_hints:
		return          # 미니멀 UI 기본: 강조 없음 (설정 '상호작용 힌트'에서만)
	if _hl_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.4);
	ALBEDO = vec3(1.0, 0.93, 0.8) * (0.035 + rim * 0.10) * pulse;
}"""
		_hl_mat = ShaderMaterial.new()
		_hl_mat.shader = sh
	var root: Node = t.inspect_visual if t.inspect_visual else t.get_parent()
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for m in meshes:
		(m as MeshInstance3D).material_overlay = _hl_mat if on else null
