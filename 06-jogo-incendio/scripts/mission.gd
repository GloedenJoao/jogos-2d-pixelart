class_name Mission
extends RefCounted

# Uma fase em andamento: o incêndio, o vale, a turma, o orçamento e as regras
# de quando aquilo acabou e como.
#
# Junta FireSim + Nav + Agents num objeto só e NÃO depende de cena — mesma
# disciplina dos projetos anteriores, e aqui ela paga dobrado: é o que permite
# o bot dos testes jogar as seis fases de ponta a ponta, milhares de vezes mais
# rápido que tempo real, sem abrir janela.
#
# ---- por que a derrota é imediata ----
#
# Assim que as casas de pé caem abaixo da meta, ou assim que um morador se
# perde, a fase acabou — mesmo que ainda haja fogo aceso e coisas a fazer.
# Deixar a partida seguir depois de o objetivo se tornar impossível é pedir
# que o jogador descubra sozinho, dois minutos depois, que já tinha perdido.

enum { PLAYING, WON, LOST }

const SPEEDS := [1.0, 2.0, 4.0]

var level: Dictionary = {}
var parsed: Levels.Parsed = null
var sim: FireSim = null
var nav: Nav = null
var agents: Agents = null

var phase := PLAYING
var elapsed := 0.0
var water_left := 0
var backfire_left := 0
var speed_index := 0

# Por que a fase terminou, em texto curto pro jogador. Vazio enquanto joga.
var outcome := ""

func start(level_index: int) -> void:
	level = Levels.get_level(level_index)
	parsed = Levels.parse(level)
	sim = Levels.build_sim(level)
	nav = Nav.new()
	nav.setup(sim)
	agents = Agents.new()
	agents.setup(sim, nav, parsed, int(level.get("seed", 1)))

	var budget: Dictionary = level.get("budget", {})
	water_left = int(budget.get("water", 0))
	backfire_left = int(budget.get("backfire", 0))

	phase = PLAYING
	elapsed = 0.0
	speed_index = 0
	outcome = ""

func speed() -> float:
	return SPEEDS[clampi(speed_index, 0, SPEEDS.size() - 1)]

func cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()

func goal_houses() -> int:
	return int(level.get("goal_houses", 0))

func update(delta: float) -> void:
	if phase != PLAYING:
		return
	var step := delta * speed()
	elapsed += step
	sim.advance(step)
	agents.update(step)
	for cell in agents.stale_orders(step):
		cancel(cell)
	_evaluate()

# Recurso é debitado ao DAR a ordem, não ao executar: senão dava pra encher o
# mapa de ordens de água com dois baldes no bolso e ver qual delas pega.
func order(tool_id: int, cell: Vector2i) -> bool:
	if phase != PLAYING:
		return false
	if tool_id == Tools.WATER and water_left <= 0:
		return false
	if tool_id == Tools.BACKFIRE and backfire_left <= 0:
		return false
	if not agents.give_order(tool_id, cell):
		return false
	if tool_id == Tools.WATER:
		water_left -= 1
	elif tool_id == Tools.BACKFIRE:
		backfire_left -= 1
	return true

# Cancelar devolve o recurso: o custo de mudar de ideia já é o tempo que o
# brigadista gastou andando até lá.
func cancel(cell: Vector2i) -> bool:
	for existing in agents.orders:
		if existing.cell == cell:
			var tool_id: int = existing.tool_id
			if agents.cancel_order_at(cell):
				if tool_id == Tools.WATER:
					water_left += 1
				elif tool_id == Tools.BACKFIRE:
					backfire_left += 1
				return true
	return false

func remaining(tool_id: int) -> int:
	match tool_id:
		Tools.WATER:
			return water_left
		Tools.BACKFIRE:
			return backfire_left
	return -1                      # aceiro não tem conta

func _evaluate() -> void:
	if agents.lost_count > 0:
		phase = LOST
		outcome = "Alguém não saiu a tempo."
		return
	if sim.houses_standing() < goal_houses():
		phase = LOST
		outcome = "Casas demais se perderam."
		return
	if sim.is_out() and agents.all_civilians_resolved():
		phase = WON
		outcome = "O fogo apagou."

# ---- resultado ----

# Três estrelas, e cada uma cobra uma coisa diferente: a primeira é a meta da
# fase, a segunda é não abrir mão de nenhuma casa, a terceira é fazer isso
# depressa. Um jogador que só quer passar precisa da primeira; quem quer
# entender o sistema vai atrás da terceira.
func stars() -> int:
	if phase != WON:
		return 0
	var earned := 1
	if sim.houses_standing() == sim.houses_total():
		earned += 1
	if elapsed <= float(level.get("par_time", 999.0)):
		earned += 1
	return earned

func summary() -> Dictionary:
	return {
		"level": level.get("id", ""),
		"won": phase == WON,
		"stars": stars(),
		"time": snappedf(elapsed, 0.1),
		"houses": sim.houses_standing(),
		"houses_total": sim.houses_total(),
		"saved": agents.safe_count,
		"civilians": agents.civilians_total(),
		"burnt": sim.cells_burnt,
	}

# ---- progresso entre fases ----

const SAVE_KEY := "incendio"

static func load_progress(save_system) -> Dictionary:
	var raw = save_system.get_value(SAVE_KEY, {})
	if not (raw is Dictionary):
		return {"levels": {}, "unlocked": 1}
	var progress: Dictionary = raw.duplicate(true)
	if not progress.has("levels") or not (progress["levels"] is Dictionary):
		progress["levels"] = {}
	progress["unlocked"] = clampi(int(progress.get("unlocked", 1)), 1, Levels.count())
	return progress

# Guarda o MELHOR resultado, nunca o último: reabrir uma fase vencida com três
# estrelas e sair no meio não pode apagar o que já foi feito.
static func record(save_system, level_index: int, result: Dictionary) -> Dictionary:
	var progress := load_progress(save_system)
	var id: String = String(result.get("level", ""))
	var levels: Dictionary = progress["levels"]
	var previous: Dictionary = levels.get(id, {"stars": 0, "time": 0.0})
	var stars_now := int(result.get("stars", 0))
	var best_stars: int = maxi(int(previous.get("stars", 0)), stars_now)
	var best_time: float = float(previous.get("time", 0.0))
	if bool(result.get("won", false)):
		var time_now := float(result.get("time", 0.0))
		best_time = time_now if best_time <= 0.0 else minf(best_time, time_now)
		progress["unlocked"] = clampi(maxi(int(progress["unlocked"]), level_index + 2), 1, Levels.count())
	levels[id] = {"stars": best_stars, "time": snappedf(best_time, 0.1)}
	progress["levels"] = levels
	save_system.set_value(SAVE_KEY, progress)
	save_system.save_data()
	return progress
