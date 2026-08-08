extends SceneTree

# Testes headless de "O Vale em Chamas".
#
# O jogo é um sistema físico com regras que se realimentam, e num sistema
# desses a regressão perigosa não é a exceção — é o EQUILÍBRIO. Ninguém quebra
# a propagação do fogo por acidente; o que se quebra por acidente é a relação
# entre "quanto tempo o capim queima" e "quanto tempo ele leva pra acender o
# vizinho", e aí a frente de fogo se apaga sozinha e o jogo inteiro deixa de
# existir sem uma única exceção no console.
#
# Por isso a suíte tem três camadas:
#
#   1. **Unidade** — cada regra do autômato isolada (vento, relevo, umidade,
#      combustível, faísca, previsão), com número: não "o vento espalha mais",
#      e sim "a favor do vento a frente anda pelo menos 1,8× mais rápido".
#   2. **Comportamento** — brigadistas e moradores diante do campo.
#   3. **Level design** — o bot joga as seis fases. Tem que vencer todas. E, do
#      outro lado, quem não faz nada tem que PERDER todas: uma fase que se
#      resolve sozinha não é uma fase, e esse foi um bug real deste projeto (a
#      "encosta" nasceu com o povoado já cercado de terra batida e vencia
#      sozinha).

const STEP := 0.1

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame

	_test_terrain_table()
	_test_burn_outlasts_ignition()
	_test_sim_setup()
	_test_front_speed()
	_test_wind()
	_test_slope()
	_test_moisture_and_water()
	_test_fuel_is_spent_forever()
	_test_firebreak_stops_fire()
	_test_embers_jump_a_firebreak()
	_test_determinism()
	_test_fixed_timestep()
	_test_forecast()

	_test_levels_are_well_formed()
	_test_level_parsing()
	_test_tools()

	_test_nav_avoids_solids()
	_test_nav_blocks_on_fire()
	_test_flee_prefers_safe_shelter()

	_test_order_assignment()
	_test_crew_retreats_from_heat()
	_test_unreachable_order_expires()
	_test_civilian_awareness()
	_test_civilian_lost_in_fire()
	_test_crew_calms_panic()

	_test_mission_budget()
	_test_mission_defeat_is_immediate()
	_test_mission_stars()
	_test_progress_roundtrip()

	_test_bot_wins_every_level()
	_test_doing_nothing_loses_every_level()

	await _test_scene_boots()
	await _test_scene_click_orders()
	await _test_scene_hud_does_not_dig()
	await _test_scene_shortcuts()
	await _test_scene_camera_limits()

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
	_check(absf(a - b) <= tolerance, "%s (%.3f vs %.3f)" % [label, a, b])

# ---- ferramentas de bancada ----

# Um campo uniforme de um terreno só, plano, pra medir uma regra de cada vez.
func _bench(terrain: int, cols: int = 30, rows: int = 5, slope: float = 0.0) -> FireSim:
	var kinds := PackedInt32Array()
	var heights := PackedFloat32Array()
	kinds.resize(cols * rows)
	heights.resize(cols * rows)
	for y in rows:
		for x in cols:
			kinds[y * cols + x] = terrain
			heights[y * cols + x] = slope * float(x)
	var sim := FireSim.new()
	sim.setup(cols, rows, kinds, heights, 4242)
	sim.set_wind(0.0, 0.0, 0.0, 24.0)
	return sim

# Segundos por célula que uma frente leva pra atravessar a fileira do meio.
# Mede no MIOLO (da 5ª à 20ª célula): perto da célula acesa à mão o número
# ainda carrega o empurrão inicial, e perto da borda a frente perde vizinhos.
func _front_speed(sim: FireSim, row: int = 2, limit: float = 600.0) -> float:
	var arrival := {}
	while sim.elapsed < limit:
		sim.advance(FireSim.TICK)
		for x in sim.cols:
			if not arrival.has(x) and sim.state_at(x, row) != FireSim.INTACT:
				arrival[x] = sim.elapsed
		if arrival.has(20) or sim.is_out():
			break
	if not (arrival.has(5) and arrival.has(20)):
		return -1.0
	return (float(arrival[20]) - float(arrival[5])) / 15.0

# ---- autômato ----

func _test_terrain_table() -> void:
	for kind in [Terrain.GRASS, Terrain.BRUSH, Terrain.TREE, Terrain.HOUSE, Terrain.FIELD]:
		_check(Terrain.is_flammable(kind), "%s queima" % Terrain.name_of(kind))
	for kind in [Terrain.DIRT, Terrain.ROCK, Terrain.WATER]:
		_check(not Terrain.is_flammable(kind), "%s não queima" % Terrain.name_of(kind))
	_check(Terrain.from_char("H") == Terrain.HOUSE, "H é casa")
	_check(Terrain.from_char("?") == Terrain.GRASS, "caractere desconhecido vira capim")
	# Cavar aceiro não pode DEMOLIR o que a fase manda salvar — foi um bug real:
	# o brigadista derrubava a casa pra impedir que ela queimasse.
	_check(not Terrain.can_dig(Terrain.HOUSE), "não se cava aceiro em cima da casa")
	_check(not Terrain.can_dig(Terrain.ROCK), "não se cava rocha")
	_check(Terrain.can_dig(Terrain.BRUSH), "cava-se mato")
	_check(not Terrain.is_walkable(Terrain.WATER), "não se anda na água")
	_check(Terrain.is_walkable(Terrain.DIRT), "anda-se na terra")

