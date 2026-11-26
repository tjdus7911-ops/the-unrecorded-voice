class_name Interactable
extends StaticBody3D
## 조사·조작 가능한 오브젝트의 기반 클래스.
## 빛나는 외곽선·위치 아이콘을 쓰지 않는다 — 조준점으로 바라볼 때만 짧은 안내를 띄운다.
## 사용법: action(Callable) 지정 → E로 실행 / inspectable=true → 조사 화면(회전·설명), pickup_item 이 있으면 획득.

signal interacted(by: Node)

@export var prompt := "조사하기"
@export var max_distance := 2.0
@export var enabled := true

var action: Callable                 ## E 키 동작 (없으면 조사)
var prompt_fn: Callable              ## 상황에 따라 바뀌는 안내 문구
var inspectable := false
var inspect_title := ""
var inspect_text := ""
var inspect_visual: Node3D           ## 조사 화면에 띄울 시각 노드 (복제해서 사용)
var pickup_item: StringName = &""
var remove_on_pickup: Node           ## 획득 시 월드에서 제거할 노드

func _ready() -> void:
	# 조사 판정 전용 레이어(3). 이동은 막지 않는다 — 물리적 막힘은 각 오브젝트의 충돌체가 담당.
	collision_layer = 4

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
	for mi in node.find_children("*", "MeshInstance3D", true, false):
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
