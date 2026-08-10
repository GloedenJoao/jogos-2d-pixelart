extends SceneTree

# Ferramenta de calibração: mede o tempo real de acomodação do autômato de
# água em vez de chutar FLOW_RATE. Não faz parte da suíte — roda antes de
# mexer numa constante de water_sim.gd, pra saber o que está prestes a mudar.
#
# A pergunta que importa pro jogo não é "a água equaliza?" (isso o teste de
# unidade já garante) — é "quando o jogador cava um canal, dá pra VER a água
# escoando, ou ela pisca de um estado pro outro?". Por isso a métrica aqui é
# tempo em segundos, não número de ticks.

func _initialize() -> void:
	await process_frame
	_measure_pair_settling()
	_measure_corridor_arrival()
	_measure_valley_pooling()
	quit(0)

# Dois vizinhos planos com um desnível de água grande: quanto tempo até a
# diferença de superfície cair pra perto de zero?
func _measure_pair_settling() -> void:
	print("--- acomodação entre duas células planas (desnível inicial 10.0) ---")
	for tolerance in [1.0, 0.1, 0.01]:
		var sim := WaterSim.new()
		sim.setup(2, 1, PackedFloat32Array([0.0, 0.0]))
		sim.add_water(0, 0, 10.0)
		var steps := 0
		var limit := 2000
		while sim.max_surface_gap() > tolerance and steps < limit:
			sim.advance(WaterSim.TICK)
			steps += 1
		print("  gap <= %.2f: %4d passos (%.2fs)%s" % [tolerance, steps, sim.elapsed, "  [NUNCA CHEGOU]" if steps >= limit else ""])

# Corredor 1×N raso: água despejada numa ponta, mede quando cada célula recebe
# o primeiro volume perceptível — o equivalente à "velocidade de frente" do
# fogo, mas pra um processo difusivo (não convectivo: não deve escalar linear
# com a distância, e é isso que este print deixa visível).
func _measure_corridor_arrival() -> void:
	print("--- chegada de água num corredor plano de 20 células ---")
	var n := 20
	var heights := PackedFloat32Array()
	heights.resize(n)
	var sim := WaterSim.new()
	sim.setup(n, 1, heights)
	sim.add_water(0, 0, 40.0)
	var arrival := {}
	var threshold := 0.05
	var limit := 4000
	while sim.ticks < limit and arrival.size() < n:
		sim.advance(WaterSim.TICK)
		for x in n:
			if not arrival.has(x) and sim.water_at(x, 0) >= threshold:
				arrival[x] = sim.elapsed
	for x in [1, 5, 10, 15, 19]:
		if arrival.has(x):
			print("  célula %2d: %.2fs" % [x, arrival[x]])
		else:
			print("  célula %2d: NUNCA (em %.1fs de simulação)" % [x, sim.elapsed])

# Vale [3,0,3] com volume crescente: confirma visualmente que o ponto baixo
# sempre acumula mais e que o par de bordas simétricas recebe volume igual —
# a mesma checagem do teste de unidade, aqui como leitura humana.
#
# Com volume=1.0 o "passos" bate no teto (3000): a água nem chega a molhar as
# bordas (altura 3), então a diferença de superfície entre o fundo molhado e a
# borda seca nunca cai abaixo da tolerância — não é a simulação travada, é o
# vale genuinamente não ter enchido até a borda. Os valores impressos (bordas
# em 0.000) já são o resultado final, atingido bem antes do teto.
func _measure_valley_pooling() -> void:
	print("--- vale [3, 0, 3], volume variável ---")
	for volume in [1.0, 3.0, 5.0, 10.0]:
		var sim := WaterSim.new()
		sim.setup(3, 1, PackedFloat32Array([3.0, 0.0, 3.0]))
		sim.add_water(0, 0, volume)
		var steps := 0
		while sim.max_surface_gap() > 0.01 and steps < 3000:
			sim.advance(WaterSim.TICK)
			steps += 1
		print("  volume=%5.1f -> bordas=%.3f/%.3f  fundo=%.3f  (%d passos)" % [
			volume, sim.water_at(0, 0), sim.water_at(2, 0), sim.water_at(1, 0), steps])