# A regra silenciosa que sustenta o jogo inteiro: uma célula precisa ficar em
# chamas mais tempo do que leva pra acender a vizinha. Quando isso deixa de
# valer, a frente de fogo se apaga sozinha e não há incêndio nenhum — foi
# exatamente o que aconteceu na primeira calibração, com capim queimando 7,7s e
# levando 9,8s pra pegar no vizinho.
func _test_burn_outlasts_ignition() -> void:
	for kind in [Terrain.GRASS, Terrain.BRUSH, Terrain.TREE, Terrain.FIELD]:
		var lifetime: float = Terrain.fuel_of(kind) / Terrain.burn_rate_of(kind)
		_check(lifetime >= 10.0, "%s queima por pelo menos 10s (%.1fs)" % [Terrain.name_of(kind), lifetime])
	var sim := _bench(Terrain.GRASS)
	sim.ignite(2, 2)
	var speed := _front_speed(sim)
	_check(speed > 0.0, "uma frente de fogo em capim não morre sozinha")

func _test_sim_setup() -> void:
	var sim := _bench(Terrain.GRASS)
	_check(sim.cols == 30 and sim.rows == 5, "dimensões do campo de teste")
	_check(sim.fuel[0] == Terrain.fuel_of(Terrain.GRASS), "combustível inicial vem do terreno")
	_check(sim.state[0] == FireSim.INTACT, "tudo começa intacto")
	_check(sim.burning_count() == 0, "nada queimando antes de acender")
	_check(sim.ignite(3, 2), "acender capim funciona")
	_check(sim.state_at(3, 2) == FireSim.BURNING, "a célula acesa está em chamas")
	_check(not sim.ignite(3, 2), "acender de novo o que já queima não faz nada")
	var rock := _bench(Terrain.ROCK)
	_check(not rock.ignite(3, 2), "rocha não acende")

func _test_front_speed() -> void:
	var sim := _bench(Terrain.GRASS)
	sim.ignite(0, 2)
	var speed := _front_speed(sim)
	# A faixa é larga de propósito: o teste protege o RITMO do jogo (dá tempo de
	# cavar? o fogo assusta?), não um número exato. Fora dela, todas as fases
	# precisam ser rebalanceadas — e é isso que se quer saber.
	_check(speed >= 1.5 and speed <= 4.0, "capim plano: %.2f s/célula (esperado 1,5–4,0)" % speed)

	var brush := _bench(Terrain.BRUSH)
	brush.ignite(0, 2)
	var brush_speed := _front_speed(brush)
	_check(brush_speed < speed, "mato pega mais rápido que capim (%.2f < %.2f)" % [brush_speed, speed])

func _test_wind() -> void:
	var calm := _bench(Terrain.GRASS)
	calm.ignite(0, 2)
	var calm_speed := _front_speed(calm)

	var tail := _bench(Terrain.GRASS)
	tail.set_wind(0.0, 1.0, 0.0, 24.0)          # soprando para +x
	tail.ignite(0, 2)
	var tail_speed := _front_speed(tail)

	var head := _bench(Terrain.GRASS)
	head.set_wind(PI, 1.0, 0.0, 24.0)           # soprando para -x
	head.ignite(0, 2)
	var head_speed := _front_speed(head)

	_check(tail_speed > 0.0 and tail_speed <= calm_speed / 1.8,
		"a favor do vento a frente anda ao menos 1,8× mais rápido (%.2f vs %.2f)" % [tail_speed, calm_speed])
	# Contra o vento tem que ficar LENTO, não parar: "quase parado" é uma
	# decisão do jogador (dá pra ignorar aquele lado por ora); "parado" seria
	# uma regra invisível resolvendo a fase sozinha.
	_check(head_speed > calm_speed * 2.0, "contra o vento a frente rasteja (%.2f vs %.2f)" % [head_speed, calm_speed])
	_check(head_speed > 0.0, "contra o vento a frente ainda anda")

func _test_slope() -> void:
	var flat := _bench(Terrain.GRASS)
	flat.ignite(0, 2)
	var flat_speed := _front_speed(flat)

	var up := _bench(Terrain.GRASS, 30, 5, 1.0)
	up.ignite(0, 2)
	var up_speed := _front_speed(up)

	var down := _bench(Terrain.GRASS, 30, 5, -1.0)
	down.ignite(0, 2)
	var down_speed := _front_speed(down)

	_check(up_speed < flat_speed, "morro acima o fogo acelera (%.2f < %.2f)" % [up_speed, flat_speed])
	_check(down_speed > flat_speed, "morro abaixo o fogo desacelera (%.2f > %.2f)" % [down_speed, flat_speed])

func _test_moisture_and_water() -> void:
	var dry := _bench(Terrain.GRASS)
	dry.ignite(0, 2)
	var dry_speed := _front_speed(dry)

	var wet := _bench(Terrain.GRASS)
	for idx in wet.moisture.size():
		wet.moisture[idx] = 0.85
	wet.ignite(0, 2)
	var wet_speed := _front_speed(wet)
	# Encharcado a frente não atravessa: `_front_speed` devolve -1 quando ela
	# morre antes da 20ª célula, e é justamente esse o efeito desejado.
	_check(wet_speed < 0.0 or wet_speed > dry_speed * 2.0,
		"capim encharcado segura a frente (%.2f vs %.2f)" % [wet_speed, dry_speed])

	# A água tem que APAGAR chama acesa: é o único jeito de desfazer no jogo,
	# e é o que a fase "Sede" ensina.
	var sim := _bench(Terrain.GRASS)
	sim.ignite(5, 2)
	_check(sim.state_at(5, 2) == FireSim.BURNING, "acendeu pra apagar")
	_check(sim.douse(5, 2), "jogar água funciona")
	_check(sim.state_at(5, 2) == FireSim.INTACT, "a água apaga a chama")
	_check(sim.heat[sim.index_of(5, 2)] == 0.0, "a água leva o calor junto")
	_check(sim.moisture[sim.index_of(5, 2)] >= FireSim.DOUSE_MOISTURE - 0.01, "a célula fica molhada")

	# Molhado seca com o tempo: se não secasse, um balde valeria pra sempre e a
	# escassez de água deixaria de significar qualquer coisa.
	for _i in 600:
		sim.advance(FireSim.TICK)
	_check(sim.moisture[sim.index_of(5, 2)] < FireSim.DOUSE_MOISTURE - 0.1, "a água evapora com o tempo")

