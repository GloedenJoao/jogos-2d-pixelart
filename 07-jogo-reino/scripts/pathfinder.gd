class_name Pathfinder
extends RefCounted

# Como o trabalhador atravessa o mapa. Portado de
# 05_V2-jogo-colonia/scripts/pathfinder.gd (mesma técnica, validada lá),
# generalizado pra não depender de uma classe `Valley` fixa: aqui quem chama
# `setup()` decide dimensão e tamanho de célula, e `rebuild()` recebe a lista
# de células sólidas de fora (o Reino não tem "lote 2×2 por tipo de
# construção" — cada prédio ocupa a própria célula).
#
# Duas coisas fazem esse caminho não parecer "de robô":
#
#   * **Corte de esquina** (`_smooth`): o A* devolve um caminho em escada; se a
#     reta entre dois pontos não cruza nada sólido, os pontos do meio caem fora.
#   * **Trilha de pisoteio** (`wear`): cada célula conta quantas vezes foi
#     pisada. Passando do limiar, ela vira caminho de terra — mais barata pro
#     A*, então o próximo trabalhador tende a usá-la.

const TRAIL_THRESHOLD := 26.0     # pisadas até a célula concorrer a virar trilha
const TRAIL_MAX := 400.0
const TRAIL_DECAY := 0.10         # por segundo: trilha sem uso volta a ser mato
const TRAIL_WEIGHT := 0.55        # andar na trilha custa ~metade
const SOLID_MARGIN_WEIGHT := 1.35 # encostar num sólido custa mais
const TRAIL_LIMIT := 46
const REBUILD_INTERVAL := 2.0

var cols := 0
var rows := 0
var cell_size := 16.0

var grid := AStarGrid2D.new()
var wear: Dictionary = {}         # Vector2i -> float
var solid: Dictionary = {}        # Vector2i -> true

var _trail_cells: Dictionary = {} # Vector2i -> true (as que já passaram do limiar)
var _decay_clock := 0.0
var trails_version := 0

func setup(map_cols: int, map_rows: int, map_cell_size: float) -> void:
	cols = map_cols
	rows = map_rows
	cell_size = map_cell_size
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, cols, rows)
	grid.cell_size = Vector2(cell_size, cell_size)
	grid.offset = Vector2(cell_size, cell_size) * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	wear.clear()
	solid.clear()
	_trail_cells.clear()
	_decay_clock = 0.0
	trails_version = 0

# Chamado quando o mapa muda de forma (prédio novo). `solid_cells` é a lista
# completa de células sólidas atuais — não incremental.
func rebuild(solid_cells: Array) -> void:
	solid.clear()
	for y in rows:
		for x in cols:
			grid.set_point_solid(Vector2i(x, y), false)
			grid.set_point_weight_scale(Vector2i(x, y), 1.0)

	for cell in solid_cells:
		if _inside(cell):
			solid[cell] = true
			grid.set_point_solid(cell, true)

	# Quem passa raspando numa parede lê como se atravessasse ela. Encarecer o
	# anel em volta empurra o caminho pra fora.
	for cell in solid.keys():
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var around: Vector2i = cell + Vector2i(dx, dy)
				if _inside(around) and not solid.has(around):
					grid.set_point_weight_scale(around, SOLID_MARGIN_WEIGHT)

	for cell in _trail_cells.keys():
		if _inside(cell) and not solid.has(cell):
			grid.set_point_weight_scale(cell, TRAIL_WEIGHT)

func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows

func is_solid(cell: Vector2i) -> bool:
	return solid.has(cell)

func cell_of(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))

func center_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size

# Empurra uma célula sólida para a vizinha livre mais próxima: um trabalhador
# que nasceu (ou foi carregado) em cima de um prédio ainda precisa sair dali.
func nearest_free(cell: Vector2i) -> Vector2i:
	var clamped := Vector2i(clampi(cell.x, 0, cols - 1), clampi(cell.y, 0, rows - 1))
	if not solid.has(clamped):
		return clamped
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var probe: Vector2i = clamped + Vector2i(dx, dy)
				if _inside(probe) and not solid.has(probe):
					return probe
	return clamped

# ---- caminho ----

func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := nearest_free(cell_of(from))
	var goal := nearest_free(cell_of(to))
	if start == goal:
		return PackedVector2Array([to])

	var cells := grid.get_id_path(start, goal)
	if cells.is_empty():
		return PackedVector2Array([to])

	var points := PackedVector2Array()
	for cell in cells:
		points.append(center_of(cell))
	points = _smooth(points)
	if points.size() > 0:
		points[points.size() - 1] = to
	else:
		points.append(to)
	return points

func has_route(from: Vector2, to: Vector2) -> bool:
	var start := nearest_free(cell_of(from))
	var goal := nearest_free(cell_of(to))
	return start == goal or not grid.get_id_path(start, goal).is_empty()

func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	var anchor := 0
	var probe := 1
	while probe < points.size():
		if probe == points.size() - 1:
			out.append(points[probe])
			break
		if not line_is_clear(points[anchor], points[probe + 1]):
			out.append(points[probe])
			anchor = probe
		probe += 1
	return out

func line_is_clear(a: Vector2, b: Vector2) -> bool:
	var distance := a.distance_to(b)
	var steps := maxi(2, int(distance / (cell_size * 0.5)))
	for i in range(steps + 1):
		var point: Vector2 = a.lerp(b, float(i) / float(steps))
		if solid.has(cell_of(point)):
			return false
	return true

# ---- trilhas de pisoteio ----

func register_step(position: Vector2) -> void:
	var cell := cell_of(position)
	if not _inside(cell) or solid.has(cell):
		return
	wear[cell] = minf(float(wear.get(cell, 0.0)) + 1.0, TRAIL_MAX)

func is_trail(cell: Vector2i) -> bool:
	return _trail_cells.has(cell)

func trail_cells() -> Array:
	return _trail_cells.keys()

func decay(delta: float) -> bool:
	_decay_clock += delta
	if _decay_clock < REBUILD_INTERVAL:
		return false
	var step := _decay_clock
	_decay_clock = 0.0

	var candidates: Array = []
	for cell in wear.keys():
		var value: float = float(wear[cell]) - TRAIL_DECAY * step
		if value <= 0.0:
			wear.erase(cell)
			continue
		wear[cell] = value
		if value >= TRAIL_THRESHOLD and not solid.has(cell):
			candidates.append(cell)

	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(wear[a]) > float(wear[b]))
	if candidates.size() > TRAIL_LIMIT:
		candidates.resize(TRAIL_LIMIT)

	var next := {}
	for cell in candidates:
		next[cell] = true
	if next.size() == _trail_cells.size() and _same_set(next, _trail_cells):
		return false

	for cell in _trail_cells.keys():
		if not next.has(cell) and not solid.has(cell):
			grid.set_point_weight_scale(cell, 1.0)
	for cell in next.keys():
		grid.set_point_weight_scale(cell, TRAIL_WEIGHT)
	_trail_cells = next
	trails_version += 1
	return true

func _same_set(a: Dictionary, b: Dictionary) -> bool:
	for cell in a:
		if not b.has(cell):
			return false
	return true
