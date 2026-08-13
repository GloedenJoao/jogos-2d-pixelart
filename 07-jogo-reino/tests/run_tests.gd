extends SceneTree

# Testes headless do Reino em Construção.
#
# Fase 0 — o autômato de água (water_sim.gd): a regressão mais perigosa não é
# uma exceção, é a CONSERVAÇÃO. Um autômato de calor pode inventar ou perder
# energia sem que ninguém note a olho nu; água que se multiplica ou some
# silenciosamente destrói a promessa central do jogo ("engenharia de terreno
# de verdade") sem derrubar nenhum teste ingênuo.
#
# Fase 1 — mapa, depósitos, névoa e a primeira cena de verdade: mesmo espírito
# do bot do platformer/incêndio ("regressão dos dois lados") adaptado a um
# gerador procedural — aqui o equivalente a "o bot vence todas as fases" é "a
# cobertura de cada tipo de depósito cai numa faixa plausível pra QUALQUER
# semente", não só pra uma.

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
	_test_conservation_holds_with_a_peak_surrounded_on_four_sides()

	_test_map_is_deterministic()
	_test_map_coverage_is_reasonable()
	_test_map_extract_and_deplete()
	_test_map_forest_regenerates_only_when_left_standing()
	_test_map_out_of_bounds_is_safe()
	_test_map_height_feeds_water_sim()

	_test_fog_starts_fully_unseen()
	_test_fog_reveal_is_circular()
	_test_fog_explored_persists_after_source_moves()
	_test_fog_out_of_bounds_is_safe()

	_test_pathfinder_open_grid()
	_test_pathfinder_detours_around_solid()
	_test_pathfinder_nearest_free()
	_test_pathfinder_trail_forms_and_decays()

	_test_workers_spawn_and_arrive_close_target_immediately()
	_test_workers_walk_and_arrive_exactly_at_target()
	_test_workers_move_independently()

	_test_buildings_place_and_assign()
	_test_buildings_only_produce_when_worker_is_working()
	_test_buildings_buffer_caps_and_throttles_extraction()
	_test_buildings_production_stops_when_deposit_empties()
	_test_buildings_nearest_deposit_cell()

	_test_buildings_collect_and_deliver()
	_test_buildings_warehouse_id()

	_test_buildings_processor_only_produces_when_worker_is_working()
	_test_buildings_processor_conversion_is_1_to_1()
	_test_buildings_processor_throttled_by_available_input()

	_test_buildings_mine_extracts_ore_like_the_other_extractors()
	_test_buildings_forge_converts_ore_to_lingote_1_to_1()

	_test_buildings_powered_without_worker_still_produces()
	_test_buildings_staffed_without_any_generator_still_produces()
	_test_buildings_neither_staffed_nor_powered_does_not_produce()
	_test_buildings_generator_out_of_range_does_not_power()
	_test_buildings_generator_only_burns_fuel_when_something_needs_it()
	_test_buildings_generator_runs_out_of_fuel_stops_powering()

	_test_buildings_waterwheel_powers_without_burning_any_stock()
	_test_buildings_windmill_powers_without_burning_any_stock()

	_test_buildings_housing_capacity()
	_test_population_starts_at_zero()
	_test_population_grows_toward_capacity_and_caps()
	_test_population_does_not_grow_without_housing()
	_test_population_employ_respects_availability()
	_test_population_available_grows_as_count_grows()

	_test_progression_starts_at_level_one()
	_test_progression_levels_up_and_carries_remainder()
	_test_progression_handles_multiple_levels_in_one_jump()
	_test_progression_ignores_zero_and_negative_xp()
	_test_progression_caps_at_max_defined_level()

	_test_carrier_picks_the_fullest_buffer()
	_test_carrier_full_round_trip_delivers_to_warehouse()
	_test_carrier_ignores_buffers_below_min_pickup()
	_test_carrier_does_nothing_without_a_warehouse()

	await _test_scene_boots()
	await _test_scene_camera_limits_to_map_size()
	await _test_scene_click_reveals_fog()
	await _test_scene_pan_moves_camera_within_limits()
	await _test_scene_buildings_unlock_progressively()
	await _test_scene_worker_arrives_and_produces()
	await _test_scene_population_grows_up_to_three_houses()
	await _test_scene_progression_grows_reveal_radius()
	await _test_scene_carrier_delivers_to_warehouse()
	await _test_scene_processing_chain_produces_tabua_and_bloco()
	await _test_scene_ore_chain_produces_lingote()
	await _test_scene_waterwheel_and_windmill_placement()

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

# Regressão do bug pego pela integração com o MapGen (ver o comentário em
# `_tick` de water_sim.gd): uma célula alta cercada por vizinhos baixos dos
# quatro lados tenta mandar água pras quatro arestas ao mesmo tempo. Numa
# grade 1D isso nunca acontece (no máximo 2 vizinhos), por isso só apareceu
# num mapa 2D de verdade.
func _test_conservation_holds_with_a_peak_surrounded_on_four_sides() -> void:
	var sim := WaterSim.new()
	# cruz: centro alto, os quatro vizinhos ortogonais baixos, cantos altos
	# (só pra não vazar prum shape em L). 3x3.
	var h := PackedFloat32Array([
		3.0, 0.0, 3.0,
		0.0, 3.0, 0.0,
		3.0, 0.0, 3.0,
	])
	sim.setup(3, 3, h)
	sim.add_water(1, 1, 1.0)   # pouca água: força o cenário "quero mandar mais do que tenho"
	for _i in 200:
		sim.advance(TICK)
	_near(sim.total_water(), 1.0, 0.001, "pico cercado por 4 vizinhos mais baixos não cria água")
	_check(sim.water_at(1, 1) >= 0.0, "o próprio pico nunca fica com água negativa")

func _test_huge_delta_does_not_runaway() -> void:
	var sim := _line_sim([0.0, 0.0])
	sim.add_water(0, 0, 3.0)
	var ran: int = sim.advance(50.0)
	_check(ran <= 12, "um delta gigante não trava tentando recuperar tudo de uma vez (%d passos)" % ran)

# ---- Fase 1: mapa (map_gen.gd) ----

const MAP_COLS := 60
const MAP_ROWS := 40

func _map(seed_value: int) -> MapGen:
	var m := MapGen.new()
	m.generate(MAP_COLS, MAP_ROWS, seed_value)
	return m

func _test_map_is_deterministic() -> void:
	var a := _map(777)
	var b := _map(777)
	_check(a.kind == b.kind, "mesma semente dá o mesmo mapa de terreno")
	var same_height := true
	for idx in a.height.size():
		if absf(a.height[idx] - b.height[idx]) > 0.0001:
			same_height = false
			break
	_check(same_height, "mesma semente dá o mesmo relevo")

	var c := _map(778)
	_check(a.kind != c.kind, "sementes diferentes dão mapas diferentes (contraprova)")

# Faixas largas de propósito (mesmo espírito de _test_front_speed em
# fire_sim): o que a suíte protege é "nenhum tipo domina o mapa nem
# desaparece", não um número exato — os valores centrais vieram de medir 12
# sementes com um script de calibração (removido depois de usado, os números
# ficaram só aqui e no comentário de map_gen.gd).
func _test_map_coverage_is_reasonable() -> void:
	for seed_value in [1000, 5000, 9000, 12000]:
		var cov := _map(seed_value).coverage()
		var forest: float = cov[MapGen.Kind.FOREST]
		var stone: float = cov[MapGen.Kind.STONE]
		var hills: float = cov[MapGen.Kind.HILLS]
		var grass: float = cov[MapGen.Kind.GRASS]
		_check(forest >= 0.10 and forest <= 0.30, "floresta numa faixa plausível (%.2f, semente %d)" % [forest, seed_value])
		_check(stone >= 0.02 and stone <= 0.10, "pedra numa faixa plausível (%.2f, semente %d)" % [stone, seed_value])
		_check(hills >= 0.05 and hills <= 0.25, "colina numa faixa plausível (%.2f, semente %d)" % [hills, seed_value])
		_check(grass >= 0.40 and grass <= 0.80, "grama numa faixa plausível (%.2f, semente %d)" % [grass, seed_value])
		_near(forest + stone + hills + grass, 1.0, 0.001, "cobertura soma o mapa inteiro (semente %d)" % seed_value)

func _test_map_extract_and_deplete() -> void:
	var m := _map(42)
	var pos := Vector2i(-1, -1)
	for y in MAP_ROWS:
		for x in MAP_COLS:
			if m.kind_at(x, y) == MapGen.Kind.FOREST:
				pos = Vector2i(x, y)
				break
		if pos.x >= 0:
			break
	_check(pos.x >= 0, "o mapa de teste tem pelo menos uma floresta")
	if pos.x < 0:
		return

	var full: float = m.deposit_at(pos.x, pos.y)
	var taken := m.extract(pos.x, pos.y, 5.0)
	_near(taken, 5.0, 0.0001, "extrair menos que o total devolve exatamente o pedido")
	_near(m.deposit_at(pos.x, pos.y), full - 5.0, 0.0001, "extrair decrementa o depósito")
	_check(m.kind_at(pos.x, pos.y) == MapGen.Kind.FOREST, "depósito parcial continua sendo floresta")

	var over := m.extract(pos.x, pos.y, 9999.0)
	_near(over, full - 5.0, 0.0001, "extrair mais do que resta devolve só o que tinha")
	_check(m.deposit_at(pos.x, pos.y) == 0.0, "depósito esgotado fica em zero")
	_check(m.kind_at(pos.x, pos.y) == MapGen.Kind.GRASS, "depósito esgotado reverte pra grama")
	_check(m.extract(pos.x, pos.y, 1.0) == 0.0, "não dá pra extrair de grama")

