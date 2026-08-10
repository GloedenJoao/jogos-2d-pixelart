extends SceneTree

# Testes headless da Fase 0 — o autômato de água (water_sim.gd).
#
# Não existe jogo pra jogar ainda (ver plano em docs/plano-projeto7-reino.md);
# esta suíte protege a única coisa que a Fase 0 promete: que "abrir um canal"
# ou "represar" produzem física correta. A regressão mais perigosa aqui não é
# uma exceção — é a CONSERVAÇÃO. Um autômato de calor pode inventar ou perder
# energia sem que ninguém note a olho nu; água que se multiplica ou some
# silenciosamente destrói a promessa central do jogo ("engenharia de terreno
# de verdade") sem derrubar nenhum teste ingênuo.

const TICK := 0.1
# Tolerância por ARESTA, não fim a fim: um corredor de N células pode acumular
# até (N-1) vezes esta folga entre as duas pontas mesmo com toda aresta já
# "acomodada" (foi o que a suíte pegou: 0.02 por aresta bastava pra `_settle`
# sair cedo, mas ainda deixava ~0.06 de diferença entre as duas pontas de um
# corredor de 5 células). Manter isto pequeno é o que faz a folga acumulada
# ainda caber dentro da tolerância dos testes de equilíbrio global.
const SETTLE_TOLERANCE := 0.005
const SETTLE_LIMIT := 4000

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame

	_test_setup()
	_test_flat_pair_equalizes()
	_test_water_flows_downhill_and_pools()
	_test_isolated_cell_keeps_its_water()
	_test_wall_blocks_until_canal_is_dug()
	_test_dam_blocks_until_gate_opens()
	_test_conservation_holds_across_scenarios()
	_test_no_negative_and_no_water_in_walls()
	_test_fixed_timestep_independence()
	_test_huge_delta_does_not_runaway()

	print("")
	if _fail == 0:
		print("TODOS OS TESTES PASSARAM (%d asserções)" % _pass)
	else:
		print("FALHARAM %d de %d asserções" % [_fail, _pass + _fail])
	quit(1 if _fail > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FALHOU: %s" % label)

func _near(a: float, b: float, tolerance: float, label: String) -> void:
	_check(absf(a - b) <= tolerance, "%s (%.4f vs %.4f)" % [label, a, b])

# ---- helpers ----

func _line_sim(heights: Array) -> WaterSim:
	var sim := WaterSim.new()
	var arr := PackedFloat32Array()
	for h in heights:
		arr.append(h)
	sim.setup(heights.size(), 1, arr)
	return sim

# Roda até a maior diferença de superfície entre vizinhos molhados cair abaixo
# da tolerância, ou até o teto de passos (pra nunca travar um teste em loop
# infinito se uma mudança futura quebrar a convergência).
func _settle(sim: WaterSim, tolerance: float = SETTLE_TOLERANCE, limit: int = SETTLE_LIMIT) -> int:
	var steps := 0
	while sim.max_surface_gap() > tolerance and steps < limit:
		sim.advance(TICK)
		steps += 1
	return steps

# ---- testes ----

func _test_setup() -> void:
	var sim := _line_sim([0.0, 0.0, 0.0])
	_check(sim.cols == 3 and sim.rows == 1, "dimensões da grade de teste")
	_check(sim.total_water() == 0.0, "grade nova começa seca")
	sim.add_water(1, 0, 5.0)
	_check(sim.water_at(1, 0) == 5.0, "add_water deposita no lugar certo")
	_check(sim.water_at(0, 0) == 0.0, "add_water não vaza pros vizinhos antes de nenhum tick rodar")

func _test_flat_pair_equalizes() -> void:
	var sim := _line_sim([0.0, 0.0])
	sim.add_water(0, 0, 10.0)
	var steps := _settle(sim)
	_check(steps > 0 and steps < SETTLE_LIMIT, "duas células planas acomodam dentro do teto de passos")
	_near(sim.water_at(0, 0), 5.0, 0.05, "água se divide igual entre duas células planas")
	_near(sim.water_at(1, 0), 5.0, 0.05, "água se divide igual entre duas células planas (par)")

# Vale: [3, 0, 3]. Água despejada na borda esquerda tem que escoar pro fundo
# do vale e, com volume suficiente, transbordar até molhar a borda direita
# também (comunicação pelas duas arestas), sempre com a mesma superfície nos
# três pontos que continuam molhados.
func _test_water_flows_downhill_and_pools() -> void:
	var sim := _line_sim([3.0, 0.0, 3.0])
	sim.add_water(0, 0, 5.0)
	_settle(sim)
	_check(sim.water_at(1, 0) > sim.water_at(0, 0), "o fundo do vale acumula mais água que a borda")
	_near(sim.water_at(0, 0), sim.water_at(2, 0), 0.05, "vale simétrico acumula água simétrica nas bordas")
	_near(sim.surface_at(0, 0), sim.surface_at(1, 0), SETTLE_TOLERANCE, "superfície equalizada: borda e fundo")
	_near(sim.surface_at(1, 0), sim.surface_at(2, 0), SETTLE_TOLERANCE, "superfície equalizada: fundo e outra borda")
	# Solução analítica pra este caso (ver tests/calibrate.gd): com heights
	# [3,0,3] e volume total 5, a superfície de equilíbrio é 11/3.
	_near(sim.surface_at(1, 0), 11.0 / 3.0, 0.05, "nível de equilíbrio bate com a solução fechada")

func _test_isolated_cell_keeps_its_water() -> void:
	var sim := WaterSim.new()
	var heights := PackedFloat32Array([0.0])
	sim.setup(1, 1, heights)
	sim.add_water(0, 0, 3.0)
	for _i in 50:
		sim.advance(TICK)
	_near(sim.water_at(0, 0), 3.0, 0.0001, "célula sem vizinho não tem pra onde escoar")

# Muro alto (altura 5) entre dois vales rasos: água despejada de um lado não
# pode aparecer do outro lado até o jogador cavar o muro (baixar a altura).
func _test_wall_blocks_until_canal_is_dug() -> void:
	var sim := _line_sim([0.0, 0.0, 5.0, 0.0, 0.0])
	sim.add_water(0, 0, 2.0)
	_settle(sim)
	_check(sim.water_at(3, 0) == 0.0 and sim.water_at(4, 0) == 0.0, "muro intacto: nada atravessa")
	_near(sim.water_at(0, 0), sim.water_at(1, 0), 0.05, "os dois lados de cá do muro equalizam entre si")

	sim.set_height(2, 0, 0.0)
	_settle(sim)
	_check(sim.water_at(3, 0) > 0.0 and sim.water_at(4, 0) > 0.0, "canal cavado: água agora alcança o outro lado")
	_near(sim.surface_at(0, 0), sim.surface_at(4, 0), 0.05, "depois do canal, superfície equalizada ponta a ponta")

# Represa: bloqueia mesmo com desnível favorável do lado bloqueado. Comporta
# aberta depois libera o fluxo represado sem precisar recriar a simulação.
func _test_dam_blocks_until_gate_opens() -> void:
	var sim := _line_sim([0.0, 0.0, 0.0])
	sim.set_blocked(1, 0, true)
	sim.add_water(0, 0, 4.0)
	_settle(sim)
	_check(sim.water_at(2, 0) == 0.0, "represa fechada: nada passa pro outro lado")
	_check(sim.water_at(1, 0) == 0.0, "a própria represa nunca guarda água")
	_near(sim.water_at(0, 0), 4.0, 0.01, "água represada fica inteira do lado de origem")

	sim.set_blocked(1, 0, false)
	_settle(sim)
	_check(sim.water_at(2, 0) > 0.0, "comporta aberta: água agora alcança o outro lado")

func _test_conservation_holds_across_scenarios() -> void:
	var flat := _line_sim([0.0, 0.0, 0.0, 0.0])
	flat.add_water(0, 0, 7.0)
	for _i in 300:
		flat.advance(TICK)
	_near(flat.total_water(), 7.0, 0.001, "conservação em terreno plano")

	var valley := _line_sim([2.0, 0.0, 1.0, 3.0])
	valley.add_water(0, 0, 3.0)
	valley.add_water(3, 0, 1.5)
	for _i in 300:
		valley.advance(TICK)
	_near(valley.total_water(), 4.5, 0.001, "conservação em relevo irregular")

	var dammed := _line_sim([0.0, 0.0, 0.0, 0.0, 0.0])
	dammed.set_blocked(2, 0, true)
	dammed.add_water(0, 0, 5.0)
	dammed.add_water(4, 0, 2.0)
	for _i in 300:
		dammed.advance(TICK)
	_near(dammed.total_water(), 7.0, 0.001, "conservação com represa no meio")

func _test_no_negative_and_no_water_in_walls() -> void:
	var sim := _line_sim([0.0, 0.0, 0.0])
	sim.set_blocked(1, 0, true)
	sim.add_water(0, 0, 0.3)
	for _i in 200:
		sim.advance(TICK)
		for idx in sim.water.size():
			if sim.water[idx] < 0.0:
				_check(false, "água nunca fica negativa")
				return
	_check(sim.water_at(1, 0) == 0.0, "represa continua seca no fim da simulação")

func _test_fixed_timestep_independence() -> void:
	var a := _line_sim([3.0, 0.0, 3.0])
	var b := _line_sim([3.0, 0.0, 3.0])
	a.add_water(0, 0, 5.0)
	b.add_water(0, 0, 5.0)
	for _i in 200:
		a.advance(0.1)
		b.advance(0.05)
		b.advance(0.05)
	_check(a.ticks == b.ticks, "mesmo número de passos (%d vs %d)" % [a.ticks, b.ticks])
	for idx in a.water.size():
		_near(a.water[idx], b.water[idx], 0.0001, "resultado não depende do tamanho do frame (célula %d)" % idx)

func _test_huge_delta_does_not_runaway() -> void:
	var sim := _line_sim([0.0, 0.0])
	sim.add_water(0, 0, 3.0)
	var ran: int = sim.advance(50.0)
	_check(ran <= 12, "um delta gigante não trava tentando recuperar tudo de uma vez (%d passos)" % ran)
