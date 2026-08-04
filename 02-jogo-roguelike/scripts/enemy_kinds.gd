class_name EnemyKinds
extends RefCounted

# Catálogo de criaturas da caverna. Cada tipo tem atributos próprios e uma
# profundidade mínima, então os andares mais fundos trazem bichos mais perigosos.
# "tile" é a coordenada no tileset Kenney Tiny Dungeon; "tint" diferencia visualmente
# variantes que reaproveitam o mesmo sprite.

const KINDS := [
	{
		"id": "limo",
		"name": "Limo",
		"tile": Vector2i(0, 9),
		"tint": Color(1, 1, 1),
		"hp": 5,
		"attack": 2,
		"aggro": 4,
		"gold": 3,
		"min_floor": 1,
	},
	{
		"id": "caranguejo",
		"name": "Caranguejo",
		"tile": Vector2i(2, 9),
		"tint": Color(1, 1, 1),
		"hp": 8,
		"attack": 3,
		"aggro": 5,
		"gold": 5,
		"min_floor": 1,
	},
	{
		"id": "morcego",
		"name": "Morcego",
		"tile": Vector2i(0, 10),
		"tint": Color(1, 1, 1),
		"hp": 4,
		"attack": 2,
		"aggro": 9,
		"gold": 4,
		"min_floor": 2,
	},
	{
		"id": "fungo",
		"name": "Fungo Rastejante",
		"tile": Vector2i(2, 10),
		"tint": Color(1, 1, 1),
		"hp": 12,
		"attack": 2,
		"aggro": 2,
		"gold": 6,
		"min_floor": 2,
	},
	{
		"id": "golem",
		"name": "Golem de Pedra",
		"tile": Vector2i(1, 10),
		"tint": Color(1, 1, 1),
		"hp": 16,
		"attack": 5,
		"aggro": 4,
		"gold": 12,
		"min_floor": 3,
	},
]

const BOSS := {
	"id": "guardiao",
	"name": "Guardião da Caverna",
	"tile": Vector2i(1, 10),
	"tint": Color(1.0, 0.55, 0.55),
	"hp": 34,
	"attack": 7,
	"aggro": 7,
	"gold": 40,
	"min_floor": 1,
	"boss": true,
}

# Escala de dificuldade por andar: cada andar depois do primeiro deixa os bichos
# um pouco mais duros, sem trocar o tipo.
const HP_PER_FLOOR := 2
const ATTACK_EVERY_N_FLOORS := 3

static func find_kind(id: String) -> Dictionary:
	for kind in KINDS:
		if kind.id == id:
			return kind
	if BOSS.id == id:
		return BOSS
	return {}

static func available_for_floor(floor_number: int) -> Array:
	var out: Array = []
	for kind in KINDS:
		if kind.min_floor <= floor_number:
			out.append(kind)
	if out.is_empty():
		out.append(KINDS[0])
	return out

static func pick_for_floor(floor_number: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool := available_for_floor(floor_number)
	return pool[rng.randi_range(0, pool.size() - 1)]

# Aplica a escala de andar em cima dos atributos-base do tipo.
static func scaled(kind: Dictionary, floor_number: int) -> Dictionary:
	var depth: int = maxi(0, floor_number - 1)
	var out := kind.duplicate(true)
	out.hp = int(kind.hp) + depth * HP_PER_FLOOR
	out.attack = int(kind.attack) + int(depth / ATTACK_EVERY_N_FLOORS)
	out.gold = int(kind.gold) + depth * 2
	return out

static func make_entity(kind: Dictionary, pos: Vector2i, floor_number: int) -> Entity:
	var stats := scaled(kind, floor_number)
	var enemy := Entity.new(stats.name, pos, stats.hp, stats.attack)
	enemy.set_meta("kind_id", stats.id)
	enemy.set_meta("tile", stats.tile)
	enemy.set_meta("tint", stats.tint)
	enemy.set_meta("aggro", stats.aggro)
	enemy.set_meta("gold", stats.gold)
	enemy.set_meta("boss", stats.get("boss", false))
	return enemy
