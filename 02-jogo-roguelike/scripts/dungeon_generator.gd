class_name DungeonGenerator
extends RefCounted

const MIN_ROOM_SIZE := 4
const MAX_ROOM_SIZE := 7
const MAX_ROOMS := 8
const MAX_PLACEMENT_ATTEMPTS := 40
const MAX_ITEMS := 4
const MAX_ENEMIES := 5
const ENEMIES_PER_FLOOR := 2

static func generate(width: int, height: int, rng: RandomNumberGenerator, floor_number: int = 1) -> DungeonData:
	var data := DungeonData.new()
	data.width = width
	data.height = height
	data.floor_number = maxi(1, floor_number)
	for x in width:
		for y in height:
			data.cells[Vector2i(x, y)] = DungeonData.Cell.WALL

	var placed_rooms: Array[Rect2i] = []
	for _attempt in MAX_PLACEMENT_ATTEMPTS:
		if placed_rooms.size() >= MAX_ROOMS:
			break
		var w := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var h := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var x := rng.randi_range(1, width - w - 2)
		var y := rng.randi_range(1, height - h - 2)
		var rect := Rect2i(x, y, w, h)
		var overlaps := false
		for other in placed_rooms:
			if rect.grow(1).intersects(other):
				overlaps = true
				break
		if overlaps:
			continue
		placed_rooms.append(rect)
		_carve_room(data, rect)

	# Sempre garante pelo menos uma sala (fallback determinístico se o placement aleatório falhar).
	if placed_rooms.is_empty():
		var fallback := Rect2i(1, 1, mini(MAX_ROOM_SIZE, width - 2), mini(MAX_ROOM_SIZE, height - 2))
		placed_rooms.append(fallback)
		_carve_room(data, fallback)

	for i in range(1, placed_rooms.size()):
		_carve_corridor(data, _room_center(placed_rooms[i - 1]), _room_center(placed_rooms[i]), rng)

	data.rooms = placed_rooms
	data.entrance = _room_center(placed_rooms[0])
	data.exit = _farthest_room_center(placed_rooms, data.entrance)

	_place_items(data, placed_rooms, rng)
	_place_enemies(data, placed_rooms, rng)

	return data

static func _carve_room(data: DungeonData, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			data.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR

static func _carve_corridor(data: DungeonData, from: Vector2i, to: Vector2i, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 1) == 0:
		_carve_h(data, from.x, to.x, from.y)
		_carve_v(data, from.y, to.y, to.x)
	else:
		_carve_v(data, from.y, to.y, from.x)
		_carve_h(data, from.x, to.x, to.y)

static func _carve_h(data: DungeonData, x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		data.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR

static func _carve_v(data: DungeonData, y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		data.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR

static func _room_center(rect: Rect2i) -> Vector2i:
	return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)

static func _farthest_room_center(placed_rooms: Array[Rect2i], from: Vector2i) -> Vector2i:
	var best := from
	var best_dist := -1
	for rect in placed_rooms:
		var center := _room_center(rect)
		var dist := absi(center.x - from.x) + absi(center.y - from.y)
		if dist > best_dist:
			best_dist = dist
			best = center
	return best

static func _place_items(data: DungeonData, placed_rooms: Array[Rect2i], rng: RandomNumberGenerator) -> void:
	if placed_rooms.size() <= 1:
		return
	var count := mini(MAX_ITEMS, placed_rooms.size() - 1)
	for i in count:
		var room := placed_rooms[1 + (i % (placed_rooms.size() - 1))]
		var pos := _random_floor_in_room(room, rng)
		if pos == data.entrance or pos == data.exit:
			continue
		var is_gold := rng.randi_range(0, 1) == 0
		data.items.append({
			"pos": pos,
			"type": "gold" if is_gold else "potion",
			"amount": rng.randi_range(5, 15) if is_gold else 1,
		})

static func _place_enemies(data: DungeonData, placed_rooms: Array[Rect2i], rng: RandomNumberGenerator) -> void:
	if placed_rooms.size() <= 1:
		return
	# Andares mais fundos ficam mais povoados (a densidade cresce, o mapa não).
	var budget := MAX_ENEMIES + (data.floor_number - 1) * ENEMIES_PER_FLOOR
	for i in budget:
		var room := placed_rooms[1 + (i % (placed_rooms.size() - 1))]
		var pos := _random_floor_in_room(room, rng)
		if pos == data.entrance or pos == data.exit or data.enemy_spawns.has(pos):
			continue
		data.enemy_spawns.append(pos)

static func _random_floor_in_room(rect: Rect2i, rng: RandomNumberGenerator) -> Vector2i:
	var x := rng.randi_range(rect.position.x, rect.position.x + rect.size.x - 1)
	var y := rng.randi_range(rect.position.y, rect.position.y + rect.size.y - 1)
	return Vector2i(x, y)
