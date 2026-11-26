extends Node
## 인벤토리 / 증거 수집 (autoload: Inventory)

signal item_added(item_id: StringName)

var items: Array[StringName] = []
var has_flashlight := false

func add(item_id: StringName) -> void:
	if item_id == &"flashlight":
		has_flashlight = true
	if not items.has(item_id):
		items.append(item_id)
		item_added.emit(item_id)

func has(item_id: StringName) -> bool:
	return items.has(item_id)

func clear() -> void:
	items.clear()
	has_flashlight = false
