class_name Nav
extends RefCounted

# Como se anda num vale que está pegando fogo.
#
# O A* do Projeto 5 resolvia um problema estático: as casas ficam onde estão, e
# o caminho só muda quando a colônia cresce. Aqui o mapa de custo é o próprio
# incêndio — cada célula fica mais cara conforme esquenta e vira PAREDE quando
# acende. O mesmo trajeto que era o melhor há dez segundos pode estar fechado
# agora, e é por isso que os pesos são reconstruídos periodicamente e os
# agentes recalculam a rota em vez de guardá-la até o fim.
#
# É também o que dá peso à posição dos brigadistas: mandar um deles pro outro
# lado da frente não é uma caminhada mais longa, é uma caminhada em volta do
# incêndio inteiro — ou impossível.

const REFRESH := 0.6             # segundos entre reconstruções do mapa de custo
# Calor encarece MUITO: um agente prefere um desvio longo a passar raspando na
# frente de fogo. Sem isso o A* corta pela borda das chamas (que ainda não é
# parede) e o brigadista parece suicida.
const HEAT_WEIGHT := 8.0
# Mesmo perto do fogo, um caminho existe: o peso máximo é alto, não infinito,
# senão um agente cercado simplesmente congela em vez de tentar sair correndo.
const MAX_WEIGHT := 12.0

var grid := AStarGrid2D.new()
var cols := 0
var rows := 0

var _sim: FireSim = null
var _clock := 0.0
# Sobe a cada reconstrução: quem guardou uma rota sabe que ela envelheceu.
var version := 0

func setup(sim: FireSim) -> void:
	_sim = sim
	cols = sim.cols
	rows = sim.rows
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, cols, rows)
	grid.cell_size = Vector2(Layout.CELL, Layout.CELL)
	grid.offset = Vector2(Layout.CELL, Layout.CELL) * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	rebuild()

func tick(delta: float) -> bool:
	_clock += delta
	if _clock < REFRESH:
		return false
	_clock = 0.0
	rebuild()
	return true

func rebuild() -> void:
	if _sim == null:
		return
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			var idx := _sim.index_of(x, y)
			var blocked: bool = _sim.state[idx] == FireSim.BURNING or not Terrain.is_walkable(_sim.kind[idx])
			grid.set_point_solid(cell, blocked)
			if not blocked:
				var danger: float = _sim.danger_at(x, y)
				grid.set_point_weight_scale(cell, minf(MAX_WEIGHT, 1.0 + HEAT_WEIGHT * danger))
	version += 1

func is_blocked(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return true
	return grid.is_point_solid(cell)

func nearest_free(cell: Vector2i) -> Vector2i:
	var clamped := Vector2i(clampi(cell.x, 0, cols - 1), clampi(cell.y, 0, rows - 1))
	if not is_blocked(clamped):
		return clamped
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var probe := clamped + Vector2i(dx, dy)
				if not is_blocked(probe):
					return probe
	return clamped

# Caminho em células. Vazio significa "não dá" — e quem chamou precisa tratar
# isso como informação de jogo (um brigadista sem rota desiste da ordem; um
# civil sem rota entra em pânico), não como erro.
func path(from: Vector2i, to: Vector2i) -> Array:
	if _sim == null:
		return []
	var start := nearest_free(from)
	var goal := to
	if is_blocked(goal):
		goal = nearest_free(goal)
	if start == goal:
		return []
	var cells := grid.get_id_path(start, goal)
	var out: Array = []
	for i in range(1, cells.size()):
		out.append(cells[i])
	return out

# O destino ainda vale a pena, ou o fogo fechou o caminho? Usado antes de
# gastar a caminhada.
func reachable(from: Vector2i, to: Vector2i) -> bool:
	return from == to or not path(from, to).is_empty()

# ---- fuga ----

# Pra onde corre quem está com medo. Primeiro tenta o abrigo alcançável mais
# perto; se todos estiverem cortados, faz uma varredura em largura e devolve a
# célula segura mais próxima que der pra alcançar.
#
# Devolver "o abrigo mais perto em linha reta" seria pior do que não ajudar:
# num vale partido ao meio pelo fogo, o abrigo mais perto costuma ser o do
# outro lado da frente, e o civil andaria direto pra dentro dela.
func flee_target(from: Vector2i, shelters: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_cost := 1e9
	for shelter in shelters:
		var route := path(from, shelter)
		if route.is_empty() and from != shelter:
			continue
		if cost_of(route) < best_cost:
			best_cost = cost_of(route)
			best = shelter
	if best.x >= 0:
		return best
	return safest_nearby(from)

# O preço de um trajeto, não o comprimento dele. A distinção decidiu vida e
# morte no teste: contando passos, um morador escolhia o abrigo mais perto em
# número de células — que numa das fases ficava a quatro passos do foco do
# incêndio — e corria alegremente pra dentro do fogo. Somando o perigo de cada
# célula do caminho, o abrigo mais longe e frio ganha do mais perto e quente,
# que é o que uma pessoa faria.
const FLEE_DANGER_COST := 9.0

func cost_of(route: Array) -> float:
	var total := float(route.size())
	for cell in route:
		total += FLEE_DANGER_COST * _sim.danger_at(cell.x, cell.y)
	return total

const SAFE_SEARCH_LIMIT := 260

func safest_nearby(from: Vector2i) -> Vector2i:
	var start := nearest_free(from)
	var seen := {start: true}
	var queue: Array = [start]
	var best := start
	var best_danger := _sim.danger_at(start.x, start.y)
	var visited := 0
	while not queue.is_empty() and visited < SAFE_SEARCH_LIMIT:
		var cell: Vector2i = queue.pop_front()
		visited += 1
		var danger := _sim.danger_at(cell.x, cell.y)
		if danger < best_danger - 0.02:
			best_danger = danger
			best = cell
			if danger <= 0.01:
				break
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var probe := cell + Vector2i(dx, dy)
				if seen.has(probe) or is_blocked(probe):
					continue
				seen[probe] = true
				queue.append(probe)
	return best