func _test_map_forest_regenerates_only_when_left_standing() -> void:
	var m := _map(42)
	var pos := Vector2i(-1, -1)
	for y in MAP_ROWS:
		for x in MAP_COLS:
			if m.kind_at(x, y) == MapGen.Kind.FOREST:
				pos = Vector2i(x, y)
				break
		if pos.x >= 0:
			break
	m.extract(pos.x, pos.y, 10.0)
	var after_cut: float = m.deposit_at(pos.x, pos.y)
	for _i in 200:
		m.advance(1.0)
	_check(m.deposit_at(pos.x, pos.y) > after_cut, "floresta deixada em pé se regenera com o tempo")
	_check(m.deposit_at(pos.x, pos.y) <= MapGen.FOREST_DEPOSIT_MAX, "regeneração não passa do teto")

	var stone_pos := Vector2i(-1, -1)
	for y in MAP_ROWS:
		for x in MAP_COLS:
			if m.kind_at(x, y) == MapGen.Kind.STONE:
				stone_pos = Vector2i(x, y)
				break
		if stone_pos.x >= 0:
			break
	if stone_pos.x >= 0:
		var stone_before: float = m.deposit_at(stone_pos.x, stone_pos.y)
		m.extract(stone_pos.x, stone_pos.y, 5.0)
		var stone_after_cut: float = m.deposit_at(stone_pos.x, stone_pos.y)
		for _i in 200:
			m.advance(1.0)
		_near(m.deposit_at(stone_pos.x, stone_pos.y), stone_after_cut, 0.0001, "pedra não se regenera (%.1f -> %.1f)" % [stone_before, stone_after_cut])

func _test_map_out_of_bounds_is_safe() -> void:
	var m := _map(1)
	_check(m.extract(-5, -5, 10.0) == 0.0, "extrair fora do mapa não crasha e não dá nada")
	_check(m.kind_at(9999, 9999) == MapGen.Kind.GRASS, "consultar fora do mapa devolve grama, não erro")
	_check(m.height_at(-1, 0) == 0.0, "altura fora do mapa devolve 0, não erro")

# A integração que a Fase 1 promete: a altura que o MapGen gera tem que
# servir de entrada pro WaterSim (Fase 0) sem nenhuma adaptação.
func _test_map_height_feeds_water_sim() -> void:
	var m := _map(55)
	var sim := WaterSim.new()
	sim.setup(m.cols, m.rows, m.height)
	_check(sim.cols == MAP_COLS and sim.rows == MAP_ROWS, "WaterSim aceita as dimensões do MapGen")
	sim.add_water(m.cols / 2, m.rows / 2, 20.0)
	for _i in 50:
		sim.advance(WaterSim.TICK)
	_near(sim.total_water(), 20.0, 0.01, "água se comporta normalmente sobre relevo gerado")

# ---- Fase 1: névoa (fog.gd) ----

func _test_fog_starts_fully_unseen() -> void:
	var f := Fog.new()
	f.setup(20, 15)
	_check(f.explored_count() == 0, "névoa começa sem nada explorado")
	_check(not f.is_visible(10, 7), "nada visível antes de qualquer revelação")

func _test_fog_reveal_is_circular() -> void:
	var f := Fog.new()
	f.setup(30, 30)
	f.reveal(15, 15, 5.0)
	_check(f.is_visible(15, 15), "centro da revelação está visível")
	_check(f.is_visible(15, 19), "ponto a 4 células (dentro do raio 5) está visível")
	_check(not f.is_visible(21, 21), "canto do quadrado 5x5 (distância ~8.5) fica de fora — é círculo, não quadrado")
	_check(not f.is_visible(15, 25), "muito além do raio continua escuro")

func _test_fog_explored_persists_after_source_moves() -> void:
	var f := Fog.new()
	f.setup(30, 30)
	f.update_visibility([Vector3(5, 5, 4.0)])
	_check(f.is_visible(5, 5) and f.is_explored(5, 5), "primeira posição fica visível e explorada")

	f.update_visibility([Vector3(20, 20, 4.0)])
	_check(not f.is_visible(5, 5), "fonte que se moveu deixa de iluminar onde estava")
	_check(f.is_explored(5, 5), "mas o que já foi visto continua na memória (explorado)")
	_check(f.is_visible(20, 20), "a nova posição está visível")

func _test_fog_out_of_bounds_is_safe() -> void:
	var f := Fog.new()
	f.setup(10, 10)
	f.reveal(-3, -3, 5.0)
	_check(f.is_visible(0, 0), "revelar perto da borda com centro fora do mapa ainda alcança células válidas")
	_check(not f.is_visible(50, 50), "consultar fora do mapa devolve falso, não erro")

# ---- Fase 2: pathfinder (portado de 05_V2-jogo-colonia/scripts/pathfinder.gd) ----

func _pf(cols: int = 20, rows: int = 20, cell: float = 32.0) -> Pathfinder:
	var pf := Pathfinder.new()
	pf.setup(cols, rows, cell)
	pf.rebuild([])
	return pf

func _test_pathfinder_open_grid() -> void:
	var pf := _pf()
	var start := Vector2(16.0, 16.0)
	var goal := Vector2(300.0, 300.0)
	var path := pf.find_path(start, goal)
	_check(path.size() > 0, "grade aberta sempre devolve algum caminho")
	_near(path[path.size() - 1].x, goal.x, 0.01, "o caminho termina exatamente no destino (x)")
	_near(path[path.size() - 1].y, goal.y, 0.01, "o caminho termina exatamente no destino (y)")
	_check(pf.has_route(start, goal), "has_route concorda que existe rota")

func _test_pathfinder_detours_around_solid() -> void:
	var pf := _pf(10, 10, 32.0)
	# parede vertical inteira em x=5, exceto um buraco em y=8 — só rota é dar a volta.
	var wall: Array = []
	for y in 8:
		wall.append(Vector2i(5, y))
	pf.rebuild(wall)

	var start := Vector2(1 * 32.0 + 16.0, 1 * 32.0 + 16.0)
	var goal := Vector2(8 * 32.0 + 16.0, 1 * 32.0 + 16.0)
	_check(pf.has_route(start, goal), "existe rota contornando o buraco na parede")
	var path := pf.find_path(start, goal)
	var straight_line_blocked := not pf.line_is_clear(start, goal)
	_check(straight_line_blocked, "a reta direta atravessa a parede (checagem do próprio teste)")
	_check(path.size() >= 2, "o caminho contorna em vez de atravessar (mais de um ponto)")

	var fully_walled := _pf(10, 10, 32.0)
	var full_wall: Array = []
	for y in 10:
		full_wall.append(Vector2i(5, y))
	fully_walled.rebuild(full_wall)
	_check(not fully_walled.has_route(start, goal), "parede sem buraco nenhum: não existe rota")

func _test_pathfinder_nearest_free() -> void:
	var pf := _pf(10, 10, 32.0)
	pf.rebuild([Vector2i(5, 5)])
	_check(pf.nearest_free(Vector2i(5, 5)) != Vector2i(5, 5), "célula sólida não é devolvida como livre")
	_check(not pf.is_solid(pf.nearest_free(Vector2i(5, 5))), "a célula livre mais próxima realmente não é sólida")
	_check(pf.nearest_free(Vector2i(1, 1)) == Vector2i(1, 1), "célula já livre é devolvida sem mudança")

func _test_pathfinder_trail_forms_and_decays() -> void:
	var pf := _pf(10, 10, 32.0)
	var cell := Vector2i(3, 3)
	var pos := pf.center_of(cell)
	for _i in int(Pathfinder.TRAIL_THRESHOLD) + 5:
		pf.register_step(pos)
	pf.decay(Pathfinder.REBUILD_INTERVAL + 0.01)
	_check(pf.is_trail(cell), "célula pisada acima do limiar vira trilha depois do decay rodar")

	# sem mais nenhum passo, um decay bem mais longo que o necessário apaga o desgaste
	pf.decay(1000.0)
	_check(not pf.is_trail(cell), "trilha sem uso volta a ser mato depois de tempo suficiente")

# ---- Fase 2: trabalhadores (workers.gd / worker.gd) ----

func _test_workers_spawn_and_arrive_close_target_immediately() -> void:
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2(100.0, 100.0))
	_check(w.state == Worker.State.IDLE, "trabalhador nasce ocioso")
	var pf := _pf()
	mgr.send_to(w, Vector2(101.0, 100.0), pf)   # bem perto: dentro do raio de "já chegou"
	_check(w.state == Worker.State.IDLE, "alvo pertinho e sem prédio vira IDLE na hora, sem gerar caminho")
	_check(not w.has_path(), "não gerou caminho pra uma distância irrisória")

