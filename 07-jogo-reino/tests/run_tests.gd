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

	await _test_scene_boots()
	await _test_scene_camera_limits_to_map_size()
	await _test_scene_click_reveals_fog()
	await _test_scene_pan_moves_camera_within_limits()

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

# ---- Fase 1: cena ----

func _boot_main() -> Node:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	return main

func _test_scene_boots() -> void:
	var main := _boot_main()
	await process_frame
	await process_frame
	_check(main.map.cols == MAP_COLS and main.map.rows == MAP_ROWS, "a cena gera o mapa com as dimensões esperadas")
	_check(main.fog.explored_count() > 0, "a cena já revela a área inicial ao redor da vila")
	_check(is_instance_valid(main.camera) and main.camera.is_current(), "a câmera existe e está ativa")
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
