class_name Interactable
extends StaticBody3D
## 조사·획득 가능한 오브젝트의 기반 클래스.
## 빛나는 외곽선·위치 아이콘을 쓰지 않는다 — 조준점 근처에서 바라볼 때만 짧은 안내를 띄운다.

signal interacted(by: Node)

@export var prompt := "조사하기"
@export var max_distance := 2.0
@export var enabled := true

func _ready() -> void:
	collision_layer = 1 | 4   # world + interactable

func can_interact(player: Node3D) -> bool:
	return enabled and player.global_position.distance_to(global_position) <= max_distance + 1.0

func interact(by: Node) -> void:
	interacted.emit(by)
	_on_interact(by)

func _on_interact(_by: Node) -> void:
	pass
