extends SceneTree

# Ferramenta de diagnóstico: acompanha UMA fase segundo a segundo e desenha o
# vale em ASCII, pra ver o que o incêndio está realmente fazendo em vez de
# adivinhar pelo placar final.
#
# Foi ela que mostrou por que a fase "Sede" era invencível: o bot cercava quase
# toda casa e faltava sempre uma célula do anel, por onde o fogo entrava. Um
# placar de fim de partida nunca teria contado isso.

const STEP := 0.1

func _initialize() -> void:
	await process_frame
	var index := 3
	var mission := Mission.new()
	mission.start(index)
	var bot := ContainmentBot.new()
	bot.setup(mission)

	var t := 0.0
	var next_report := 0.0
	while mission.phase == Mission.PLAYING and t < 120.0:
		bot.update(STEP)
		mission.update(STEP)
		t += STEP
		if t >= next_report:
			next_report += 20.0
			_report(mission, t)
	_report(mission, t)
	print("fim: %s  %s" % [mission.phase, mission.outcome])
	quit(0)

func _report(mission: Mission, t: float) -> void:
	var sim := mission.sim
	print("")
	print("t=%.0fs  casas=%d/%d  queimando=%d  agua=%d  ordens=%d (feitas %d, perdidas %d)  civis salvos=%d perdidos=%d" % [
		t, sim.houses_standing(), sim.houses_total(), sim.burning_count(),
		mission.water_left, mission.agents.pending_orders(),
		mission.agents.orders_done, mission.agents.orders_lost,
		mission.agents.safe_count, mission.agents.lost_count,
	])
	var order_cells := {}
	for order in mission.agents.orders:
		order_cells[order.cell] = true
	var crew_cells := {}
	for person in mission.agents.crew:
		crew_cells[person.cell()] = person.state.substr(0, 1)
	for y in sim.rows:
		var line := ""
		for x in sim.cols:
			var cell := Vector2i(x, y)
			var idx := sim.index_of(x, y)
			if crew_cells.has(cell):
				line += String(crew_cells[cell]).to_upper()
			elif order_cells.has(cell):
				line += "?"
			elif sim.state[idx] == FireSim.BURNING:
				line += "@"
			elif sim.state[idx] == FireSim.BURNT:
				line += " "
			elif sim.kind[idx] == Terrain.HOUSE:
				line += "H"
			elif sim.kind[idx] == Terrain.DIRT:
				line += "_"
			elif sim.kind[idx] == Terrain.ROCK:
				line += "#"
			elif sim.kind[idx] == Terrain.WATER:
				line += "~"
			elif sim.kind[idx] == Terrain.TREE:
				line += "T"
			elif sim.kind[idx] == Terrain.BRUSH:
				line += ","
			else:
				line += "."
		print(line)