func _test_fuel_is_spent_forever() -> void:
	var sim := _bench(Terrain.GRASS)
	sim.ignite(5, 2)
	while sim.state_at(5, 2) == FireSim.BURNING and sim.elapsed < 200.0:
		sim.advance(FireSim.TICK)
	_check(sim.state_at(5, 2) == FireSim.BURNT, "sem combustível a célula vira cinza")
	_check(sim.fuel[sim.index_of(5, 2)] == 0.0, "o combustível acabou")
	_check(not sim.ignite(5, 2), "cinza não pega fogo de novo")
	_check(sim.cells_burnt > 0, "o contador de área queimada subiu")

	# Casa perdida é casa que virou cinza — não casa que pegou fogo. A
	# diferença é o que dá sentido a correr com um balde d'água.
	var kinds := PackedInt32Array([Terrain.HOUSE])
	var heights := PackedFloat32Array([0.0])
	var one := FireSim.new()
	one.setup(1, 1, kinds, heights, 7)
	one.ignite(0, 0)
	_check(one.houses_standing() == 1, "casa em chamas ainda está de pé")
	while one.state_at(0, 0) == FireSim.BURNING and one.elapsed < 400.0:
		one.advance(FireSim.TICK)
	_check(one.houses_lost == 1, "casa que virou cinza conta como perdida")
	_check(one.houses_standing() == 0, "e não está mais de pé")

func _test_firebreak_stops_fire() -> void:
	var sim := _bench(Terrain.GRASS, 24, 7)
	# Uma coluna inteira de terra batida, do topo à base: é o aceiro.
	for y in sim.rows:
		_check(sim.strip(12, y), "cavou aceiro em (12,%d)" % y)
	_check(sim.kind_at(12, 3) == Terrain.DIRT, "aceiro virou terra")
	sim.ignite(2, 3)
	for _i in 3000:
		sim.advance(FireSim.TICK)
		if sim.is_out():
			break
	_check(sim.is_out(), "o incêndio acabou sozinho")
	var crossed := false
	for y in sim.rows:
		for x in range(13, sim.cols):
			if sim.state_at(x, y) != FireSim.INTACT:
				crossed = true
	_check(not crossed, "sem vento, o fogo não passa do aceiro")
	_check(sim.state_at(4, 3) == FireSim.BURNT, "mas queimou tudo do lado de cá")

	# Cavar tem limites, e eles são regra de jogo, não detalhe: ninguém cava
	# dentro do fogo, e cavar cinza não devolve nada.
	var live := _bench(Terrain.GRASS)
	live.ignite(4, 2)
	_check(not live.strip(4, 2), "não se cava célula em chamas")

func _test_embers_jump_a_firebreak() -> void:
	# Sem faísca, um aceiro de uma célula resolveria qualquer fase pra sempre e
	# o jogo teria uma resposta certa só. Com vento forte a brasa PULA, e é isso
	# que obriga a cavar largo ou molhar o outro lado.
	var sim := _bench(Terrain.GRASS, 30, 9)
	sim.set_wind(0.0, 1.0, 0.0, 60.0)
	for y in sim.rows:
		sim.strip(10, y)
	for y in range(2, 7):
		sim.ignite(6, y)
	var jumped := false
	for _i in 2500:
		sim.advance(FireSim.TICK)
		for y in sim.rows:
			for x in range(11, sim.cols):
				if sim.state_at(x, y) != FireSim.INTACT:
					jumped = true
		if jumped or sim.is_out():
			break
	_check(jumped, "com vendaval a brasa atravessa um aceiro de uma cava")

	# E com vento fraco não atravessa: a faísca precisa ser consequência do
	# vento, não um dado solto que castiga o jogador sem aviso.
	var calm := _bench(Terrain.GRASS, 30, 9)
	calm.set_wind(0.0, 0.2, 0.0, 60.0)
	for y in calm.rows:
		calm.strip(10, y)
	for y in range(2, 7):
		calm.ignite(6, y)
	var calm_jumped := false
	for _i in 2500:
		calm.advance(FireSim.TICK)
		for y in calm.rows:
			for x in range(11, calm.cols):
				if calm.state_at(x, y) != FireSim.INTACT:
					calm_jumped = true
		if calm.is_out():
			break
	_check(not calm_jumped, "com vento fraco o aceiro segura")

