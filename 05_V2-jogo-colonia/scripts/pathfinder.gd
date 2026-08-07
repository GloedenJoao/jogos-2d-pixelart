class_name Pathfinder
extends RefCounted

# Como o morador atravessa o vale.
#
# No V1 todo mundo andava em LINHA RETA até o destino — o que significa passar
# por dentro das casas. Aqui o vale vira uma grade de navegação: os lotes 2×2
# das construções são sólidos, e o caminho sai de um A* (AStarGrid2D, que é
# classe de núcleo do Godot e roda headless, então continua tudo testável).
#
# Duas coisas fazem esse caminho não parecer "de robô":
#
#   * **Corte de esquina** (`_smooth`): o A* devolve um caminho em escada; se a
#     reta entre dois pontos não cruza nada sólido, os pontos do meio caem fora.
#   * **Trilha de pisoteio** (`wear`): cada célula conta quantas vezes foi
#     pisada. Passando do limiar, ela vira caminho de terra — mais barata pro
#     A*, então o próximo morador tende a usá-la. As trilhas da colônia se
#     desenham sozinhas, do jeito que gente de verdade faz atalho na grama.

const TRAIL_THRESHOLD := 26.0     # pisadas até a célula concorrer a virar trilha
# Teto alto de propósito: é o que dá RANKING. Se todas as células cheias
# empatassem no máximo, a escolha das TRAIL_LIMIT mais pisadas viraria sorteio
# e a estrada mudaria de lugar sozinha a cada varredura.
const TRAIL_MAX := 400.0
# Devagar: uma colônia de cinco pessoas também tem que conseguir abrir caminho.
# Quem impede o vale de virar terra batida é o teto de células, não o esquecimento.
const TRAIL_DECAY := 0.10         # por segundo: trilha sem uso volta a ser mato
const TRAIL_WEIGHT := 0.55        # andar na trilha custa ~metade
const PLOT_MARGIN_WEIGHT := 1.35  # encostar na parede da casa custa mais

# Teto de células que podem ser trilha ao mesmo tempo. Sem ele, uma colônia
# grande pisa em TUDO e o vale inteiro vira terra batida — o que não lê como
# "caminho", lê como "alguém arou o mapa". Com teto, só as células mais
# pisadas ganham o status, e o que sobra é uma malha de estradas.
const TRAIL_LIMIT := 46
const REBUILD_INTERVAL := 2.0

var grid := AStarGrid2D.new()
var wear: Dictionary = {}         # Vector2i -> float
var solid: Dictionary = {}        # Vector2i -> true

var _trail_cells: Dictionary = {} # Vector2i -> true (as que já passaram do limiar)
var _decay_clock := 0.0
# Sobe toda vez que a malha de trilhas muda; a cena só redesenha quando muda.
var trails_version := 0

func _init() -> void:
	grid.region = Rect2i(0, 0, Valley.COLS, Valley.ROWS)
	grid.cell_size = Vector2(Valley.CELL, Valley.CELL)
	grid.offset = Vector2(Valley.CELL, Valley.CELL) * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

# Chamado quando a colônia muda de forma (comprou construção, virou era).
# `built_ids` são os tipos de construção que já existem no vale.
func rebuild(built_ids: Array) -> void:
	solid.clear()
	for y in Valley.ROWS:
		for x in Valley.COLS:
			grid.set_point_solid(Vector2i(x, y), false)
			grid.set_point_weight_scale(Vector2i(x, y), 1.0)

	for id in built_ids:
		var origin: Vector2i = Valley.plot_cell(id)
		for dx in 2:
			for dy in 2:
				var cell := origin + Vector2i(dx, dy)
				if _inside(cell):
					solid[cell] = true
					grid.set_point_solid(cell, true)

	# Uma casa não tem só a parede: quem passa raspando nela lê como se
	# atravessasse o muro. Encarecer o anel em volta empurra o caminho pra fora.
	for cell in solid.keys():
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var around: Vector2i = cell + Vector2i(dx, dy)
				if _inside(around) and not solid.has(around):
					grid.set_point_weight_scale(around, PLOT_MARGIN_WEIGHT)

	for cell in _trail_cells.keys():
		if _inside(cell) and not solid.has(cell):
			grid.set_point_weight_scale(cell, TRAIL_WEIGHT)

func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < Valley.COLS and cell.y < Valley.ROWS

func is_solid(cell: Vector2i) -> bool:
	return solid.has(cell)

static func cell_of(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / Valley.CELL), floori(position.y / Valley.CELL))

static func center_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * Valley.CELL

# Empurra uma célula sólida para a vizinha livre mais próxima: um morador que
# nasceu (ou foi salvo) em cima de uma casa ainda precisa conseguir sair.
func nearest_free(cell: Vector2i) -> Vector2i:
	var clamped := Vector2i(clampi(cell.x, 0, Valley.COLS - 1), clampi(cell.y, 0, Valley.ROWS - 1))
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

# Devolve os pontos (em pixels do mundo) que o morador precisa visitar. O
# destino REAL entra no fim: o A* trabalha em centros de célula, mas o posto de
# trabalho fica num ponto exato dentro dela.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := nearest_free(cell_of(from))
	var goal := nearest_free(cell_of(to))
	if start == goal:
		return PackedVector2Array([to])

	var cells := grid.get_id_path(start, goal)
	if cells.is_empty():
		# Sem rota (colônia mal formada, destino ilhado): linha reta é melhor
		# que o morador congelar no lugar.
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

# Corte de esquina: mantém um ponto só quando a reta até o próximo cruzaria algo
# sólido. É o que transforma a escada do A* num trajeto que parece decidido.
# Existe rota de verdade, ou `find_path` cairia no fallback em linha reta? O
# fallback é indistinguível de um caminho curto olhando só o resultado, e a
# diferença importa: um posto inalcançável é bug de layout do vale.
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

# Amostra a reta a cada meia célula: barato e suficiente pra saber se o atalho
# atravessa uma casa.
func line_is_clear(a: Vector2, b: Vector2) -> bool:
	var distance := a.distance_to(b)
	var steps := maxi(2, int(distance / (Valley.CELL * 0.5)))
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

# Trilha que ninguém usa mais volta a ser mato, e só as TRAIL_LIMIT células mais
# pisadas contam como estrada. Roda em passos grandes (não todo frame) porque é
# varredura e ordenação de dicionário.
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

# ---- persistência ----

func to_dict() -> Dictionary:
	var packed: Array = []
	for cell in wear.keys():
		packed.append([cell.x, cell.y, snappedf(float(wear[cell]), 0.1)])
	return {"wear": packed}

func from_dict(data: Dictionary) -> void:
	wear.clear()
	_trail_cells.clear()
	var packed = data.get("wear", [])
	if not (packed is Array):
		return
	var restored: Array = []
	for entry in packed:
		if entry is Array and entry.size() == 3:
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			if not _inside(cell):
				continue
			var value: float = clampf(float(entry[2]), 0.0, TRAIL_MAX)
			wear[cell] = value
			if value >= TRAIL_THRESHOLD:
				restored.append(cell)
	# O mesmo teto do jogo rodando vale pro save: um arquivo antigo (ou
	# adulterado) não pode reabrir com o vale inteiro coberto de estrada.
	restored.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(wear[a]) > float(wear[b]))
	if restored.size() > TRAIL_LIMIT:
		restored.resize(TRAIL_LIMIT)
	for cell in restored:
		_trail_cells[cell] = true
	trails_version += 1
