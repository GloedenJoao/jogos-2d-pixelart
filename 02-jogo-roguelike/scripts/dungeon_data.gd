class_name DungeonData
extends RefCounted

enum Cell { WALL, FLOOR }

var width: int
var height: int
var cells: Dictionary = {} # Vector2i -> Cell
var rooms: Array[Rect2i] = []
var entrance: Vector2i
var exit: Vector2i
var items: Array[Dictionary] = [] # {"pos": Vector2i, "type": "potion"|"gold", "amount": int}
var enemy_spawns: Array[Vector2i] = []

func is_floor(pos: Vector2i) -> bool:
	return cells.get(pos, Cell.WALL) == Cell.FLOOR

func item_at(pos: Vector2i) -> Dictionary:
	for item in items:
		if item.pos == pos:
			return item
	return {}

func remove_item_at(pos: Vector2i) -> void:
	for i in items.size():
		if items[i].pos == pos:
			items.remove_at(i)
			return
