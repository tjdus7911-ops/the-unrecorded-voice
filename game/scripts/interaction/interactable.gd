class_name Interactable
extends StaticBody3D
## 조사·조작 가능한 오브젝트의 기반 클래스.
## 빛나는 외곽선·위치 아이콘을 쓰지 않는다 — 조준점으로 바라볼 때만 짧은 안내를 띄운다.
## 사용법: action(Callable) 지정 → E로 실행 / inspectable=true → 조사 화면(회전·설명), pickup_item 이 있으면 획득.

signal interacted(by: Node)

@export var prompt := "조사하기"
@export var max_distance := 2.0
## 비활성화되면 판정 레이어도 끈다 — 꺼진 상자 판정이 안쪽 물건(메모·테이프)을 가리지 않게
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			collision_layer = 4 if v else 0

var action: Callable                 ## E 키 동작 (없으면 조사)
var prompt_fn: Callable              ## 상황에 따라 바뀌는 안내 문구
var inspectable := false
var inspect_title := ""
var inspect_text := ""
var inspect_visual: Node3D           ## 조사 화면에 띄울 시각 노드 (복제해서 사용)
var pickup_item: StringName = &""
var remove_on_pickup: Node           ## 획득 시 월드에서 제거할 노드
var highlight := false              ## 바라볼 때 은은한 강조 (필수 진행 물건만 — 숨겨진 단서에는 쓰지 않는다)
var inspect_text_back := ""          ## 뒤집었을 때 보이는 글 (숨겨진 단서 등)
var clue_back: StringName = &""      ## 뒷면을 보면 얻는 단서 ID (data/progress/clues.json)
## ---- 1인칭 손 동작 (ViewmodelArms)
## reach: "" 손 동작 없음 / "grab" 손잡이 잡기 / "press" 검지로 누르기 / "pull" 잡고 당기기(따라감) / "pick" 집기
var reach := ""
var reach_target: Node3D             ## 손이 닿을 지점 (없으면 판정 상자 중심)
var reach_offset := Vector3.ZERO     ## reach_target 기준 월드 오프셋
var reach_hold := 0.25               ## 닿은 뒤 머무는 시간
var reach_follow: Callable           ## func(k: float) -> Vector3 : 물체와 함께 움직일 손 위치 (문·서랍)
var lock_hands := false              ## 조사·운반 중 다른 상호작용 금지용

func reach_point() -> Vector3:
	if reach_target and is_instance_valid(reach_target):
		return reach_target.global_position + reach_offset
	for c in get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).global_position + reach_offset
	return global_position + reach_offset

func _ready() -> void:
	# 조사 판정 전용 레이어(3). 이동은 막지 않는다 — 물리적 막힘은 각 오브젝트의 충돌체가 담당.
	collision_layer = 4 if enabled else 0

func can_interact(player: Node3D) -> bool:
	return enabled and player.global_position.distance_to(global_position) <= max_distance + 1.0

func current_prompt() -> String:
	if prompt_fn.is_valid():
		return prompt_fn.call()
	return prompt

func interact(by: Node) -> void:
	interacted.emit(by)
	if action.is_valid():
		action.call()
	else:
		_on_interact(by)

func _on_interact(_by: Node) -> void:
	pass

## 노드의 모든 메시를 감싸는 상자 충돌체를 붙여 Interactable로 만든다 (움직이는 부품은 그 노드 아래에 붙여 함께 이동).
static func attach_to(node: Node3D, prompt_text: String, padding := 0.01, min_size := 0.06) -> Interactable:
	var it := Interactable.new()
	it.name = "Interact"
	it.prompt = prompt_text
	node.add_child(it)
	var aabb := local_aabb(node)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (aabb.size + Vector3.ONE * padding * 2.0).max(Vector3.ONE * min_size)
	cs.shape = bs
	cs.position = aabb.get_center()
	it.add_child(cs)
	return it

static func local_aabb(node: Node3D) -> AABB:
	var inv := node.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)       # 노드 자신이 메시인 경우 (서랍 앞판 등)
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var box := (inv * m.global_transform) * m.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