func _test_workers_walk_and_arrive_exactly_at_target() -> void:
	var mgr := Workers.new()
	var pf := _pf()
	var w := mgr.spawn(Vector2(16.0, 16.0))
	w.job_building = 0   # simula alocação — chegando, vira WORKING, não IDLE
	var target := Vector2(500.0, 500.0)
	mgr.send_to(w, target, pf)
	_check(w.state == Worker.State.WALKING, "alvo longe: trabalhador começa a andar")

	var steps := 0
	while w.state == Worker.State.WALKING and steps < 2000:
		mgr.advance(1.0 / 30.0, pf)
		steps += 1
	_check(steps < 2000, "chega dentro de um teto razoável de passos (%d)" % steps)
	_check(w.state == Worker.State.WORKING, "com job_building marcado, chegar vira WORKING")
	_near(w.position.x, target.x, 0.5, "posição final bate exatamente com o alvo (x)")
	_near(w.position.y, target.y, 0.5, "posição final bate exatamente com o alvo (y)")

func _test_workers_move_independently() -> void:
	var mgr := Workers.new()
	var pf := _pf()
	var a := mgr.spawn(Vector2(16.0, 16.0))
	var b := mgr.spawn(Vector2(16.0, 16.0))
	mgr.send_to(a, Vector2(600.0, 16.0), pf)
	mgr.send_to(b, Vector2(16.0, 600.0), pf)
	for _i in 30:
		mgr.advance(1.0 / 30.0, pf)
	_check(a.position != b.position, "trabalhadores em rotas diferentes não colam um no outro")
	_check(a.position.y < 32.0, "trabalhador A anda na horizontal, não se desvia pra vertical")
	_check(b.position.x < 32.0, "trabalhador B anda na vertical, não se desvia pra horizontal")

# ---- Fase 2: prédios (buildings.gd) ----

func _test_buildings_place_and_assign() -> void:
	var b := Buildings.new()
	var id_a := b.place(Buildings.Kind.LUMBERJACK, Vector2i(3, 3))
	var id_b := b.place(Buildings.Kind.QUARRY, Vector2i(7, 7))
	_check(id_a == 0 and id_b == 1, "ids sequenciais por ordem de construção")
	_check(b.list[id_a].kind == Buildings.Kind.LUMBERJACK and b.list[id_a].cell == Vector2i(3, 3), "primeiro prédio guardado certo")

	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(id_a, w)
	_check(b.list[id_a].worker_id == w.id, "assign liga o prédio ao trabalhador")
	_check(w.job_building == id_a, "assign liga o trabalhador ao prédio (mão dupla)")

func _test_buildings_only_produce_when_worker_is_working() -> void:
	var m := MapGen.new()
	m.generate(20, 20, 9001)
	var forest_cell := Buildings.nearest_deposit_cell(m, MapGen.Kind.FOREST, Vector2i(10, 10), 15)
	_check(forest_cell.x >= 0, "o mapa de teste tem floresta a uma distância alcançável")
	if forest_cell.x < 0:
		return

	var b := Buildings.new()
	var building_id := b.place(Buildings.Kind.LUMBERJACK, forest_cell)
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)

	b.advance(1.0, m, mgr)
	_near(b.list[building_id].buffer, 0.0, 0.0001, "sem trabalhador alocado, prédio não acumula nada no pátio")

	b.assign(building_id, w)
	w.state = Worker.State.WALKING
	b.advance(1.0, m, mgr)
	_near(b.list[building_id].buffer, 0.0, 0.0001, "alocado mas ainda a caminho (WALKING) não produz")

	w.state = Worker.State.WORKING
	b.advance(1.0, m, mgr)
	_check(b.list[building_id].buffer > 0.0, "trabalhador WORKING no prédio acumula produção no pátio de verdade")
	_near(b.stock["madeira"], 0.0, 0.0001, "produção no pátio ainda NÃO é estoque jogável — precisa de um carregador (Fase 3)")

func _test_buildings_buffer_caps_and_throttles_extraction() -> void:
	var m := MapGen.new()
	m.generate(20, 20, 9001)
	var forest_cell := Buildings.nearest_deposit_cell(m, MapGen.Kind.FOREST, Vector2i(10, 10), 15)
	if forest_cell.x < 0:
		return
	var b := Buildings.new()
	var building_id := b.place(Buildings.Kind.LUMBERJACK, forest_cell)
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(building_id, w)
	w.state = Worker.State.WORKING

	for _i in 60:
		b.advance(1.0, m, mgr)
	_near(b.list[building_id].buffer, Buildings.EXTRACTOR_BUFFER_CAP, 0.0001, "pátio para exatamente no teto, não passa dele")

	var deposit_before: float = m.deposit_at(forest_cell.x, forest_cell.y)
	b.advance(5.0, m, mgr)
	_near(m.deposit_at(forest_cell.x, forest_cell.y), deposit_before, 0.0001, "pátio cheio: trabalhador fica WORKING mas para de extrair (não desperdiça o depósito)")

	# Esvaziar o pátio (o que um Carrier faria) libera espaço e a extração
	# volta sozinha, sem precisar reatribuir o trabalhador.
	b.collect(building_id, Buildings.EXTRACTOR_BUFFER_CAP)
	b.advance(1.0, m, mgr)
	_check(b.list[building_id].buffer > 0.0, "pátio esvaziado: extração recomeça no próximo avanço")

func _test_buildings_production_stops_when_deposit_empties() -> void:
	var m := MapGen.new()
	m.generate(20, 20, 9001)
	var forest_cell := Buildings.nearest_deposit_cell(m, MapGen.Kind.FOREST, Vector2i(10, 10), 15)
	if forest_cell.x < 0:
		return
	var b := Buildings.new()
	var building_id := b.place(Buildings.Kind.LUMBERJACK, forest_cell)
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(building_id, w)
	w.state = Worker.State.WORKING

	# Esvazia o pátio a cada passo (papel do Carrier neste teste), senão o
	# teto do pátio para a extração antes do depósito se esgotar de verdade —
	# não é o mecanismo que este teste quer proteger.
	for _i in 200:
		b.advance(1.0, m, mgr)
		b.collect(building_id, 999.0)
	_check(m.deposit_at(forest_cell.x, forest_cell.y) == 0.0, "depósito esgota depois de tempo suficiente")
	_check(m.kind_at(forest_cell.x, forest_cell.y) == MapGen.Kind.GRASS, "célula esgotada vira grama (mesma regra da Fase 1)")

	var buffer_before: float = b.list[building_id].buffer
	b.advance(5.0, m, mgr)
	_near(b.list[building_id].buffer, buffer_before, 0.0001, "depósito vazio: prédio para de produzir sozinho, sem erro")

func _test_buildings_nearest_deposit_cell() -> void:
	var m := MapGen.new()
	m.generate(20, 20, 9001)
	var forest_cell := Buildings.nearest_deposit_cell(m, MapGen.Kind.FOREST, Vector2i(10, 10), 15)
	_check(forest_cell.x >= 0, "acha floresta dentro de um raio generoso")
	if forest_cell.x >= 0:
		_check(m.kind_at(forest_cell.x, forest_cell.y) == MapGen.Kind.FOREST, "a célula encontrada é mesmo do tipo pedido")
		_check(Buildings.nearest_deposit_cell(m, MapGen.Kind.FOREST, forest_cell, 15) == forest_cell, "buscar a partir da própria célula devolve ela mesma")

	# raio 0 só acha se a própria célula de partida já for do tipo pedido —
	# escolhe deliberadamente uma célula que NÃO é floresta pra provar isso.
	var not_forest := Vector2i(0, 0)
	while m.kind_at(not_forest.x, not_forest.y) == MapGen.Kind.FOREST:
		not_forest.x += 1
	_check(Buildings.nearest_deposit_cell(m, MapGen.Kind.FOREST, not_forest, 0) == Vector2i(-1, -1), "raio 0 numa célula errada não acha nada")

func _test_buildings_collect_and_deliver() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.LUMBERJACK, Vector2i(5, 5))
	b.list[id].buffer = 8.0

	var taken := b.collect(id, 3.0)
	_near(taken, 3.0, 0.0001, "collect devolve exatamente o pedido quando o pátio tem de sobra")
	_near(b.list[id].buffer, 5.0, 0.0001, "collect decrementa o pátio")

	var over := b.collect(id, 999.0)
	_near(over, 5.0, 0.0001, "collect nunca devolve mais do que existia no pátio")
	_near(b.list[id].buffer, 0.0, 0.0001, "pátio esvaziado fica em zero, não negativo")

	_near(b.stock.get("madeira", 0.0), 0.0, 0.0001, "collect por si só não entrega nada — só tira do pátio")
	b.deliver("madeira", 3.0)
	b.deliver("madeira", 5.0)
	_near(b.stock["madeira"], 8.0, 0.0001, "deliver soma no estoque jogável, entrega após entrega")

	b.deliver("pedra", 0.0)
	_check(not b.stock.has("pedra") or b.stock["pedra"] == 0.0, "entregar quantidade zero não faz nada (nem cria a chave à toa)")

func _test_buildings_warehouse_id() -> void:
	var b := Buildings.new()
	_check(b.warehouse_id() == -1, "sem nenhum prédio, não existe armazém")
	b.place(Buildings.Kind.LUMBERJACK, Vector2i(1, 1))
	_check(b.warehouse_id() == -1, "extrator sozinho não conta como armazém")
	var wid := b.place(Buildings.Kind.WAREHOUSE, Vector2i(9, 9))
	_check(b.warehouse_id() == wid, "acha o armazém certo mesmo com outros prédios na lista")