# Sem determinismo o bot dos testes não prova nada (cada rodada seria outra
# fase) e o jogador não consegue APRENDER uma fase, que é o núcleo do gênero.
func _test_determinism() -> void:
	var a := Levels.build_sim(Levels.get_level(1))
	var b := Levels.build_sim(Levels.get_level(1))
	for i in 900:
		a.advance(FireSim.TICK)
		b.advance(FireSim.TICK)
		if i == 300:
			a.strip(20, 5)
			b.strip(20, 5)
		if i == 500:
			a.douse(22, 6)
			b.douse(22, 6)
	var same := true
	for idx in a.state.size():
		if a.state[idx] != b.state[idx] or absf(a.heat[idx] - b.heat[idx]) > 0.0001:
			same = false
			break
	_check(same, "mesma semente e mesmas ações dão exatamente o mesmo incêndio")
	_check(a.cells_burnt == b.cells_burnt, "a área queimada bate")

	# Contraprova, pra o teste acima não ser vácuo: mexer no sorteio de UMA
	# célula tem que mudar QUANDO ela acende. Comparar estados finais não serve
	# — no fim da partida quase tudo virou cinza dos dois lados, e duas
	# simulações diferentes empatam.
	var base := _bench(Terrain.GRASS)
	base.ignite(0, 2)
	var tweaked := _bench(Terrain.GRASS)
	tweaked.jitter[tweaked.index_of(6, 2)] *= 1.9
	tweaked.ignite(0, 2)
	var base_time := -1.0
	var tweaked_time := -1.0
	for _i in 2000:
		base.advance(FireSim.TICK)
		tweaked.advance(FireSim.TICK)
		if base_time < 0.0 and base.state_at(6, 2) != FireSim.INTACT:
			base_time = base.elapsed
		if tweaked_time < 0.0 and tweaked.state_at(6, 2) != FireSim.INTACT:
			tweaked_time = tweaked.elapsed
		if base_time > 0.0 and tweaked_time > 0.0:
			break
	_check(base_time > 0.0 and tweaked_time > base_time + 0.5,
		"célula mais teimosa demora mais a pegar (%.1fs vs %.1fs)" % [tweaked_time, base_time])

# O incêndio anda em passos fixos, então a taxa de quadros não pode mudar o
# jogo: dois passos de 0,05s têm que dar no mesmo que um de 0,1s.
func _test_fixed_timestep() -> void:
	var a := _bench(Terrain.GRASS)
	var b := _bench(Terrain.GRASS)
	a.ignite(3, 2)
	b.ignite(3, 2)
	for _i in 300:
		a.advance(0.1)
		b.advance(0.05)
		b.advance(0.05)
	_check(a.ticks == b.ticks, "mesmo número de passos (%d vs %d)" % [a.ticks, b.ticks])
	var same := true
	for idx in a.state.size():
		if a.state[idx] != b.state[idx]:
			same = false
	_check(same, "o resultado não depende do tamanho do frame")

	var slow := _bench(Terrain.GRASS)
	slow.ignite(3, 2)
	var ran: int = slow.advance(5.0)
	_check(ran <= 12, "um delta gigante não trava o jogo tentando recuperar tudo (%d passos)" % ran)

func _test_forecast() -> void:
	var sim := _bench(Terrain.GRASS, 24, 7)
	for y in sim.rows:
		sim.strip(12, y)
	sim.ignite(2, 3)
	sim.advance(FireSim.TICK)
	var eta := sim.forecast()

	_check(eta[sim.index_of(2, 3)] == 0.0, "onde já queima, o tempo é zero")
	_check(eta[sim.index_of(4, 3)] < eta[sim.index_of(8, 3)], "mais perto do fogo, menos tempo")
	_check(eta[sim.index_of(4, 3)] > 0.0, "chegar até a vizinha leva algum tempo")
	# O que faz a previsão ENSINAR em vez de só informar: atrás do aceiro ela
	# diz "nunca", e o jogador vê o próprio plano funcionando antes da chama.
	_check(eta[sim.index_of(16, 3)] >= FireSim.FORECAST_INF, "atrás do aceiro o fogo não chega")
	_check(eta[sim.index_of(11, 3)] < FireSim.FORECAST_INF, "antes do aceiro, chega")

	# A previsão tem que bater com a realidade, não só ser monotônica.
	var real := _bench(Terrain.GRASS, 24, 7)
	real.ignite(2, 3)
	real.advance(FireSim.TICK)
	var predicted: float = real.forecast()[real.index_of(8, 3)]
	var actual := -1.0
	while real.elapsed < 400.0:
		real.advance(FireSim.TICK)
		if real.state_at(8, 3) != FireSim.INTACT:
			actual = real.elapsed
			break
	_check(actual > 0.0, "o fogo de fato chegou em (8,3)")
	# A previsão é aproximada de propósito (um jogo que entrega o futuro exato
	# não tem decisão nenhuma), mas tem que ser aproximada pro lado certo: um
	# aviso que erra por três vezes é pior que nenhum.
	_check(predicted > actual * 0.5 and predicted < actual * 2.0,
		"a previsão fica na ordem de grandeza certa (previu %.0fs, levou %.0fs)" % [predicted, actual])

# ---- fases ----

func _test_levels_are_well_formed() -> void:
	_check(Levels.count() == 6, "seis fases")
	for i in Levels.count():
		var level := Levels.get_level(i)
		var id: String = level["id"]
		var lines: Array = level["map"]
		var width: int = String(lines[0]).length()
		var rectangular := true
		for line in lines:
			if String(line).length() != width:
				rectangular = false
		_check(rectangular, "%s: o mapa é retangular" % id)

		if level.has("heights"):
			var heights: Array = level["heights"]
			var matches: bool = heights.size() == lines.size()
			for line in heights:
				if String(line).length() != width:
					matches = false
			_check(matches, "%s: o relevo tem a mesma forma do mapa" % id)

		var parsed := Levels.parse(level)
		_check(parsed.ignitions.size() > 0, "%s: tem foco de incêndio" % id)
		_check(parsed.crew.size() >= 3, "%s: tem brigadistas (%d)" % [id, parsed.crew.size()])
		_check(parsed.houses_total > 0, "%s: tem casas" % id)
		# Meta maior que o número de casas é derrota no primeiro quadro, e foi
		# um bug real: a fase 6 nasceu pedindo 4 casas num mapa com 3.
		_check(int(level["goal_houses"]) <= parsed.houses_total,
			"%s: a meta (%d) cabe nas casas que existem (%d)" % [id, int(level["goal_houses"]), parsed.houses_total])
		_check(int(level["goal_houses"]) > 0, "%s: a meta não é zero" % id)
		# Gente sem para onde ir não é desafio, é armadilha.
		if parsed.civilians.size() > 0:
			_check(parsed.shelters.size() > 0, "%s: se há gente, há abrigo" % id)
		_check(String(level["teaches"]) != "", "%s: declara o que ensina" % id)

