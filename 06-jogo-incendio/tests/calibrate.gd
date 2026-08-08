extends SceneTree

# Ferramenta de calibração: mede a velocidade da frente de fogo em cada
# condição, pra escolher as constantes de FireSim com número em vez de chute.
#
# Não faz parte da suíte — é o que se roda ANTES de mexer numa constante do
# fogo, pra saber o que se está prestes a quebrar. As faixas que este script
# produziu viraram asserção em run_tests.gd.

func _initialize() -> void:
	await process_frame
	_measure("capim plano, sem vento", Terrain.GRASS, 0.0, 0.0)
	_measure("capim, vento a favor 1.0", Terrain.GRASS, 1.0, 0.0)
	_measure("capim, vento contra 1.0", Terrain.GRASS, -1.0, 0.0)
	_measure("mato plano, sem vento", Terrain.BRUSH, 0.0, 0.0)
	_measure("mata plana, sem vento", Terrain.TREE, 0.0, 0.0)
	_measure("lavoura plana, sem vento", Terrain.FIELD, 0.0, 0.0)
	_measure("capim, subida de 1/celula", Terrain.GRASS, 0.0, 1.0)
	_measure("capim, descida de 1/celula", Terrain.GRASS, 0.0, -1.0)
	_measure("capim molhado (0.85)", Terrain.GRASS, 0.0, 0.0, true)
	quit(0)

func _measure(label: String, terrain: int, wind_x: float, slope: float, wet: bool = false) -> void:
	var cols := 30
	var rows := 5
	var kinds := PackedInt32Array()
	var heights := PackedFloat32Array()
	kinds.resize(cols * rows)
	heights.resize(cols * rows)
	for y in rows:
		for x in cols:
			kinds[y * cols + x] = terrain
			heights[y * cols + x] = slope * x

	var sim := FireSim.new()
	sim.setup(cols, rows, kinds, heights, 1234)
	# Vento apontando em +x (a favor) ou -x (contra).
	if absf(wind_x) > 0.01:
		sim.set_wind(0.0 if wind_x > 0.0 else PI, absf(wind_x), 0.0, 24.0)
	else:
		sim.set_wind(0.0, 0.0, 0.0, 24.0)
	if wet:
		for y in rows:
			for x in cols:
				sim.moisture[y * cols + x] = 0.85

	sim.ignite(0, 2)
	var arrival := {}
	var limit := 6000
	while sim.ticks < limit:
		sim.advance(FireSim.TICK)
		for x in cols:
			if not arrival.has(x) and sim.state_at(x, 2) != FireSim.INTACT:
				arrival[x] = sim.elapsed
		if arrival.has(cols - 1):
			break
		if sim.is_out():
			break

	var reached: int = arrival.size()
	if reached < 6:
		print("%-32s FRENTE MORREU apos %d celulas (%.1fs)" % [label, reached, sim.elapsed])
		return
	# Velocidade medida no miolo (longe da célula acesa à mão e da borda).
	var a: float = arrival.get(5, 0.0)
	var b: float = arrival.get(mini(reached - 1, 20), 0.0)
	var span: int = mini(reached - 1, 20) - 5
	var per_cell: float = (b - a) / maxf(1.0, float(span))
	print("%-32s %5.2f s/celula   alcance=%d   total=%.1fs" % [label, per_cell, reached, sim.elapsed])