# ---- Fase 4: processamento (Serraria, Oficina de Pedra) ----

func _test_buildings_processor_only_produces_when_worker_is_working() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.SAWMILL, Vector2i(4, 4))
	b.stock["madeira"] = 10.0
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)

	b.advance(1.0, MapGen.new(), mgr)
	_near(b.stock["tábua"], 0.0, 0.0001, "sem trabalhador alocado, Serraria não processa nada")

	b.assign(id, w)
	w.state = Worker.State.WALKING
	b.advance(1.0, MapGen.new(), mgr)
	_near(b.stock["tábua"], 0.0, 0.0001, "alocado mas ainda a caminho não processa")

	w.state = Worker.State.WORKING
	b.advance(1.0, MapGen.new(), mgr)
	_check(b.stock["tábua"] > 0.0, "trabalhador WORKING na Serraria processa de verdade")

func _test_buildings_processor_conversion_is_1_to_1() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.STONE_WORKSHOP, Vector2i(4, 4))
	b.stock["pedra"] = 20.0
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(id, w)
	w.state = Worker.State.WORKING

	b.advance(2.0, MapGen.new(), mgr)
	var consumed: float = 20.0 - b.stock["pedra"]
	_near(b.stock["bloco"], consumed, 0.0001, "cada unidade de pedra consumida vira exatamente uma de bloco (1:1)")
	_check(consumed > 0.0, "consumiu pedra de verdade (o teste não é vácuo)")

func _test_buildings_processor_throttled_by_available_input() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.SAWMILL, Vector2i(4, 4))
	b.stock["madeira"] = 0.3   # bem menos do que a receita pediria num segundo
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(id, w)
	w.state = Worker.State.WORKING

	b.advance(1.0, MapGen.new(), mgr)
	_near(b.stock["madeira"], 0.0, 0.0001, "consome só o que existe, não fica negativo")
	_near(b.stock["tábua"], 0.3, 0.0001, "produção fica limitada pelo insumo disponível, não pela taxa da receita")

	var tabua_before: float = b.stock["tábua"]
	b.advance(5.0, MapGen.new(), mgr)
	_near(b.stock["tábua"], tabua_before, 0.0001, "sem mais insumo, Serraria para sozinha (trabalhador continua WORKING)")

# ---- Mina + Forja (terceira cadeia: minério → lingote) ----
# Reaproveitam 100% do código genérico de extração/processamento (advance,
# buffer, receitas) — estes testes só provam que a entrada nos dicts
# (RESOURCE_OF/DEPOSIT_KIND_OF/PRODUCTION_PER_SECOND/PROCESS_RECIPES) está
# correta, não repetem a lógica genérica já coberta acima.

func _test_buildings_mine_extracts_ore_like_the_other_extractors() -> void:
	var m := MapGen.new()
	m.generate(20, 20, 9001)
	var hills_cell := Buildings.nearest_deposit_cell(m, MapGen.Kind.HILLS, Vector2i(10, 10), 15)
	_check(hills_cell.x >= 0, "o mapa de teste tem colina (depósito de minério) a uma distância alcançável")
	if hills_cell.x < 0:
		return

	var b := Buildings.new()
	var id := b.place(Buildings.Kind.MINE, hills_cell)
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)

	b.advance(1.0, m, mgr)
	_near(b.list[id].buffer, 0.0, 0.0001, "sem trabalhador alocado, Mina não acumula nada no pátio")

	b.assign(id, w)
	w.state = Worker.State.WORKING
	b.advance(1.0, m, mgr)
	_check(b.list[id].buffer > 0.0, "trabalhador WORKING na Mina acumula minério no pátio de verdade")

	var taken := b.collect(id, 999.0)
	b.deliver("minério", taken)
	_check(b.stock["minério"] > 0.0, "minério coletado do pátio vira estoque jogável (mesmo caminho collect/deliver dos outros extratores)")

func _test_buildings_forge_converts_ore_to_lingote_1_to_1() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.FORGE, Vector2i(4, 4))
	b.stock["minério"] = 20.0
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(id, w)
	w.state = Worker.State.WORKING

	b.advance(2.0, MapGen.new(), mgr)
	var consumed: float = 20.0 - b.stock["minério"]
	_near(b.stock["lingote"], consumed, 0.0001, "cada unidade de minério consumida vira exatamente uma de lingote (1:1)")
	_check(consumed > 0.0, "consumiu minério de verdade (o teste não é vácuo)")

# ---- Fase 5: energia (Gerador a Lenha, regra "energia OU trabalhador") ----

func _test_buildings_powered_without_worker_still_produces() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.GENERATOR, Vector2i(4, 4))
	var id := b.place(Buildings.Kind.STONE_WORKSHOP, Vector2i(5, 4))   # dentro do raio, sem trabalhador
	b.stock["pedra"] = 10.0
	b.stock["madeira"] = 10.0   # combustível do gerador
	var mgr := Workers.new()

	_check(b.list[id].worker_id == -1, "a Oficina de Pedra deste teste não tem NENHUM trabalhador")
	b.advance(1.0, MapGen.new(), mgr)
	_check(b.stock["bloco"] > 0.0, "mesmo sem trabalhador, produz só por estar no raio de um gerador com combustível")
	_check(b.list[id].powered, "Building.powered fica true no frame em que foi alimentado (pra cena desenhar o indicador)")

func _test_buildings_staffed_without_any_generator_still_produces() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.SAWMILL, Vector2i(4, 4))   # nenhum gerador no mapa
	b.stock["madeira"] = 10.0
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(id, w)
	w.state = Worker.State.WORKING

	b.advance(1.0, MapGen.new(), mgr)
	_check(b.stock["tábua"] > 0.0, "trabalhador sozinho continua bastando — energia é alternativa, não substituição")
	_check(not b.list[id].powered, "não tem gerador nenhum, então powered nunca vira true")

func _test_buildings_neither_staffed_nor_powered_does_not_produce() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.SAWMILL, Vector2i(4, 4))
	b.stock["madeira"] = 10.0
	var mgr := Workers.new()

	b.advance(1.0, MapGen.new(), mgr)
	_near(b.stock["tábua"], 0.0, 0.0001, "sem trabalhador WORKING e sem gerador no raio, não produz nada")
	_check(not b.list[id].powered, "sem gerador nenhum, powered fica false")

func _test_buildings_generator_out_of_range_does_not_power() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.GENERATOR, Vector2i(0, 0))
	var id := b.place(Buildings.Kind.STONE_WORKSHOP, Vector2i(0, int(Buildings.GENERATOR_RADIUS) + 5))
	b.stock["pedra"] = 10.0
	b.stock["madeira"] = 10.0
	var mgr := Workers.new()

	b.advance(1.0, MapGen.new(), mgr)
	_near(b.stock["bloco"], 0.0, 0.0001, "prédio fora do raio do gerador não recebe energia")
	_check(not b.list[id].powered, "fora do raio: powered continua false")
	_near(b.stock["madeira"], 10.0, 0.0001, "gerador não gasta combustível por um prédio que nem alcança")

func _test_buildings_generator_only_burns_fuel_when_something_needs_it() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.GENERATOR, Vector2i(4, 4))
	var id := b.place(Buildings.Kind.SAWMILL, Vector2i(5, 4))   # dentro do raio, mas JÁ staffado
	b.stock["madeira"] = 10.0
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	b.assign(id, w)
	w.state = Worker.State.WORKING

	var madeira_before: float = b.stock["madeira"]
	b.advance(1.0, MapGen.new(), mgr)
	_check(b.stock["madeira"] < madeira_before, "a Serraria consumiu madeira normalmente (produção por trabalhador)")
	# a diferença entre o que a Serraria consumiu (rate da receita) e o que
	# sobrou tem que bater — se o gerador também tivesse queimado combustível
	# à toa, sobraria menos madeira do que a receita sozinha explica.
	var recipe: Dictionary = Buildings.PROCESS_RECIPES[Buildings.Kind.SAWMILL]
	_near(b.stock["madeira"], madeira_before - recipe["rate"], 0.001, "gerador não queima combustível: ninguém no raio precisava dele (Serraria já staffada)")

func _test_buildings_generator_runs_out_of_fuel_stops_powering() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.GENERATOR, Vector2i(4, 4))
	var id := b.place(Buildings.Kind.STONE_WORKSHOP, Vector2i(5, 4))
	b.stock["pedra"] = 100.0
	b.stock["madeira"] = 0.5   # pouco combustível, esgota rápido
	var mgr := Workers.new()

	for _i in 20:
		b.advance(0.1, MapGen.new(), mgr)
	_near(b.stock["madeira"], 0.0, 0.001, "combustível esgota")
	var bloco_when_out_of_fuel: float = b.stock["bloco"]
	_check(bloco_when_out_of_fuel > 0.0, "produziu bloco enquanto teve combustível (o teste não é vácuo)")

	b.advance(1.0, MapGen.new(), mgr)
	_near(b.stock["bloco"], bloco_when_out_of_fuel, 0.0001, "sem combustível, o gerador para de alimentar — Oficina de Pedra para junto")
	_check(not b.list[id].powered, "powered vira false assim que o gerador fica sem combustível")

