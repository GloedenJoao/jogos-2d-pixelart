class_name Carrier
extends RefCounted

# NPC carregador: dado puro, mesma separação de `Worker` (a lógica de andar
# e decidir fica em `Carriers`).

enum State { IDLE, TO_SOURCE, TO_WAREHOUSE }

const SPEED := 90.0
const CAPACITY := 10.0

var id := -1
var position := Vector2.ZERO
var path := PackedVector2Array()
var path_index := 0
var state: int = State.IDLE
var source_building := -1
var resource := ""
var carrying := 0.0

func has_path() -> bool:
	return path_index < path.size()

func next_waypoint() -> Vector2:
	return path[path_index] if has_path() else position

func set_path(new_path: PackedVector2Array) -> void:
	path = new_path
	path_index = 0

func clear_path() -> void:
	path = PackedVector2Array()
	path_index = 0