func _test_level_parsing() -> void:
	var level := Levels.get_level(0)
	var parsed := Levels.parse(level)
	_check(parsed.cols == String(level["map"][0]).length(), "largura lida do mapa")
	_check(parsed.rows == (level["map"] as Array).size(), "altura lida do mapa")
	for cell in parsed.ignitions:
		_check(parsed.kinds[cell.y * parsed.cols + cell.x] == Terrain.GRASS, "o foco fica sobre capim")
	for cell in parsed.crew:
		_check(parsed.kinds[cell.y * parsed.cols + cell.x] == Terrain.GRASS, "o brigadista começa em capim")

	# O abrigo tem que ser terra batida. Um abrigo de capim pegaria fogo com
	# gente dentro, o que é o oposto de um abrigo.
	var with_shelter := Levels.parse(Levels.get_level(3))
	_check(with_shelter.shelters.size() > 0, "a fase 4 tem abrigo")
	for cell in with_shelter.shelters:
		var kind: int = with_shelter.kinds[cell.y * with_shelter.cols + cell.x]
		_check(kind == Terrain.DIRT, "o abrigo é terra batida, não capim")
		_check(not Terrain.is_flammable(kind), "e portanto não queima")

	var sim := Levels.build_sim(level)
	_check(sim.burning_count() == parsed.ignitions.size(), "a partida começa com os focos acesos")
	var flat := Levels.build_sim(Levels.get_level(0))
	_check(flat.height[0] == 0.0, "fase sem relevo é plana")
	var hilly := Levels.build_sim(Levels.get_level(2))
	var highest := 0.0
	for h in hilly.height:
		highest = maxf(highest, h)
	_check(highest > 0.0, "a fase da encosta tem morro de verdade")

func _test_tools() -> void:
	var sim := _bench(Terrain.GRASS, 12, 5)
	sim.kind[sim.index_of(4, 2)] = Terrain.HOUSE
	sim.kind[sim.index_of(5, 2)] = Terrain.ROCK
	sim.ignite(1, 2)

	_check(Tools.can_target(Tools.DIG, sim, Vector2i(8, 2)), "dá pra cavar capim intacto")
	_check(not Tools.can_target(Tools.DIG, sim, Vector2i(4, 2)), "não dá pra cavar a casa")
	_check(not Tools.can_target(Tools.DIG, sim, Vector2i(5, 2)), "não dá pra cavar rocha")
	_check(not Tools.can_target(Tools.DIG, sim, Vector2i(1, 2)), "não dá pra cavar no fogo")
	_check(Tools.can_target(Tools.WATER, sim, Vector2i(1, 2)), "dá pra jogar água no fogo")
	_check(Tools.can_target(Tools.BACKFIRE, sim, Vector2i(8, 2)), "dá pra atear contra-fogo no capim")
	_check(not Tools.can_target(Tools.BACKFIRE, sim, Vector2i(5, 2)), "não se ateia fogo em rocha")
	_check(not Tools.can_target(Tools.DIG, sim, Vector2i(-1, 0)), "fora do mapa não vale")

	_check(Tools.apply(Tools.DIG, sim, Vector2i(8, 2)), "cavar surte efeito")
	_check(sim.kind_at(8, 2) == Terrain.DIRT, "e o chão virou terra")
	_check(Tools.apply(Tools.BACKFIRE, sim, Vector2i(9, 2)), "contra-fogo acende")
	_check(sim.state_at(9, 2) == FireSim.BURNING, "e a célula pega fogo")
	_check(Tools.seconds_of(Tools.DIG) > Tools.seconds_of(Tools.WATER),
		"cavar é mais lento que molhar — é o que dá papel às duas")
	_check(not Tools.is_limited(Tools.DIG), "aceiro não tem conta")
	_check(Tools.is_limited(Tools.WATER), "água tem conta")

# ---- navegação ----

func _test_nav_avoids_solids() -> void:
	var sim := _bench(Terrain.GRASS, 16, 9)
	for y in range(0, 7):
		sim.kind[sim.index_of(8, y)] = Terrain.ROCK
	var nav := Nav.new()
	nav.setup(sim)

	_check(nav.is_blocked(Vector2i(8, 3)), "rocha é parede")
	_check(not nav.is_blocked(Vector2i(8, 8)), "a passagem embaixo está livre")
	var route := nav.path(Vector2i(2, 3), Vector2i(14, 3))
	_check(route.size() > 0, "existe rota até o outro lado")
	var crossed := false
	for cell in route:
		if sim.kind_at(cell.x, cell.y) == Terrain.ROCK:
			crossed = true
	_check(not crossed, "a rota não atravessa a rocha")
	# Com movimento diagonal, dar a volta por baixo custa os mesmos 12 passos da
	# reta — contar passos não prova desvio nenhum. O que prova é a rota ter
	# descido até a altura da passagem.
	var lowest := 0
	for cell in route:
		lowest = maxi(lowest, cell.y)
	_check(lowest >= 7, "a rota desce até a passagem embaixo da rocha (chegou em y=%d)" % lowest)

	sim.kind[sim.index_of(4, 4)] = Terrain.HOUSE
	nav.rebuild()
	_check(nav.is_blocked(Vector2i(4, 4)), "casa também é obstáculo")
	_check(nav.nearest_free(Vector2i(4, 4)) != Vector2i(4, 4), "quem cai numa casa é empurrado pra fora")