# ---- Roda D'Água + Moinho de Vento (segunda e terceira fonte de energia, grátis pra operar) ----

func _test_buildings_waterwheel_powers_without_burning_any_stock() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.WATERWHEEL, Vector2i(4, 4))
	var id := b.place(Buildings.Kind.STONE_WORKSHOP, Vector2i(5, 4))
	b.stock["pedra"] = 10.0
	var mgr := Workers.new()

	var stock_before := b.stock.duplicate()
	b.advance(1.0, MapGen.new(), mgr)
	_check(b.stock["bloco"] > 0.0, "Roda D'Água sustenta produção sem trabalhador, igual ao Gerador")
	_check(b.list[id].powered, "powered fica true — mesmo sinal que a cena usa pro indicador, não importa qual fonte")
	for resource in stock_before:
		if resource == "pedra" or resource == "bloco":
			continue
		_near(b.stock.get(resource, 0.0), stock_before[resource], 0.0001, "Roda D'Água não consome NENHUM estoque — é grátis pra operar, diferente do Gerador")

func _test_buildings_windmill_powers_without_burning_any_stock() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.WINDMILL, Vector2i(4, 4))
	var id := b.place(Buildings.Kind.SAWMILL, Vector2i(5, 4))
	b.stock["madeira"] = 10.0
	var mgr := Workers.new()

	var madeira_before: float = b.stock["madeira"]
	b.advance(1.0, MapGen.new(), mgr)
	_check(b.stock["tábua"] > 0.0, "Moinho de Vento sustenta produção sem trabalhador, igual ao Gerador")
	_check(b.list[id].powered, "powered fica true")
	# madeira caiu só pelo consumo da RECEITA da Serraria (input da produção),
	# nunca por combustível — Moinho não tem `FUELED_POWER_KINDS`.
	var recipe: Dictionary = Buildings.PROCESS_RECIPES[Buildings.Kind.SAWMILL]
	_near(b.stock["madeira"], madeira_before - recipe["rate"], 0.001, "Moinho de Vento não queima madeira nenhuma — só a receita da Serraria consumiu")

# ---- Fase 6: população (population.gd, Buildings.housing_capacity) ----

func _test_buildings_housing_capacity() -> void:
	var b := Buildings.new()
	_check(b.housing_capacity() == 0, "sem casa nenhuma, capacidade é zero")
	b.place(Buildings.Kind.HOUSE, Vector2i(1, 1))
	_check(b.housing_capacity() == Buildings.HOUSE_CAPACITY, "uma casa soma a capacidade dela")
	b.place(Buildings.Kind.HOUSE, Vector2i(2, 2))
	_check(b.housing_capacity() == Buildings.HOUSE_CAPACITY * 2, "duas casas somam o dobro")
	b.place(Buildings.Kind.LUMBERJACK, Vector2i(3, 3))
	_check(b.housing_capacity() == Buildings.HOUSE_CAPACITY * 2, "prédio que não é casa não soma nada")

func _test_population_starts_at_zero() -> void:
	var p := Population.new()
	_check(p.count == 0.0, "população nasce em zero")
	_check(p.available() == 0, "sem população, nada disponível pra empregar")

func _test_population_grows_toward_capacity_and_caps() -> void:
	var p := Population.new()
	# food_available bem grande: estes testes cobrem só o crescimento,
	# comida à vontade não deixa a fome interferir (ver testes dedicados
	# a comida/fome mais abaixo).
	p.advance(1.0, 6, 999999.0)
	_near(p.count, Population.GROWTH_PER_SECOND, 0.0001, "cresce à taxa esperada")

	# delta gigante não pode passar do teto — sem casa nova, população não
	# nasce do nada além da capacidade habitacional.
	p.advance(1000.0, 6, 999999.0)
	_near(p.count, 6.0, 0.0001, "cresce até o teto e para exatamente nele")

	p.advance(10.0, 6, 999999.0)
	_near(p.count, 6.0, 0.0001, "não ultrapassa o teto mesmo com mais tempo")

func _test_population_does_not_grow_without_housing() -> void:
	var p := Population.new()
	p.advance(10.0, 0, 999999.0)
	_near(p.count, 0.0, 0.0001, "capacidade zero (nenhuma casa) significa população nunca cresce")

func _test_population_employ_respects_availability() -> void:
	var p := Population.new()
	p.advance(10.0, 3, 999999.0)   # população cheia em 3

	_check(p.employ(), "primeiro emprego disponível é aceito")
	_check(p.employ(), "segundo também")
	_check(p.employ(), "terceiro também — exatamente a capacidade")
	_check(not p.employ(), "quarto emprego falha: não sobrou ninguém disponível")
	_check(p.employed() == 3, "employed() reflete quantos foram empregados de verdade")
	_check(p.available() == 0, "disponível zera depois de empregar todo mundo")

func _test_population_available_grows_as_count_grows() -> void:
	var p := Population.new()
	_check(p.available() == 0, "nada disponível em t=0")
	p.advance(1.0 / Population.GROWTH_PER_SECOND, 10, 999999.0)   # ~1.0 de população
	_check(p.available() >= 1, "depois de crescer o suficiente, sobra gente disponível pra empregar")

# ---- Necessidade de comida (Fazenda + Population) ----

func _test_population_advance_returns_food_consumed() -> void:
	var p := Population.new()
	p.advance(100.0, 10, 999999.0)   # população cheia em 10, comida à vontade
	var before: float = p.count
	var consumed := p.advance(1.0, 10, 999999.0)
	_near(consumed, before * Population.CONSUMPTION_PER_CAPITA, 0.0001, "consumo bate com população × consumo per capita")
	_check(consumed > 0.0, "consumiu de verdade (teste não é vácuo)")

func _test_population_well_fed_does_not_starve() -> void:
	var p := Population.new()
	for _i in 200:
		p.advance(1.0, 6, 999999.0)   # sempre mais comida do que precisa
	_near(p.count, 6.0, 0.01, "com comida sempre disponível, população fica na capacidade cheia, sem encolher")

func _test_population_starves_without_food() -> void:
	var p := Population.new()
	p.advance(100.0, 6, 999999.0)   # sobe até 6 primeiro, com comida à vontade
	_near(p.count, 6.0, 0.01, "população cheia antes de cortar a comida")

	for _i in 50:
		p.advance(1.0, 6, 0.0)   # zero comida disponível a partir daqui
	_check(p.count < 6.0, "sem comida nenhuma, a fome encolhe a população mesmo com capacidade sobrando")
	_check(p.count >= 0.0, "população nunca fica negativa")

func _test_population_partial_food_finds_equilibrium() -> void:
	var p := Population.new()
	p.advance(100.0, 6, 999999.0)
	# Comida suficiente pra sustentar só metade da capacidade — o
	# crescimento continua tentando subir até 6, mas a fome puxa de volta;
	# o resultado de longo prazo se estabiliza numa faixa, não explode nem
	# some.
	var half_ration: float = 3.0 * Population.CONSUMPTION_PER_CAPITA
	for _i in 2000:
		p.advance(1.0, 6, half_ration)
	_check(p.count > 0.0 and p.count < 6.0, "com comida parcial, população se estabiliza abaixo da capacidade cheia (%.2f)" % p.count)

func _test_buildings_farm_produces_without_a_deposit() -> void:
	var b := Buildings.new()
	var id := b.place(Buildings.Kind.FARM, Vector2i(4, 4))
	var mgr := Workers.new()
	var w := mgr.spawn(Vector2.ZERO)
	var m := MapGen.new()
	m.generate(5, 5, 1)   # mapa mínimo: a Fazenda não deveria nem tocar nele

	b.advance(1.0, m, mgr)
	_near(b.list[id].buffer, 0.0, 0.0001, "sem trabalhador alocado, Fazenda não acumula nada")

	b.assign(id, w)
	w.state = Worker.State.WORKING
	b.advance(1.0, m, mgr)
	_check(b.list[id].buffer > 0.0, "trabalhador WORKING na Fazenda produz comida sem depender de nenhum depósito do mapa")

	var taken := b.collect(id, 999.0)
	b.deliver("comida", taken)
	_check(b.stock["comida"] > 0.0, "comida coletada do pátio vira estoque jogável (mesmo caminho collect/deliver dos outros extratores)")

# ---- Fase 7: progressão (progression.gd) ----

func _test_progression_starts_at_level_one() -> void:
	var p := Progression.new()
	_check(p.level == 1, "vila nasce no nível 1")
	_check(p.xp == 0.0, "sem XP nenhum no início")
	_near(p.reveal_radius(), Progression.REVEAL_RADIUS_BY_LEVEL[1], 0.0001, "alcance do nível 1 bate com a tabela")

func _test_progression_levels_up_and_carries_remainder() -> void:
	var p := Progression.new()
	p.add_xp(Progression.XP_PER_LEVEL - 5.0)
	_check(p.level == 1, "ainda não bateu o teto do nível, continua no 1")
	p.add_xp(10.0)   # passa do teto por 5 de sobra
	_check(p.level == 2, "cruzar o teto de XP sobe de nível")
	_near(p.xp, 5.0, 0.0001, "o excedente vira XP do próximo nível, não é descartado")
	_near(p.reveal_radius(), Progression.REVEAL_RADIUS_BY_LEVEL[2], 0.0001, "alcance já reflete o nível novo")

