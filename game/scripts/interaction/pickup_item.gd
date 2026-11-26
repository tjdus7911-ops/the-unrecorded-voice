class_name PickupItem
extends Interactable
## 획득 가능한 단서·도구 (손전등, 카세트테이프, 열쇠, 근무일지 등).

@export var item_id: StringName = &""
@export var display_name := ""
@export var pickup_sound: AudioStream

func _ready() -> void:
	super._ready()
	if prompt == "조사하기":
		prompt = "줍기"

func _on_interact(_by: Node) -> void:
	Inventory.add(item_id)
	if pickup_sound:
		var p := AudioStreamPlayer3D.new()
		p.stream = pickup_sound
		p.bus = &"SFX"
		get_parent().add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)
	queue_free()