func _test_nav_blocks_on_fire() -> void:
	var sim := _bench(Terrain.GRASS, 16, 9)
	var nav := Nav.new()
	nav.setup(sim)
	var clear := nav.path(Vector2i(2, 4), Vector2i(14, 4))
	_check(clear.size() > 0, "com o vale limpo, o caminho é direto")

	for y in sim.rows:
		sim.ignite(8, y)
	nav.rebuild()
	_check(nav.is_blocked(Vector2i(8, 4)), "não se atravessa uma frente de fogo")
	_check(nav.path(Vector2i(2, 4), Vector2i(14, 4)).is_empty(),
		"com o vale cortado pelo fogo, não há rota — e quem chamou precisa tratar isso")

func _test_flee_prefers_safe_shelter() -> void:
	# Dois abrigos: um logo ali, colado no incêndio, e um longe e frio. Contando
	# PASSOS o morador escolhe o perto e corre pra dentro do fogo — foi
	# exatamente o que uma fase inteira fez, com o abrigo a quatro células do
	# foco. Contando o PREÇO do caminho, ele escolhe o longe.
	var sim := _bench(Terrain.GRASS, 30, 9)
	for y in range(2, 7):
		sim.ignite(12, y)
	for _i in 40:
		sim.advance(FireSim.TICK)
	var nav := Nav.new()
	nav.setup(sim)

	var near_shelter := Vector2i(10, 4)     # do lado do fogo
	var far_shelter := Vector2i(2, 4)       # longe, atrás do morador
	var target := nav.flee_target(Vector2i(7, 4), [near_shelter, far_shelter])
	_check(target == far_shelter, "foge para o abrigo mais SEGURO, não para o mais perto")

	var hot := nav.cost_of(nav.path(Vector2i(7, 4), near_shelter))
	var cold := nav.cost_of(nav.path(Vector2i(7, 4), far_shelter))
	_check(hot > cold, "o caminho quente custa mais que o frio (%.1f > %.1f)" % [hot, cold])

	# Sem abrigo algum, ainda assim vai para o lugar mais frio que alcança.
	var refuge := nav.safest_nearby(Vector2i(11, 4))
	_check(sim.danger_at(refuge.x, refuge.y) < sim.danger_at(11, 4), "sem abrigo, corre pro canto mais frio")

# ---- agentes ----

func _mission_at(level_index: int) -> Mission:
	var mission := Mission.new()
	mission.start(level_index)
	return mission

func _test_order_assignment() -> void:
	var mission := _mission_at(0)
	var crew_cell: Vector2i = mission.parsed.crew[0]
	var target := crew_cell + Vector2i(2, 0)
	_check(mission.order(Tools.DIG, target), "a ordem foi aceita")
	_check(mission.agents.pending_orders() == 1, "e entrou na fila")
	_check(not mission.order(Tools.DIG, target), "não se empilham duas ordens na mesma célula")

	for _i in 200:
		mission.update(STEP)
		if mission.agents.orders_done > 0:
			break
	_check(mission.agents.orders_done == 1, "alguém foi até lá e cavou")
	_check(mission.sim.kind_at(target.x, target.y) == Terrain.DIRT, "e o chão virou terra")
	_check(mission.agents.pending_orders() == 0, "a fila esvaziou")

	# A ordem vai pra quem chega mais rápido — medido em rota, não em linha reta.
	var second := _mission_at(0)
	var far: Vector2i = second.parsed.crew[0] + Vector2i(1, 0)
	second.order(Tools.DIG, far)
	second.update(STEP)
	var taker: int = second.agents.orders[0].taken_by if second.agents.orders.size() > 0 else -1
	_check(taker >= 0, "a ordem foi atribuída a alguém")

func _test_crew_retreats_from_heat() -> void:
	var mission := _mission_at(0)
	var person = mission.agents.crew[0]
	var here: Vector2i = person.cell()
	# Acende tudo em volta do brigadista: ele tem que largar o serviço e sair.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			mission.sim.ignite(here.x + dx, here.y + dy)
	for _i in 60:
		mission.update(STEP)
	_check(person.state == "retreating" or person.cell() != here,
		"com fogo em volta, o brigadista recua em vez de continuar cavando")
	_check(mission.agents.crew.size() == 3, "e ninguém some do jogo — recuar não é morrer")

func _test_unreachable_order_expires() -> void:
	# Uma ordem numa ilha cercada de fogo vira zumbi: o brigadista tenta, não
	# acha rota, larga, tenta de novo — parado, pra sempre. Ela precisa expirar
	# e devolver o recurso, o que também avisa o jogador de que ali não dá.
	var mission := _mission_at(0)
	var island := Vector2i(mission.sim.cols - 3, 2)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			mission.sim.ignite(island.x + dx, island.y + dy)
	mission.nav.rebuild()
	_check(mission.order(Tools.DIG, island), "a ordem entrou")
	var elapsed := 0.0
	while elapsed < Agents.ORDER_TIMEOUT + 4.0 and mission.agents.pending_orders() > 0:
		mission.update(STEP)
		elapsed += STEP
	_check(mission.agents.pending_orders() == 0, "a ordem inalcançável foi cancelada sozinha")

func _test_civilian_awareness() -> void:
	var mission := _mission_at(3)
	var civil = mission.agents.civilians[0]
	_check(not civil.aware, "o morador começa sem saber do incêndio")
	_check(civil.state == "calm", "e portanto parado em casa")

	mission.update(STEP)
	var start: Vector2 = civil.pos
	for _i in 30:
		mission.update(STEP)
	_check(civil.pos.distance_to(start) < 4.0, "longe do fogo, ele não sai correndo à toa")

	var here: Vector2i = civil.cell()
	mission.sim.ignite(here.x + 2, here.y)
	for _i in 40:
		mission.update(STEP)
	_check(civil.aware, "com fogo por perto, ele percebe")
	_check(civil.state == "fleeing" or civil.state == "panic" or civil.state == "safe", "e reage")