func _test_progression_handles_multiple_levels_in_one_jump() -> void:
	var p := Progression.new()
	p.add_xp(Progression.XP_PER_LEVEL * 3.0 + 7.0)
	_check(p.level == 4, "um ganho grande de XP de uma vez pode subir vários níveis no mesmo passo")
	_near(p.xp, 7.0, 0.0001, "sobra exatamente o resto depois de pagar os 3 níveis")

func _test_progression_ignores_zero_and_negative_xp() -> void:
	var p := Progression.new()
	p.add_xp(0.0)
	p.add_xp(-10.0)
	_check(p.level == 1 and p.xp == 0.0, "XP zero ou negativo não faz nada (nem crasha)")

func _test_progression_caps_at_max_defined_level() -> void:
	var p := Progression.new()
	var max_level: int = Progression.REVEAL_RADIUS_BY_LEVEL.keys().max()
	p.add_xp(Progression.XP_PER_LEVEL * 100.0)   # XP muito além de qualquer nível definido
	_check(p.level == max_level, "não sobe além do último nível que a tabela define")
	_check(p.is_max_level(), "is_max_level() concorda que chegou ao teto")
	_near(p.reveal_radius(), Progression.REVEAL_RADIUS_BY_LEVEL[max_level], 0.0001, "alcance trava no valor do nível máximo")

# ---- Fase 3: carregador (carrier.gd / carriers.gd) ----

func _open_pathfinder(cols: int = 20, rows: int = 20, cell: float = 32.0) -> Pathfinder:
	var pf := Pathfinder.new()
	pf.setup(cols, rows, cell)
	return pf

func _test_carrier_picks_the_fullest_buffer() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.WAREHOUSE, Vector2i(0, 0))
	var lumberjack := b.place(Buildings.Kind.LUMBERJACK, Vector2i(5, 0))
	var quarry := b.place(Buildings.Kind.QUARRY, Vector2i(0, 5))
	b.list[lumberjack].buffer = 3.0
	b.list[quarry].buffer = 9.0

	var pf := _open_pathfinder()
	pf.rebuild([b.list[0].cell, b.list[lumberjack].cell, b.list[quarry].cell])
	var mgr := Carriers.new()
	var c := mgr.spawn(Vector2(160.0, 160.0))
	mgr.advance(0.1, pf, b)
	_check(c.source_building == quarry, "escolhe o pátio mais cheio (pedra), não o mais próximo nem o primeiro da lista")
	_check(c.state == Carrier.State.TO_SOURCE, "já parte pra buscar assim que decide")

func _test_carrier_full_round_trip_delivers_to_warehouse() -> void:
	var b := Buildings.new()
	var warehouse := b.place(Buildings.Kind.WAREHOUSE, Vector2i(0, 0))
	var lumberjack := b.place(Buildings.Kind.LUMBERJACK, Vector2i(6, 0))
	b.list[lumberjack].buffer = 7.0

	var pf := _open_pathfinder()
	pf.rebuild([b.list[warehouse].cell, b.list[lumberjack].cell])
	var mgr := Carriers.new()
	var c := mgr.spawn(pf.center_of(Vector2i(0, 1)))

	var steps := 0
	while c.state != Carrier.State.TO_WAREHOUSE and steps < 500:
		mgr.advance(0.1, pf, b)
		steps += 1
	_check(c.state == Carrier.State.TO_WAREHOUSE, "depois de chegar na fonte, pega a carga e parte pro armazém")
	_near(c.carrying, 7.0, 0.0001, "pega exatamente o que tinha no pátio (menos que a capacidade)")
	_near(b.list[lumberjack].buffer, 0.0, 0.0001, "pátio esvaziado depois da coleta")
	_check(c.resource == "madeira", "carrega o recurso certo pro tipo de prédio")

	steps = 0
	while c.state != Carrier.State.IDLE and steps < 500:
		mgr.advance(0.1, pf, b)
		steps += 1
	_check(c.state == Carrier.State.IDLE, "entrega no armazém e volta a ficar disponível")
	_near(c.carrying, 0.0, 0.0001, "descarregou tudo — não anda por aí com carga depois de entregar")
	_near(b.stock["madeira"], 7.0, 0.0001, "a entrega virou estoque jogável de verdade")

func _test_carrier_ignores_buffers_below_min_pickup() -> void:
	var b := Buildings.new()
	b.place(Buildings.Kind.WAREHOUSE, Vector2i(0, 0))
	var lumberjack := b.place(Buildings.Kind.LUMBERJACK, Vector2i(5, 0))
	b.list[lumberjack].buffer = 0.2   # bem abaixo de Carriers.MIN_PICKUP

	var pf := _open_pathfinder()
	var mgr := Carriers.new()
	var c := mgr.spawn(Vector2(160.0, 160.0))
	for _i in 10:
		mgr.advance(0.1, pf, b)
	_check(c.state == Carrier.State.IDLE, "pátio quase vazio não compensa a viagem — carregador espera")
	_near(b.list[lumberjack].buffer, 0.2, 0.0001, "nada foi coletado")

func _test_carrier_does_nothing_without_a_warehouse() -> void:
	var b := Buildings.new()
	var lumberjack := b.place(Buildings.Kind.LUMBERJACK, Vector2i(5, 0))
	b.list[lumberjack].buffer = 20.0

	var pf := _open_pathfinder()
	var mgr := Carriers.new()
	var c := mgr.spawn(Vector2(160.0, 160.0))
	for _i in 10:
		mgr.advance(0.1, pf, b)
	_check(c.state == Carrier.State.IDLE, "sem armazém no mapa, o carregador não tem pra onde levar nada")
	_near(b.list[lumberjack].buffer, 20.0, 0.0001, "e por isso nem chega a coletar")

# ---- Fase 1+2+3: cena ----

func _boot_main() -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	return main

# Prédios agora nascem por nível (ver `_maybe_unlock_next_tier` em main.gd),
# não todos de uma vez no frame 1 — vários testes de cena precisam de um
# tier específico já desbloqueado antes de procurar um prédio por Kind.
# Devolve o número de passos usados, pra quem chama poder mostrar isso numa
# mensagem de falha.
func _advance_to_tier(main: Node, tier: int, max_steps: int) -> int:
	var steps := 0
	while steps < max_steps and main._unlocked_level < tier:
		main._process(1.0 / 30.0)
		steps += 1
	return steps

func _test_scene_boots() -> void:
	var main := _boot_main()
	await process_frame
	await process_frame
	_check(main.map.cols == MAP_COLS and main.map.rows == MAP_ROWS, "a cena gera o mapa com as dimensões esperadas")
	_check(main.fog.explored_count() > 0, "a cena já revela a área inicial ao redor da vila")
	_check(is_instance_valid(main.camera) and main.camera.is_current(), "a câmera existe e está ativa")
	_check(main.water_sim.total_water() > 0.0, "a cena semeia pelo menos um lago")
	var wet := 0
	for v in main.water_sim.water:
		if v > 0.05:
			wet += 1
	var coverage: float = float(wet) / float(main.water_sim.water.size())
	_check(coverage > 0.005 and coverage < 0.15, "cobertura de lago é lago, não poça nem inundação (%.1f%%)" % (coverage * 100.0))
	main.queue_free()
	await process_frame

func _test_scene_camera_limits_to_map_size() -> void:
	var main := _boot_main()
	await process_frame
	var cell: int = main.CELL
	_check(main.camera.limit_left == 0 and main.camera.limit_top == 0, "limite da câmera começa na origem")
	_check(main.camera.limit_right == MAP_COLS * cell, "limite direito bate com a largura do mapa")
	_check(main.camera.limit_bottom == MAP_ROWS * cell, "limite inferior bate com a altura do mapa")
	main.queue_free()
	await process_frame

func _test_scene_click_reveals_fog() -> void:
	var main := _boot_main()
	await process_frame
	var before: int = main.fog.explored_count()
	# célula bem longe da vila (que já começa revelada), pra garantir que o
	# clique é a causa do aumento e não sobreposição com a área inicial.
	var far := Vector2(2, 2) * float(main.CELL)
	main._scout_at(far)
	_check(main.fog.explored_count() > before, "clicar num ponto distante revela área nova")
	_check(main.fog.is_visible(2, 2), "a célula clicada fica visível")
	main.queue_free()
	await process_frame

