class_name EnemyAI
extends RefCounted

const AGGRO_RANGE := 6

# Retorna {"action": "attack"}, {"action": "move", "to": Vector2i} ou {"action": "idle"}.
static func decide(enemy: Entity, player: Entity, dungeon: DungeonData, occupied: Dictionary) -> Dictionary:
	var dist := _chebyshev(enemy.grid_pos, player.grid_pos)
	if dist <= 1:
		return {"action": "attack"}
	# Cada tipo de criatura tem seu próprio raio de agressividade (morcego enxerga
	# longe, fungo quase não sai do lugar); o padrão vale pra inimigos sem meta.
	var aggro: int = int(enemy.get_meta("aggro", AGGRO_RANGE))
	if dist > aggro:
		return {"action": "idle"}
	var step := _step_towards(enemy.grid_pos, player.grid_pos)
	if step == enemy.grid_pos or not dungeon.is_floor(step) or occupied.has(step):
		return {"action": "idle"}
	return {"action": "move", "to": step}

static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func _sign(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0

static func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx := _sign(to.x - from.x)
	var dy := _sign(to.y - from.y)
	if absi(to.x - from.x) >= absi(to.y - from.y) and dx != 0:
		return from + Vector2i(dx, 0)
	if dy != 0:
		return from + Vector2i(0, dy)
	if dx != 0:
		return from + Vector2i(dx, 0)
	return from