func _test_civilian_lost_in_fire() -> void:
	var mission := _mission_at(3)
	var civil = mission.agents.civilians[0]
	var here: Vector2i = civil.cell()
	mission.sim.ignite(here.x, here.y)
	# Atravessar uma célula acesa correndo tem que ser possível: a perda vem de
	# ficar dentro do fogo, não de encostar nele.
	mission.update(0.5)
	_check(civil.state != "lost", "meio segundo dentro do fogo não mata")
	for _i in int((Agents.LETHAL_TIME + 1.0) / STEP):
		mission.update(STEP)
	_check(mission.agents.lost_count >= 1 or civil.state != "calm", "ficar no fogo tem consequência")

func _test_crew_calms_panic() -> void:
	var mission := _mission_at(3)
	var civil = mission.agents.civilians[0]
	civil.aware = true
	civil.state = "panic"
	civil.panic_left = Agents.PANIC_TIME
	var person = mission.agents.crew[0]
	person.pos = civil.pos + Vector2(16, 0)
	mission.update(STEP)
	_check(civil.state == "fleeing", "brigadista do lado tira a pessoa do pânico")

# ---- missão ----

func _test_mission_budget() -> void:
	var mission := _mission_at(3)
	var water := mission.water_left
	_check(water > 0, "a fase tem baldes")
	var cell: Vector2i = mission.parsed.crew[0] + Vector2i(2, 0)
	_check(mission.order(Tools.WATER, cell), "pediu água")
	_check(mission.water_left == water - 1, "o balde foi debitado ao PEDIR, não ao usar")
	_check(mission.cancel(cell), "cancelou")
	_check(mission.water_left == water, "e o balde voltou")

	# Sem orçamento, a ordem tem que ser recusada — e recusada ANTES de mandar
	# alguém andar até lá.
	mission.water_left = 0
	_check(not mission.order(Tools.WATER, cell), "sem balde, não se pede água")
	_check(mission.agents.pending_orders() == 0, "e ninguém saiu andando à toa")
	_check(mission.remaining(Tools.DIG) == -1, "aceiro não tem conta")

func _test_mission_defeat_is_immediate() -> void:
	var mission := _mission_at(0)
	var goal := mission.goal_houses()
	var total := mission.sim.houses_total()
	_check(goal == total, "a fase 1 pede todas as casas")

	# Derruba uma casa: a fase tem que acabar no mesmo passo, não dois minutos
	# depois, quando o fogo finalmente se apagar sozinho.
	for y in mission.sim.rows:
		for x in mission.sim.cols:
			if mission.sim.kind_at(x, y) == Terrain.HOUSE:
				var idx := mission.sim.index_of(x, y)
				mission.sim.state[idx] = FireSim.BURNT
				mission.sim.houses_lost += 1
				break
		if mission.sim.houses_standing() < total:
			break
	mission.update(STEP)
	_check(mission.phase == Mission.LOST, "perder uma casa a mais que a meta encerra a fase")
	_check(mission.outcome != "", "e o jogo diz por quê")
	_check(not mission.order(Tools.DIG, Vector2i(5, 5)), "depois de acabar não se dão mais ordens")

func _test_mission_stars() -> void:
	var mission := _mission_at(0)
	_check(mission.stars() == 0, "fase em andamento não vale estrela")
	mission.phase = Mission.WON
	mission.elapsed = 10.0
	_check(mission.stars() == 3, "vencer com tudo de pé e rápido vale três")
	mission.elapsed = 9999.0
	_check(mission.stars() == 2, "devagar perde a terceira")
	# Derruba uma casa e a segunda estrela some junto.
	for idx in mission.sim.kind.size():
		if mission.sim.kind[idx] == Terrain.HOUSE:
			mission.sim.state[idx] = FireSim.BURNT
			break
	_check(mission.stars() == 1, "com casa perdida sobra uma")

func _test_progress_roundtrip() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase(Mission.SAVE_KEY)
	save_system.save_data()

	var fresh := Mission.load_progress(save_system)
	_check(int(fresh["unlocked"]) == 1, "começa com uma fase liberada")

	var mission := _mission_at(0)
	mission.phase = Mission.WON
	mission.elapsed = 100.0
	var progress := Mission.record(save_system, 0, mission.summary())
	_check(int(progress["unlocked"]) == 2, "vencer libera a próxima")
	_check(int(progress["levels"]["garganta"]["stars"]) == 3, "guardou as estrelas")

	# Rejogar pior não pode apagar o melhor resultado.
	mission.elapsed = 9999.0
	progress = Mission.record(save_system, 0, mission.summary())
	_check(int(progress["levels"]["garganta"]["stars"]) == 3, "o recorde de estrelas fica")
	_near(float(progress["levels"]["garganta"]["time"]), 100.0, 0.5, "o melhor tempo fica")

	var reloaded := Mission.load_progress(save_system)
	_check(int(reloaded["unlocked"]) == 2, "e sobrevive a recarregar")
	save_system.data.erase(Mission.SAVE_KEY)
	save_system.save_data()

# ---- level design ----

func _play_level(index: int, use_bot: bool, limit: float = 900.0) -> Mission:
	var mission := Mission.new()
	mission.start(index)
	var bot := ContainmentBot.new()
	bot.setup(mission)
	var t := 0.0
	while mission.phase == Mission.PLAYING and t < limit:
		if use_bot:
			bot.update(STEP)
		mission.update(STEP)
		t += STEP
	return mission