# `_pan_with_keys` lê teclas físicas direto (`Input.is_key_pressed`), não
# ações do InputMap — simular de verdade exige injetar um `InputEventKey` via
# `Input.parse_input_event`, não `Input.action_press` (que só afetaria uma
# ação nomeada, sem efeito nenhum aqui). E o estado só fica visível pra
# `is_key_pressed` depois que um frame passa — chamar `main._process` na
# sequência, sem esperar, testaria pan sem nunca apertar tecla nenhuma (foi
# o que a primeira versão deste teste fazia, silenciosamente).
func _press_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _test_scene_pan_moves_camera_within_limits() -> void:
	var main := _boot_main()
	await process_frame
	var start: Vector2 = main.camera.position

	await _press_key(KEY_D, true)
	for _i in 30:
		main._process(1.0 / 30.0)
	await _press_key(KEY_D, false)
	_check(main.camera.position.x > start.x, "segurar D move a câmera pra direita")
	_check(main.camera.position.y == start.y, "segurar D não move a câmera verticalmente")

	# Empurra muito além do limite: a câmera tem que ficar presa na borda do
	# mapa, não escorregar pra fora dele.
	await _press_key(KEY_D, true)
	for _i in 2000:
		main._process(1.0 / 30.0)
	await _press_key(KEY_D, false)
	_check(main.camera.position.x <= main.camera.limit_right, "câmera não ultrapassa o limite direito por mais que se empurre")
	_check(main.camera.position.x >= main.camera.limit_left, "câmera não ultrapassa o limite esquerdo")
	_check(main.camera.position.y >= main.camera.limit_top and main.camera.position.y <= main.camera.limit_bottom, "câmera continua dentro dos limites verticais")

	main.queue_free()
	await process_frame

# Testa o mecanismo de desbloqueio por nível em si (`_unlock_building_tier`
# em main.gd): cada tier acrescenta prédios específicos e nunca planta os de
# um tier ainda não alcançado. Só verifica os prédios que NÃO dependem de
# depósito (sempre nascem, qualquer semente) — Posto de Lenhador/Pedreira/
# Mina ficam de fora daqui de propósito, já cobertos por outros testes que
# lidam com a semente não ter o depósito por perto.
func _test_scene_buildings_unlock_progressively() -> void:
	var main := _boot_main()
	await process_frame
	_check(main._unlocked_level == 1, "a vila nasce já no tier 1")
	var kinds1: Array = main.buildings.list.map(func(b): return b.kind)
	_check(Buildings.Kind.WAREHOUSE in kinds1 and Buildings.Kind.FARM in kinds1 and Buildings.Kind.HOUSE in kinds1, "tier 1 tem Armazém, Fazenda e uma Casa")
	_check(not (Buildings.Kind.SAWMILL in kinds1) and not (Buildings.Kind.FORGE in kinds1), "prédios de tiers mais altos ainda não existem no tier 1")

	var s2 := _advance_to_tier(main, 2, 40000)
	_check(main._unlocked_level >= 2, "sobe pro tier 2 dentro de um teto razoável (%d passos)" % s2)
	var kinds2: Array = main.buildings.list.map(func(b): return b.kind)
	_check(kinds2.count(Buildings.Kind.HOUSE) == 2, "tier 2 acrescenta a segunda Casa")
	_check(not (Buildings.Kind.SAWMILL in kinds2), "Serraria continua fora até o tier 3")

	var s3 := _advance_to_tier(main, 3, 40000)
	var kinds3: Array = main.buildings.list.map(func(b): return b.kind)
	_check(Buildings.Kind.SAWMILL in kinds3, "tier 3 acrescenta a Serraria (%d passos)" % s3)
	_check(kinds3.count(Buildings.Kind.HOUSE) == 3, "tier 3 acrescenta a terceira Casa")
	_check(not (Buildings.Kind.FORGE in kinds3) and not (Buildings.Kind.STONE_WORKSHOP in kinds3), "Forja e Oficina de Pedra continuam fora até o tier 4")

	var s4 := _advance_to_tier(main, 4, 40000)
	var kinds4: Array = main.buildings.list.map(func(b): return b.kind)
	_check(Buildings.Kind.STONE_WORKSHOP in kinds4 and Buildings.Kind.GENERATOR in kinds4 and Buildings.Kind.FORGE in kinds4, "tier 4 acrescenta Oficina de Pedra, Gerador e Forja (%d passos)" % s4)
	_check(not (Buildings.Kind.WATERWHEEL in kinds4) and not (Buildings.Kind.WINDMILL in kinds4), "Roda D'Água e Moinho de Vento continuam fora até o tier 5 (o último)")

	# Roda D'Água/Moinho de Vento só nascem se existir célula válida perto
	# da vila (água de verdade ao lado / terreno alto o bastante) — mesma
	# regra de "explore mais" dos extratores de depósito, então não são uma
	# garantia como os prédios anteriores.
	var s5 := _advance_to_tier(main, 5, 40000)
	_check(main._unlocked_level >= 5, "sobe pro tier 5 (o último) dentro de um teto razoável (%d passos)" % s5)

	# Depois do último tier, subir de nível continua acontecendo (o alcance
	# de exploração ainda cresce, ver progression.gd), mas nenhum prédio
	# novo aparece — MAX_BUILDING_TIER é um teto de verdade, não só um
	# número que nunca é alcançado na prática.
	var buildings_before: int = main.buildings.list.size()
	for _i in 6000:
		main._process(1.0 / 30.0)
	_check(main.buildings.list.size() == buildings_before, "depois do tier 5, subir de nível não planta prédio novo nenhum (%d prédios antes e depois)" % buildings_before)

	main.queue_free()
	await process_frame

func _test_scene_worker_arrives_and_produces() -> void:
	var main := _boot_main()
	await process_frame
	_check(main.buildings.warehouse_id() >= 0, "a cena sempre nasce com um Armazém (é a própria vila)")

	# Nem todo prédio de produção tem trabalhador nesta cena de propósito: o
	# Armazém, o Gerador e as Casas são infraestrutura passiva, e a Oficina
	# de Pedra nasce sem trabalhador nenhum pra provar "energia OU
	# trabalhador" (ver o comentário em main.gd _ready()).
	var unstaffed_kinds := [Buildings.Kind.WAREHOUSE, Buildings.Kind.GENERATOR, Buildings.Kind.STONE_WORKSHOP, Buildings.Kind.HOUSE, Buildings.Kind.WATERWHEEL, Buildings.Kind.WINDMILL]

	# Fase 6: mão de obra não é mais instantânea — a população começa em
	# zero, então no primeiro frame ninguém tem trabalhador ainda nenhum. No
	# tier 1 (o único que já existe agora) isso vale só pra Fazenda.
	_check(main.workers.list.is_empty(), "no primeiro frame ainda não há trabalhador nenhum — população começa em zero")
	for building in main.buildings.list:
		if building.kind in unstaffed_kinds:
			continue
		_check(building.worker_id == -1, "prédio staffável espera na fila até a população crescer o bastante")

	# Prédios continuam aparecendo por vários níveis (ver
	# `_unlock_building_tier`) — só depois do último tier dá pra saber o
	# conjunto FINAL de prédios staffáveis do jogo e testar todos de uma vez.
	var unlock_steps := _advance_to_tier(main, main.MAX_BUILDING_TIER, 40000)
	var staffable: Array = main.buildings.list.filter(func(b): return not (b.kind in unstaffed_kinds))
	_check(staffable.size() >= 1, "a vila termina com pelo menos um prédio staffável (%d passos até o último tier)" % unlock_steps)

	var workshop_matches: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.STONE_WORKSHOP)

	# `Array.all()` num array vazio devolve true (vácuo) — por isso o
	# tamanho entra na condição também, senão o loop sairia no passo 0 antes
	# de qualquer trabalhador sequer nascer.
	var steps := 0
	while steps < 6000 and (main.workers.list.size() < staffable.size() or not main.workers.list.all(func(w): return w.state == Worker.State.WORKING)):
		main._process(1.0 / 30.0)
		steps += 1
	_check(main.workers.list.size() == staffable.size(), "com tempo suficiente, todo prédio staffável acaba ganhando um trabalhador (%d passos)" % steps)
	for w in main.workers.list:
		_check(w.state == Worker.State.WORKING, "todo trabalhador chega e começa a trabalhar dentro de um teto razoável")
	if workshop_matches.size() > 0:
		_check(workshop_matches[0].worker_id == -1, "a Oficina de Pedra nunca ganha trabalhador — energia é quem sustenta ela")

	# "Pátio + estoque entregue nunca regride" deixou de ser um invariante
	# seguro agora que a vila inteira existe (todos os 4 tiers): Serraria e
	# Gerador consomem madeira de verdade, Oficina de Pedra consome pedra,
	# Forja consome minério, e a própria população consome comida — o
	# estoque de um recurso pode cair mesmo com o extrator dele staffado e
	# produzindo, porque a queda vem de outro consumidor, não de falha de
	# produção. O que este teste consegue garantir de verdade: o pátio de
	# cada extrator staffado teve produção de verdade (ficou > 0) em algum
	# momento da janela — não que o total nunca desça.
	var extractors: Array = staffable.filter(func(b): return Buildings.RESOURCE_OF.has(b.kind))
	var saw_production := {}
	for building in extractors:
		saw_production[building.cell] = building.buffer > 0.0
	for _i in 60:
		main._process(1.0 / 30.0)
		for building in extractors:
			if building.buffer > 0.0:
				saw_production[building.cell] = true
	for building in extractors:
		_check(saw_production[building.cell], "extrator staffado produziu de verdade (pátio > 0) em algum momento da janela")

	main.queue_free()
	await process_frame