# A regressão de level design, herdada do `DemoBot` do Projeto 3: o bot é burro
# de propósito (cerca casa com terra, sem ler vento nem usar contra-fogo) e
# mesmo assim precisa passar em todas. Se ele parar de passar, alguma constante
# do fogo mudou e as seis fases precisam ser reequilibradas.
func _test_bot_wins_every_level() -> void:
	for i in Levels.count():
		var mission := _play_level(i, true)
		var summary := mission.summary()
		_check(mission.phase == Mission.WON,
			"fase %d (%s): o bot vence — %s, casas %d/%d, gente %d/%d" % [
				i + 1, mission.level["id"], mission.outcome,
				summary["houses"], summary["houses_total"], summary["saved"], summary["civilians"]])

# O outro lado da moeda, e o mais fácil de esquecer: uma fase que se resolve
# sozinha passa despercebida porque o bot também "vence" nela. A "encosta"
# nasceu assim — o povoado já vinha cercado de terra batida no ASCII e nenhum
# incêndio o alcançava.
func _test_doing_nothing_loses_every_level() -> void:
	for i in Levels.count():
		var mission := _play_level(i, false)
		_check(mission.phase == Mission.LOST,
			"fase %d (%s): sem fazer nada, perde-se (deu %s)" % [
				i + 1, mission.level["id"],
				"vitória" if mission.phase == Mission.WON else "tempo esgotado"])

# ---- cena ----

func _boot_scene() -> Node:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase(Mission.SAVE_KEY)
	save_system.save_data()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	return instance

func _test_scene_boots() -> void:
	var scene = await _boot_scene()
	_check(scene.mission != null, "a cena monta uma partida")
	_check(scene.machine != null, "e a máquina de telas existe")
	_check(scene.machine.current_state != null, "com um estado ativo")
	_check(scene.screen == "briefing", "que começa no briefing")
	_check(scene._bodies.size() == scene.mission.agents.crew.size() + scene.mission.agents.civilians.size(),
		"cada pessoa tem o corpo assado uma vez")

	# O briefing segura o relógio: o incêndio não anda antes de o jogador ver
	# as regras da fase.
	var burnt_before: int = scene.mission.sim.cells_burnt
	for _i in 10:
		await process_frame
	_check(scene.mission.sim.cells_burnt == burnt_before, "no briefing o fogo não anda")

	scene.machine.transition_to("playing")
	_check(scene.screen == "playing", "e depois começa")
	scene.queue_free()
	await process_frame

func _test_scene_click_orders() -> void:
	var scene = await _boot_scene()
	scene.machine.transition_to("playing")
	var cell: Vector2i = scene.mission.parsed.crew[0] + Vector2i(2, 0)
	# Converte a célula em pixel de tela pelo mesmo caminho que o jogo usa, e
	# clica. É o que garante que o clique cai onde o jogador está vendo.
	var at: Vector2 = Layout.cell_center(cell) + scene._world_offset()
	_check(scene._cell_under(at) == cell, "a conta de tela→célula fecha")

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	scene.handle_play_input(event)
	_check(scene.mission.agents.pending_orders() == 1, "clicar no vale dá uma ordem")

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = at
	scene.handle_play_input(right)
	_check(scene.mission.agents.pending_orders() == 0, "botão direito cancela")
	scene.queue_free()
	await process_frame

# Um clique num botão da barra lateral não pode ATRAVESSAR e cavar o vale que
# está desenhado atrás dela.
func _test_scene_hud_does_not_dig() -> void:
	var scene = await _boot_scene()
	scene.machine.transition_to("playing")
	var on_button: Vector2 = scene._tool_button_rect(1).get_center()
	_check(scene._cell_under(on_button) == Vector2i(-1, -1), "sobre o HUD não há célula")

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = on_button
	scene.handle_play_input(event)
	_check(scene.mission.agents.pending_orders() == 0, "clicar no botão não cava nada")
	_check(scene.tool_id == Tools.WATER, "mas troca a ferramenta")
	scene.queue_free()
	await process_frame

func _test_scene_shortcuts() -> void:
	var scene = await _boot_scene()
	scene.machine.transition_to("playing")

	_check(scene.tool_id == Tools.DIG, "começa no aceiro")
	scene.handle_play_input(_key(KEY_3))
	_check(scene.tool_id == Tools.BACKFIRE, "tecla 3 escolhe contra-fogo")
	scene.handle_play_input(_key(KEY_TAB))
	_check(scene.show_risk, "TAB liga a previsão")
	scene.handle_play_input(_key(KEY_TAB))
	_check(not scene.show_risk, "e desliga")

	var speed: float = scene.mission.speed()
	scene.handle_play_input(_key(KEY_F))
	_check(scene.mission.speed() > speed, "F acelera o tempo")
	scene.handle_play_input(_key(KEY_B))
	_check(scene.bot_active, "B liga a demonstração")
	scene.queue_free()
	await process_frame

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _test_scene_camera_limits() -> void:
	var scene = await _boot_scene()
	scene.machine.transition_to("playing")
	scene.camera = Vector2(-9999, -9999)
	scene._clamp_camera()
	_check(scene.camera.x >= 0.0 and scene.camera.y >= 0.0, "a câmera não sai pela esquerda/topo")
	scene.camera = Vector2(9999, 9999)
	scene._clamp_camera()
	var limit := Layout.camera_limit(scene.mission.sim.cols, scene.mission.sim.rows)
	_check(scene.camera.x <= limit.x + 0.1 and scene.camera.y <= limit.y + 0.1,
		"nem pela direita/base")

	# O minimapa é navegação: clicar nele leva a câmera pra lá.
	var mini: Rect2 = scene._minimap_rect()
	scene._click_hud(mini.position + mini.size * 0.75)
	_check(scene.camera.x >= 0.0, "clicar no minimapa move a câmera pra dentro do vale")
	scene.queue_free()
	await process_frame