func _test_scene_population_grows_up_to_three_houses() -> void:
	var main := _boot_main()
	await process_frame
	# Não é exatamente 0.0: pelo menos um frame de verdade já rodou entre o
	# _ready() e esta checagem (o `await process_frame` do _boot_main), e
	# esse frame já chama _process() com o delta real do motor.
	_check(main.population.count < 1.0, "população praticamente não cresceu ainda logo após instanciar (%.3f)" % main.population.count)
	var houses_at_start: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.HOUSE)
	_check(houses_at_start.size() == 1, "a vila nasce com só UMA casa — as outras duas vêm com os níveis 2 e 3 (ver _unlock_building_tier)")

	# Prédios (inclusive Casa) só terminam de aparecer quando a vila sobe até
	# o último tier — ver o comentário em `_advance_to_tier`.
	var steps := _advance_to_tier(main, main.MAX_BUILDING_TIER, 40000)
	var houses: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.HOUSE)
	# Três casas, não duas: a Fazenda é o sexto prédio staffável, e junto com
	# o carregador soma 7 vagas — duas casas (capacidade 6) já não cobririam
	# nem as vagas, quanto mais deixar folga (ver o comentário em
	# _place_tier4_buildings).
	_check(houses.size() == 3, "com tempo suficiente, a vila termina com três casas (%d passos)" % steps)
	_check(main.buildings.housing_capacity() == Buildings.HOUSE_CAPACITY * 3, "a capacidade bate com o número de casas")

	for _i in 6000:
		main._process(1.0 / 30.0)
	_near(main.population.count, float(main.buildings.housing_capacity()), 0.01, "com tempo suficiente, população enche exatamente a capacidade habitacional")
	_check(main.population.employed() <= main.buildings.housing_capacity(), "nunca emprega mais gente do que a população permite")

	main.queue_free()
	await process_frame

func _test_scene_progression_grows_reveal_radius() -> void:
	var main := _boot_main()
	await process_frame
	_check(main.progression.level == 1, "vila começa no nível 1")
	# a 10 células do centro: fora do alcance do nível 1 (9), dentro do
	# alcance do nível 2 (12) — ver Progression.REVEAL_RADIUS_BY_LEVEL.
	var far_cell: Vector2i = main._village_cell + Vector2i(10, 0)
	_check(not main.fog.is_explored(far_cell.x, far_cell.y), "célula fora do alcance inicial ainda não foi explorada")

	var steps := 0
	while steps < 3000 and main.progression.level < 2:
		main._process(1.0 / 30.0)
		steps += 1
	_check(main.progression.level >= 2, "a vila sobe de nível dentro de um teto razoável de passos (%d)" % steps)
	_check(main.fog.is_explored(far_cell.x, far_cell.y), "depois de subir de nível, o alcance de exploração cresceu de verdade — uma célula antes escura foi vista")

	main.queue_free()
	await process_frame

# O ciclo inteiro da Fase 3: trabalhador produz no pátio, carregador busca e
# entrega no Armazém, e É SÓ AÍ que o estoque jogável (HUD) sobe. Um teto de
# passos bem mais largo que o do teste anterior — dá tempo do trabalhador
# chegar, produzir o suficiente pra valer a viagem (MIN_PICKUP), e do
# carregador fazer a ida e volta inteira.
func _test_scene_carrier_delivers_to_warehouse() -> void:
	var main := _boot_main()
	await process_frame
	# Fase 6: o carregador também espera a população crescer — não nasce
	# mais no primeiro frame (ver _test_scene_worker_arrives_and_produces).
	_check(main.carriers.list.is_empty(), "no primeiro frame ainda não há carregador — também espera população")

	var before := {}
	for resource in main.buildings.stock:
		before[resource] = main.buildings.stock[resource]

	var steps := 0
	var delivered := false
	while steps < 6000 and not delivered:
		main._process(1.0 / 30.0)
		steps += 1
		for resource in main.buildings.stock:
			if main.buildings.stock[resource] > before.get(resource, 0.0):
				delivered = true
	_check(delivered, "dentro de um teto razoável, o ciclo completo (produzir → coletar → entregar) rende estoque jogável de verdade (%d passos)" % steps)
	_check(main.carriers.list.size() == 1, "o carregador acabou nascendo assim que sobrou população disponível")

	main.queue_free()
	await process_frame

# Fase 4 de ponta a ponta: extrair → transportar → processar. Precisa de mais
# tempo que o teste anterior (a cadeia é uma etapa mais longa), por isso um
# teto de passos maior.
func _test_scene_processing_chain_produces_tabua_and_bloco() -> void:
	var main := _boot_main()
	await process_frame
	# Serraria só existe a partir do tier 3, Oficina de Pedra só do tier 4
	# (ver `_unlock_building_tier` em main.gd) — a cadeia inteira precisa da
	# vila já no último tier antes de sequer procurar os dois prédios.
	var unlock_steps := _advance_to_tier(main, main.MAX_BUILDING_TIER, 40000)
	var sawmill: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.SAWMILL)
	var workshop: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.STONE_WORKSHOP)
	_check(sawmill.size() == 1 and workshop.size() == 1, "a vila termina com Serraria e Oficina de Pedra (%d passos até o último tier)" % unlock_steps)
	_check(workshop[0].worker_id == -1, "a Oficina de Pedra continua sem trabalhador durante todo o teste")

	var steps := 0
	var got_tabua := false
	var got_bloco := false
	var was_powered := false
	while steps < 10000 and not (got_tabua and got_bloco):
		main._process(1.0 / 30.0)
		steps += 1
		got_tabua = main.buildings.stock.get("tábua", 0.0) > 0.0
		got_bloco = main.buildings.stock.get("bloco", 0.0) > 0.0
		was_powered = was_powered or workshop[0].powered
	_check(got_tabua, "a cadeia inteira rende tábua de verdade dentro de um teto razoável (%d passos)" % steps)
	_check(got_bloco, "a cadeia inteira rende bloco de verdade dentro de um teto razoável (%d passos)" % steps)
	_check(was_powered, "o bloco só saiu porque o Gerador alimentou a Oficina de Pedra em algum momento (sem trabalhador nenhum)")

	main.queue_free()
	await process_frame

# Terceira cadeia de ponta a ponta: Mina extrai minério da colina (Kind.HILLS,
# depósito sem uso desde a Fase 1), carregador entrega no Armazém, Forja
# processa em lingote — mesmo teste que a cadeia madeira/pedra, só que sem
# nenhum atalho por energia (Mina e Forja sempre têm trabalhador próprio).
func _test_scene_ore_chain_produces_lingote() -> void:
	var main := _boot_main()
	await process_frame
	# Mina só existe a partir do tier 3, Forja só do tier 4 (ver
	# `_unlock_building_tier` em main.gd).
	var unlock_steps := _advance_to_tier(main, main.MAX_BUILDING_TIER, 40000)
	var mine: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.MINE)
	var forge: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.FORGE)
	_check(forge.size() == 1, "a vila termina com a Forja (%d passos até o último tier)" % unlock_steps)
	if mine.is_empty():
		# A semente de teste fixa (9001, via _boot_main) pode não ter colina
		# dentro do raio de busca — mesma regra de "explore mais" das outras
		# duas cadeias. Sem Mina, não tem como a Forja receber minério; nada
		# mais deste teste é verificável.
		main.queue_free()
		await process_frame
		return

	var steps := 0
	var got_lingote := false
	while steps < 10000 and not got_lingote:
		main._process(1.0 / 30.0)
		steps += 1
		got_lingote = main.buildings.stock.get("lingote", 0.0) > 0.0
	_check(got_lingote, "a cadeia minério → lingote rende resultado de verdade dentro de um teto razoável (%d passos)" % steps)

	main.queue_free()
	await process_frame

# Roda D'Água e Moinho de Vento na cena de verdade (tier 5, o último):
# confirma que `_cell_near_water`/`_cell_on_high_ground` acham célula válida
# na semente real do jogo — medido à parte (fora deste arquivo) que existe
# água e terreno alto dentro do raio de busca a partir da vila, então isto
# não é sorte. O mecanismo de "energia sem combustível" em si já está
# provado isolado em `_test_buildings_waterwheel_powers_without_burning_any_stock`
# e `_test_buildings_windmill_powers_without_burning_any_stock` — aqui
# checar `building.powered` não distinguiria QUAL fonte alimentou (Gerador
# também pode estar no raio do mesmo prédio), então não tentamos.
func _test_scene_waterwheel_and_windmill_placement() -> void:
	var main := _boot_main()
	await process_frame
	var unlock_steps := _advance_to_tier(main, main.MAX_BUILDING_TIER, 40000)
	var waterwheel: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.WATERWHEEL)
	var windmill: Array = main.buildings.list.filter(func(b): return b.kind == Buildings.Kind.WINDMILL)
	_check(waterwheel.size() == 1, "a semente real do jogo tem água perto o bastante da vila pra Roda D'Água nascer (%d passos até o último tier)" % unlock_steps)
	_check(windmill.size() == 1, "a semente real do jogo tem terreno alto o bastante perto da vila pro Moinho de Vento nascer")
	if waterwheel.size() == 1:
		_check(main._has_adjacent_water(waterwheel[0].cell), "a célula onde a Roda D'Água nasceu realmente tem água de verdade do lado")
	if windmill.size() == 1:
		_check(main.map.height_at(windmill[0].cell.x, windmill[0].cell.y) >= main.WINDMILL_MIN_HEIGHT, "a célula onde o Moinho nasceu realmente está no limiar de altura exigido")

	main.queue_free()
	await process_frame
