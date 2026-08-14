extends Node2D

# Agência de jogador: até aqui (fases 0-7 + Mina/Forja + Fazenda +
# desbloqueio por nível + Roda D'Água/Moinho de Vento) o jogo inteiro rodava
# SOZINHO — todo prédio nascia automático (por nível, não mais tudo de uma
# vez, mas ainda sem decisão nenhuma do jogador). João abriu o jogo pra
# jogar, viu a vila crescendo por conta própria e pediu um menu de
# construção de verdade: ele escolhe O QUE construir e QUANDO, pagando um
# custo em recurso acumulado (ver `Buildings.BUILD_COST`), e ONDE colocar,
# clicando no mapa. Isso substitui o desbloqueio automático por nível — o
# sistema de tiers (`_unlock_building_tier`/`_place_tier2..5_buildings`) foi
# removido, mas a lógica de "onde é um lugar válido pra esse tipo de
# prédio" (perto de depósito, perto de água, terreno alto) sobreviveu quase
# inteira, só migrou de "escolhida automaticamente" pra "validada contra o
# clique do jogador" — ver `_can_place_kind_at`.
#
# Progression (progression.gd) continua existindo, mas só pro que já fazia
# antes do sistema de tiers: alcance de exploração por XP acumulado. Não
# gate mais nenhum prédio.
#
# Armazém, Fazenda e uma Casa continuam nascendo automáticos (ver
# `_place_starting_buildings`) — é o piso de sobrevivência garantido, sem
# ele o jogador começaria sem comida e sem WORKAROUND possível (nenhum
# recurso no Armazém pra pagar o primeiro prédio de qualquer forma).
#
# Tudo daqui pra baixo é histórico das fases anteriores, sem mudança de
# arquitetura — ver a quebra completa em docs/plano-projeto7-reino.md:
#
# Fase 6 — população: até a Fase 5, todo trabalhador e o carregador
# nasciam prontos no primeiro frame. Agora existe uma `Population` que
# cresce devagar até a capacidade habitacional (soma das Casas), e
# prédios/carregador entram numa fila preenchida conforme gente disponível.
#
# Fase 5 — energia: o Gerador a Lenha queima madeira do Armazém e cobre um
# raio em células — todo prédio de extração/processamento dentro do raio
# produz mesmo SEM trabalhador, desde que o gerador tenha combustível.
# "Energia OU trabalhador", não "e" — a Oficina de Pedra nasce sem
# trabalhador de propósito pra provar que o raio sozinho basta.
#
# Fase 4 — processamento: Serraria e Oficina de Pedra transformam bruto do
# Armazém em processado (tábua/bloco), 1:1, throttladas pelo estoque de
# insumo disponível — leem/escrevem direto em `stock`, sem pátio próprio.
#
# Fase 3 — transporte: a produção do extrator vira PÁTIO
# (`Building.buffer`), e um NPC carregador leva até o Armazém pra virar
# estoque jogável (`Buildings.stock`). Um extrator com o pátio cheio para de
# extrair sozinho até alguém vir buscar.
#
# Fase 2 — Posto de Lenhador e Pedreira, um trabalhador por prédio, andando
# até o posto pelo Pathfinder antes de produzir.

const TILE_SIZE := 16
const DISPLAY_SCALE := 2
const CELL := TILE_SIZE * DISPLAY_SCALE

const MAP_COLS := 60
const MAP_ROWS := 40
const MAP_SEED := 20260810

const TOWN_PATH := "res://assets/town/tilemap_packed.png"
const DUNGEON_PATH := "res://assets/dungeon/tilemap_packed.png"

# --- tiles do Kenney Tiny Town (conferidos em 06-jogo-incendio/scenes/main.gd) ---
const T_GRASS := Vector2i(0, 0)
const T_DIRT := Vector2i(1, 2)
const T_TREE := Vector2i(4, 2)
# --- tile do Kenney Tiny Dungeon (conferido em 02-jogo-roguelike/scenes/main.gd) ---
const T_ROCK := Vector2i(0, 3)
const ALT_ORE := 1
const COLOR_ORE := Color("e8a33d")

const PAN_SPEED := 640.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 1.1
const SCOUT_RADIUS := 6.0

const C_FOG_UNSEEN := Color(0.0, 0.0, 0.0, 0.93)
const C_FOG_EXPLORED := Color(0.0, 0.0, 0.0, 0.45)

# --- lagos (ver comentário no topo do arquivo) ---
# Fração mais baixa do relevo que vira "leito de lago em potencial", e quanto
# semear em cada célula candidata. Medidos rodando o autômato de verdade e
# contando célula molhada no fim, não chutados: a primeira tentativa (22% do
# relevo, 3 unidades por célula) parecia razoável olhando só a CONTAGEM DE
# SEMENTES, mas depois de acomodar o autômato espalhava a água até 29% do
# mapa — inundação, não lago. 6%/1,2 acomoda em ~4% do mapa (algumas lagoas
# distintas), que é a leitura visual que "lago" pede.
const LAKE_HEIGHT_FRACTION := 0.06
const LAKE_SEED_AMOUNT := 1.2
# Só em grama: semear em cima de floresta/pedra/colina desenharia árvore ou
# pedra boiando na água — os dois sistemas ainda não conversam sobre isso, e
# não é o que esta fase promete resolver.
#
# O acomodamento converge rápido (a diferença de superfície cai pela metade a
# cada tick, ver water_sim.gd) — medido parando de mudar por volta do tick 50
# neste mapa; 150 sobra de margem sem custar o segundo e meio que 600 custava
# no carregamento da cena.
const LAKE_SETTLE_TICKS := 150
const C_WATER_DEEP := Color("2a5f8a")
const C_WATER_SHALLOW := Color("5b9bd1")
const WATER_VISIBLE_MIN := 0.05
const WATER_DEPTH_REFERENCE := 2.0   # água nesse volume (ou mais) já desenha na cor mais funda

# --- Fase 2: prédio + trabalhador ---
const BUILDING_SEARCH_RADIUS := 20   # em células, a partir da vila
const CHAR_TEXTURE_PATH := "res://assets/characters/roguelikeChar_transparent.png"
const CHAR_TILE := 16
const CHAR_MARGIN := 1
# Um rosto por trabalhador, não clone — mesmo elenco do 05-jogo-colonia
# (scenes/main.gd CHAR_CAST), só os dois primeiros: agora são dois NPCs, um
# por prédio.
const CHAR_CAST := [Vector2i(0, 5), Vector2i(1, 5)]
const WORKER_SCALE := 2.0
# A Pedreira nasce EM CIMA de uma célula de pedra (ver
# Buildings.nearest_deposit_cell) — um marcador em tom de pedra ficava quase
# indistinguível do próprio depósito por baixo dele (achado revisando a Fase
# 2: dava pra confundir "tem uma Pedreira ali" com "é só mais pedra"). Por
# isso a cor da Pedreira é terracota, não cinza — precisa contrastar com o
# chão que ela ocupa, não combinar com ele. `C_BUILDING_OUTLINE` reforça isso
# de forma genérica: toda construção ganha uma borda escura, então nenhuma
# combinação futura de cor-de-prédio × cor-de-terreno pode repetir o mesmo
# problema sem alguém precisar lembrar da regra.
const C_BUILDING := {
	Buildings.Kind.LUMBERJACK: Color("8a5a34"),
	Buildings.Kind.QUARRY: Color("b5493a"),
	Buildings.Kind.WAREHOUSE: Color("d8c9a3"),
	Buildings.Kind.SAWMILL: Color("d1a63e"),
	Buildings.Kind.STONE_WORKSHOP: Color("6b7280"),
	Buildings.Kind.GENERATOR: Color("4a6b3a"),
	Buildings.Kind.HOUSE: Color("6a8caf"),
	# Mina senta em cima do depósito de minério, que já é laranja (ver
	# COLOR_ORE) sobre chão de terra batida — cor fria de propósito, pra não
	# repetir a camuflagem da Pedreira na Fase 2 (marcador quente demais em
	# cima de chão quente).
	Buildings.Kind.MINE: Color("4a4a5c"),
	Buildings.Kind.FORGE: Color("d9622c"),
	# Fazenda nasce em grama (mesmo chão verde da Serraria/Oficina de Pedra
	# vizinhas) — um marcador verde ali repetiria a mesma camuflagem da
	# Pedreira na Fase 2, e um dourado ficaria perto demais do amarelo da
	# Serraria (d1a63e). Framboesa contrasta com o verde do chão E com todo
	# o resto da paleta de prédios já em uso.
	Buildings.Kind.FARM: Color("c9518f"),
	# Roda D'Água nasce perto de água de verdade (chão azul do WaterSim bem
	# ao lado) — turquesa fica claramente diferente tanto do azul da água
	# quanto do azul-acinzentado já usado pela Casa.
	Buildings.Kind.WATERWHEEL: Color("45b8ac"),
	# Moinho de Vento nasce em terreno elevado (grama alta, ainda verde) —
	# tom claro e frio contrasta com o verde sem repetir o creme do Armazém.
	Buildings.Kind.WINDMILL: Color("cfd8e3"),
}
const C_BUILDING_ROOF := {
	Buildings.Kind.LUMBERJACK: Color("5c3a20"),
	Buildings.Kind.QUARRY: Color("7a2f26"),
	Buildings.Kind.WAREHOUSE: Color("8a7c5c"),
	Buildings.Kind.SAWMILL: Color("8f6f2c"),
	Buildings.Kind.STONE_WORKSHOP: Color("454a54"),
	Buildings.Kind.GENERATOR: Color("2e4526"),
	Buildings.Kind.HOUSE: Color("41597a"),
	Buildings.Kind.MINE: Color("2e2e3a"),
	Buildings.Kind.FORGE: Color("8a3d16"),
	Buildings.Kind.FARM: Color("7a2f52"),
	Buildings.Kind.WATERWHEEL: Color("2a6e66"),
	Buildings.Kind.WINDMILL: Color("8b96a3"),
}
const C_BUILDING_OUTLINE := Color("1a1410")
const STATE_COLORS := {
	Worker.State.IDLE: Color("cfcfcf"),
	Worker.State.WALKING: Color("9fd0ff"),
	Worker.State.WORKING: Color("ffd166"),
}

# --- Fase 3: armazém + carregador ---
# Terceiro rosto do elenco (ver CHAR_CAST acima) — o carregador precisa ser
# visualmente distinto dos trabalhadores de posto, senão "quem está indo
# entregar" e "quem está indo trabalhar" viram a mesma pergunta.
const CARRIER_CHAR_COORD := Vector2i(0, 6)
const C_CARGO := {
	"madeira": Color("b98a4e"),
	"pedra": Color("a8a8b4"),
	"minério": Color("8a7fa0"),
	"comida": Color("c9518f"),
}

var map := MapGen.new()
var fog := Fog.new()
var water_sim := WaterSim.new()
var pathfinder := Pathfinder.new()
var buildings := Buildings.new()
var workers := Workers.new()
var carriers := Carriers.new()
var population := Population.new()
var progression := Progression.new()
var _last_total_stock := 0.0
var _is_starving := false   # lido pelo HUD — true no frame em que a comida disponível não cobriu o consumo
var _village_cell: Vector2i
var _pending_jobs: Array = []   # ids de Buildings.list esperando trabalhador, -1 = sentinela do carregador
var _jobs_registered_up_to := 0 # índice em buildings.list já considerado pra _pending_jobs
var _nodes_built_up_to := 0     # índice em buildings.list já com Node2D criado
var _placing_kind := -1         # -1 = não está no modo de construção agora
var camera: Camera2D
var _fog_layer: Node2D
var _water_layer: Node2D
var _ghost: ColorRect
var _buildings_root: Node2D
var _workers_root: Node2D
var _carriers_root: Node2D
var _worker_nodes: Dictionary = {}   # Worker.id -> Node2D
var _carrier_nodes: Dictionary = {}  # Carrier.id -> Node2D
var _building_nodes: Dictionary = {} # Buildings.Building -> Node2D
var _vision_sources: Array = []
var _stock_label: Label
var _build_status_label: Label
var _build_buttons: Dictionary = {}   # Buildings.Kind -> Button

var _town_source_id := -1
var _dungeon_source_id := -1
var _char_texture: Texture2D
var _state_dot_texture: Texture2D

func _ready() -> void:
	_char_texture = load(CHAR_TEXTURE_PATH)
	_state_dot_texture = _build_state_dot()

	map.generate(MAP_COLS, MAP_ROWS, MAP_SEED)
	fog.setup(MAP_COLS, MAP_ROWS)
	_seed_lakes()

	_village_cell = Vector2i(MAP_COLS / 2, MAP_ROWS / 2)
	pathfinder.setup(MAP_COLS, MAP_ROWS, CELL)
	_place_starting_buildings(_village_cell)
	pathfinder.rebuild(_solid_cells())

	_build_world()
	_build_hud()

	# Um trabalhador por prédio: a Fase 2 nasceu com "um trabalhador único" no
	# escopo, mas isso deixava metade dos extratores plantados no mapa sem
	# nunca produzir nada — pra quem está jogando, prédio parado e prédio
	# inexistente parecem a mesma coisa. Continua sendo "um trabalhador por
	# posto", não staffing fracionário: isso só passaria a valer a pena com
	# múltiplas vagas por prédio (ver o comentário em buildings.gd).
	#
	# Exceções deliberadas: o Armazém e as três fontes de energia (Gerador,
	# Roda D'Água, Moinho de Vento) nunca têm trabalhador — são
	# infraestrutura passiva, não produção. E a Oficina de
	# Pedra, apesar de PODER ter trabalhador, nasce sem nenhum de propósito:
	# é o jeito mais direto de mostrar "energia OU trabalhador" de verdade —
	# ela só produz porque está no raio de uma fonte de energia, não por
	# acaso ter os dois. Posto de Lenhador, Pedreira e Serraria continuam
	# com trabalhador como sempre.
	#
	# A partir da Fase 6, "precisa de trabalhador" não é mais "nasce com um
	# trabalhador": os prédios entram numa FILA (`_pending_jobs`), e quem
	# preenche a fila é `_fill_jobs()` em `_process()`, conforme a população
	# cresce (`Population`) até a capacidade das Casas. Sem isso, mão de obra
	# continuaria sendo infinita e instantânea, e Casa não teria propósito
	# nenhum no jogo.
	#
	# A Fazenda é o único prédio staffável que nasce automático (ver
	# `_place_starting_buildings`), então `_register_pending_jobs()` já a
	# coloca sozinha na fila — só falta o carregador (sentinela -1, ver
	# `_fill_jobs`) logo atrás dela. Essa ordem importa de verdade:
	# `Population.BOOTSTRAP_POPULATION` (2) é exatamente gente o bastante pra
	# cobrir os dois, e são os dois que fecham o ciclo "produzir comida →
	# virar estoque de verdade" que desbloqueia crescimento além do piso de
	# arranque (ver population.gd). Se algum prédio de nível mais alto
	# entrasse antes, os dois trabalhadores de graça do piso iriam pra lá, a
	# Fazenda nunca ganharia gente, e a vila travaria em 2 de população pra
	# sempre — foi exatamente o que a suíte de testes pegou na primeira
	# versão desta mudança.
	_register_pending_jobs()
	_pending_jobs.append(-1)   # sentinela: carregador

	_vision_sources.append(Vector3(_village_cell.x, _village_cell.y, progression.reveal_radius()))
	fog.update_visibility(_vision_sources)
	_fog_layer.queue_redraw()

	camera.position = Vector2(_village_cell) * CELL

# Preenche vagas (prédio esperando trabalhador, ou o carregador — sentinela
# -1) uma a uma, só enquanto a população tiver gente disponível
# (`Population.available()`). Ordem da fila = prioridade: Fazenda e
# carregador primeiro (ver o comentário em `_ready()` sobre por que — é o
# que evita a vila travar no piso de população sem comida), depois os
# extratores, e Serraria/Forja por último (dependem da produção dos outros
# chegar no Armazém primeiro).
func _fill_jobs() -> void:
	while not _pending_jobs.is_empty() and population.available() > 0:
		var building_id: int = _pending_jobs.pop_front()
		population.employ()
		if building_id == -1:
			var carrier := carriers.spawn(Vector2(_village_cell) * CELL)
			_spawn_carrier_node(carrier)
			continue
		var building := buildings.list[building_id]
		var worker := workers.spawn(Vector2(_village_cell) * CELL)
		buildings.assign(building_id, worker)
		workers.send_to(worker, _work_spot_for(building), pathfinder)
		_spawn_worker_node(worker)

# Só o essencial pra sobreviver — o Armazém (é a própria vila), a Fazenda
# (sem comida a população nunca sai do piso de arranque, ver population.gd)
# e UMA Casa (capacidade 3, cobre Fazenda + carregador com folga). Todo o
# resto do catálogo (extratores, processadores, energia, mais Casas) é
# escolha do jogador via menu de construção — ver `_can_place_kind_at`/
# `_build` mais abaixo.
func _place_starting_buildings(start: Vector2i) -> void:
	buildings.place(Buildings.Kind.WAREHOUSE, start)
	var occupied := _occupied_cells()
	var farm_cell := _free_cell_near(start, Vector2i(2, 2), occupied)
	buildings.place(Buildings.Kind.FARM, farm_cell)
	occupied[farm_cell] = true
	var house_cell := _free_cell_near(start, Vector2i(2, 0), occupied)
	buildings.place(Buildings.Kind.HOUSE, house_cell)

# ---- menu de construção (agência do jogador) ----

# Ordem de exibição no painel — o Armazém fica de fora (nasce fixo com a
# vila, nunca é escolha do jogador).
const BUILDABLE_KINDS := [
	Buildings.Kind.HOUSE, Buildings.Kind.LUMBERJACK, Buildings.Kind.QUARRY, Buildings.Kind.FARM,
	Buildings.Kind.MINE, Buildings.Kind.SAWMILL, Buildings.Kind.STONE_WORKSHOP,
	Buildings.Kind.GENERATOR, Buildings.Kind.FORGE, Buildings.Kind.WATERWHEEL, Buildings.Kind.WINDMILL,
]
const BUILDING_NAME := {
	Buildings.Kind.HOUSE: "Casa",
	Buildings.Kind.LUMBERJACK: "Posto de Lenhador",
	Buildings.Kind.QUARRY: "Pedreira",
	Buildings.Kind.FARM: "Fazenda",
	Buildings.Kind.MINE: "Mina",
	Buildings.Kind.SAWMILL: "Serraria",
	Buildings.Kind.STONE_WORKSHOP: "Oficina de Pedra",
	Buildings.Kind.GENERATOR: "Gerador a Lenha",
	Buildings.Kind.FORGE: "Forja",
	Buildings.Kind.WATERWHEEL: "Roda D'Água",
	Buildings.Kind.WINDMILL: "Moinho de Vento",
}

# Profundidade mínima de água numa célula vizinha pra contar como "rio/lago
# ao lado" — bem acima do limiar visual de desenho (`WATER_VISIBLE_MIN`),
# pra não deixar construir Roda D'Água ao lado de uma poça residual quase
# seca.
const WATERWHEEL_MIN_ADJACENT_WATER := 0.2
# Mesmo limiar de altura que decide onde nasce colina (`MapGen.HILLS_HEIGHT`)
# NÃO serve aqui: qualquer célula acima dele já virou Kind.HILLS, nunca
# GRASS. "Elevado o bastante pra vento, mas ainda não é colina" pede um
# limiar mais baixo — medido rodando o mapa de verdade (a maioria da grama
# fica entre 2 e 4 de altura, ver map_gen.gd): 3.0 acha terreno genuinamente
# alto sem ficar tão raro que o Moinho quase nunca dê pra construir.
const WINDMILL_MIN_HEIGHT := 3.0

func _has_adjacent_water(cell: Vector2i) -> bool:
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for offset in offsets:
		var n: Vector2i = cell + offset
		if map.inside(n.x, n.y) and water_sim.water_at(n.x, n.y) >= WATERWHEEL_MIN_ADJACENT_WATER:
			return true
	return false

# Regra de posição por tipo — a mesma lógica que antes decidia sozinha ONDE
# plantar cada prédio (depósito certo, água do lado, terreno alto) agora só
# VALIDA a célula que o jogador clicou. Não checa custo nem se a célula já
# está ocupada — isso é `_build()`.
func _can_place_kind_at(kind: int, cell: Vector2i) -> bool:
	if not map.inside(cell.x, cell.y):
		return false
	if not fog.is_explored(cell.x, cell.y):
		return false
	match kind:
		Buildings.Kind.LUMBERJACK:
			return map.kind_at(cell.x, cell.y) == MapGen.Kind.FOREST
		Buildings.Kind.QUARRY:
			return map.kind_at(cell.x, cell.y) == MapGen.Kind.STONE
		Buildings.Kind.MINE:
			return map.kind_at(cell.x, cell.y) == MapGen.Kind.HILLS
		Buildings.Kind.WATERWHEEL:
			return map.kind_at(cell.x, cell.y) == MapGen.Kind.GRASS and _has_adjacent_water(cell)
		Buildings.Kind.WINDMILL:
			return map.kind_at(cell.x, cell.y) == MapGen.Kind.GRASS and map.height_at(cell.x, cell.y) >= WINDMILL_MIN_HEIGHT
		_:
			return map.kind_at(cell.x, cell.y) == MapGen.Kind.GRASS

# Tenta construir `kind` em `cell`: precisa passar em `_can_place_kind_at` E
# a célula não pode já ter outro prédio E o Armazém precisa ter estoque
# pro custo (`Buildings.BUILD_COST`). Devolve false sem mudar nada se
# qualquer uma falhar — quem chama (o clique do jogador, ou um teste) decide
# o que fazer com isso. Sucesso paga o custo, planta o prédio, atualiza
# pathfinder/fila de trabalho/nó da cena — os mesmos passos que antes
# aconteciam automático a cada nível, agora disparados por uma decisão.
func _build(kind: int, cell: Vector2i) -> bool:
	if _occupied_cells().has(cell):
		return false
	if not _can_place_kind_at(kind, cell):
		return false
	if not buildings.can_afford(kind):
		return false
	buildings.pay_cost(kind)
	buildings.place(kind, cell)
	pathfinder.rebuild(_solid_cells())
	_register_pending_jobs()
	_sync_new_building_nodes()
	return true

func _occupied_cells() -> Dictionary:
	var occupied := {}
	for building in buildings.list:
		occupied[building.cell] = true
	return occupied

func _solid_cells() -> Array:
	var solids: Array = []
	for building in buildings.list:
		solids.append(building.cell)
	return solids

# Chamada uma vez por prédio novo (inicial ou construído pelo jogador
# depois) — separa "quem precisa de trabalhador" de "quem é infraestrutura
# passiva", mesma regra desde a Fase 5/6. Usa `_jobs_registered_up_to` pra
# nunca reconsiderar um prédio já enfileirado, já que `buildings.list` só
# cresce (nunca reordena nem remove).
func _register_pending_jobs() -> void:
	while _jobs_registered_up_to < buildings.list.size():
		var i := _jobs_registered_up_to
		_jobs_registered_up_to += 1
		var building := buildings.list[i]
		if building.kind == Buildings.Kind.WAREHOUSE or building.kind == Buildings.Kind.GENERATOR:
			continue
		if building.kind == Buildings.Kind.HOUSE or building.kind == Buildings.Kind.STONE_WORKSHOP:
			continue
		if building.kind == Buildings.Kind.WATERWHEEL or building.kind == Buildings.Kind.WINDMILL:
			continue
		_pending_jobs.append(i)

# Busca em anéis crescentes a partir de `start + offset` — mesma técnica de
# `Buildings.nearest_deposit_cell`, mas contra um conjunto de células já
# ocupadas em vez de um tipo de depósito. Só usado pra prédios que não têm
# depósito próprio (Serraria, Oficina de Pedra).
func _free_cell_near(start: Vector2i, offset: Vector2i, occupied: Dictionary) -> Vector2i:
	var candidate := start + offset
	if map.inside(candidate.x, candidate.y) and not occupied.has(candidate):
		return candidate
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var probe := candidate + Vector2i(dx, dy)
				if map.inside(probe.x, probe.y) and not occupied.has(probe):
					return probe
	return candidate

# Onde o trabalhador para: DUAS células abaixo do prédio, não em cima nem
# colado nele — o prédio é sólido no pathfinder (ninguém anda por cima), e
# o corpo do trabalhador é mais alto que uma célula (ancorado pelos pés,
# ver _spawn_worker_node), então parar na célula logo abaixo ainda tampava o
# prédio quase inteiro atrás da cabeça.
func _work_spot_for(building: Buildings.Building) -> Vector2:
	var cell := building.cell + Vector2i(0, 2)
	if not map.inside(cell.x, cell.y) or pathfinder.is_solid(cell):
		cell = building.cell + Vector2i(0, -2)
	return Vector2(cell) * CELL + Vector2(CELL, CELL) * 0.5

# Semeia água nas células mais baixas do relevo e deixa o WaterSim acomodar
# ANTES do primeiro frame — os lagos já nascem em equilíbrio, sem o jogador
# ver a água "se arrumando" na primeira tela.
func _seed_lakes() -> void:
	water_sim.setup(map.cols, map.rows, map.height)

	var lowest: float = map.height[0]
	var highest: float = map.height[0]
	for h in map.height:
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	var threshold: float = lowest + (highest - lowest) * LAKE_HEIGHT_FRACTION

	for y in map.rows:
		for x in map.cols:
			if map.kind_at(x, y) != MapGen.Kind.GRASS:
				continue
			if map.height_at(x, y) <= threshold:
				water_sim.add_water(x, y, LAKE_SEED_AMOUNT)

	for _i in LAKE_SETTLE_TICKS:
		water_sim.advance(WaterSim.TICK)

func _process(delta: float) -> void:
	map.advance(delta)
	var food_available: float = buildings.stock.get("comida", 0.0)
	# `food_needed` espelha o cálculo interno de `Population.advance` (mesma
	# fórmula, mesmo `count` pré-tick) só pra decidir o aviso de fome do HUD
	# sem a classe precisar expor um sinal próprio pra isso.
	var food_needed: float = population.count * Population.CONSUMPTION_PER_CAPITA * delta
	var food_consumed := population.advance(delta, buildings.housing_capacity(), food_available)
	buildings.stock["comida"] = food_available - food_consumed
	_is_starving = food_consumed < food_needed - 0.0001
	_fill_jobs()
	workers.advance(delta, pathfinder)
	buildings.advance(delta, map, workers)
	carriers.advance(delta, pathfinder, buildings)
	_advance_progression()
	pathfinder.decay(delta)
	_sync_building_nodes()
	_sync_worker_nodes()
	_sync_carrier_nodes()
	_update_hud()
	_update_ghost()
	_pan_with_keys(delta)

# XP é o total de recurso já entregue no Armazém — soma de todo `stock`,
# porque processamento (Fase 4) só CONVERTE 1:1 (madeira vira tábua sem
# mudar a soma), então normalmente o único jeito da soma total subir é o
# carregador entregar algo novo. Só "normalmente": o Gerador (Fase 5) BAIXA
# essa soma de verdade ao queimar madeira como combustível — por isso só
# somamos XP quando `gained` é positivo (`if gained > 0.0`), nunca descontamos
# quando é negativo. Isso significa `progression.xp` não é mais reconstruível
# a partir de `buildings.stock` sozinho (achado depurando esta fase: os dois
# pareciam dever bater e não batiam — o gerador consumindo combustível é a
# explicação, não um bug). Progresso é permanente de propósito: não faria
# sentido perder nível porque o Gerador gastou madeira depois.
func _advance_progression() -> void:
	var total := 0.0
	for amount in buildings.stock.values():
		total += amount
	var gained: float = total - _last_total_stock
	_last_total_stock = total
	if gained > 0.0:
		progression.add_xp(gained)

	var radius := progression.reveal_radius()
	if not _vision_sources.is_empty() and _vision_sources[0].z != radius:
		_vision_sources[0].z = radius
		fog.update_visibility(_vision_sources)
		_fog_layer.queue_redraw()

func _pan_with_keys(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if move != Vector2.ZERO:
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x
		# O clamp nativo do Camera2D (`limit_*`) só afeta a transformação de
		# desenho, não a propriedade `position` do nó — ela cresceria sem
		# limite enquanto a tecla ficasse segurada, e qualquer código que leia
		# `camera.position` (incluindo os testes headless) veria um valor
		# fora do mapa. Clampar aqui mantém `position` como a fonte da
		# verdade em vez de depender de um efeito colateral do renderizador.
		camera.position.x = clampf(camera.position.x, camera.limit_left, camera.limit_right)
		camera.position.y = clampf(camera.position.y, camera.limit_top, camera.limit_bottom)

# Clique esquerdo faz coisas diferentes dependendo do modo: fora do modo de
# construção, continua explorando a névoa (comportamento original desde a
# Fase 1). No modo de construção (`_placing_kind != -1`, ligado pelo botão
# do painel), o clique tenta construir ali — Esc ou botão direito cancelam
# sem gastar nada.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _placing_kind != -1:
		_cancel_placing()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _placing_kind != -1:
				_try_build_at_mouse()
			else:
				_scout_at(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT and _placing_kind != -1:
			_cancel_placing()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / ZOOM_STEP)

func _zoom_by(factor: float) -> void:
	var z: float = clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

func _cell_under_mouse() -> Vector2i:
	var world_pos := get_global_mouse_position()
	return Vector2i(floor(world_pos.x / CELL), floor(world_pos.y / CELL))

func _on_build_button_pressed(kind: int) -> void:
	if not buildings.can_afford(kind):
		return
	_placing_kind = kind
	_build_status_label.text = "Construindo %s — clique num local válido (Esc cancela)" % BUILDING_NAME[kind]

func _cancel_placing() -> void:
	_placing_kind = -1
	_build_status_label.text = ""

func _try_build_at_mouse() -> void:
	var kind := _placing_kind
	if _build(kind, _cell_under_mouse()):
		_cancel_placing()
	# Clique inválido (célula errada, sem estoque) não sai do modo — o
	# jogador tenta de novo sem precisar reabrir o painel. O quadrado
	# vermelho (`_update_ghost`) já avisa antes do clique.

# Quadrado colorido seguindo o mouse enquanto o jogador está escolhendo
# onde construir — verde numa célula válida, vermelho numa inválida. Sem
# isso, "clique num local válido" seria adivinhação.
func _update_ghost() -> void:
	if _placing_kind == -1:
		_ghost.visible = false
		return
	var cell := _cell_under_mouse()
	_ghost.visible = true
	_ghost.position = Vector2(cell) * CELL
	var valid := _can_place_kind_at(_placing_kind, cell) and not _occupied_cells().has(cell)
	_ghost.color = Color(0.3, 1.0, 0.3, 0.45) if valid else Color(1.0, 0.3, 0.3, 0.45)

# Clique no mapa simula um posto de observação/exploração: soma uma fonte de
# visão permanente naquele ponto. Não existe unidade se deslocando ainda (Fase
# 2+), então isto é o jeito mais simples de mostrar a névoa recuando de
# verdade nesta fase, sem inventar um sistema que a fase seguinte for jogar
# fora.
func _scout_at(world_pos: Vector2) -> void:
	var cell := Vector2i(floor(world_pos.x / CELL), floor(world_pos.y / CELL))
	if not map.inside(cell.x, cell.y):
		return
	_vision_sources.append(Vector3(cell.x, cell.y, SCOUT_RADIUS))
	fog.update_visibility(_vision_sources)
	_fog_layer.queue_redraw()

# ---- construção da cena ----

func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var town := TileSetAtlasSource.new()
	town.texture = load(TOWN_PATH)
	town.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for coord in [T_GRASS, T_DIRT, T_TREE]:
		if not town.has_tile(coord):
			town.create_tile(coord)
	_town_source_id = tile_set.add_source(town)

	var dungeon := TileSetAtlasSource.new()
	dungeon.texture = load(DUNGEON_PATH)
	dungeon.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	if not dungeon.has_tile(T_ROCK):
		dungeon.create_tile(T_ROCK)
	if dungeon.get_alternative_tiles_count(T_ROCK) <= ALT_ORE:
		dungeon.create_alternative_tile(T_ROCK, ALT_ORE)
	dungeon.get_tile_data(T_ROCK, ALT_ORE).modulate = COLOR_ORE
	_dungeon_source_id = tile_set.add_source(dungeon)

	return tile_set

func _build_world() -> void:
	var world := Node2D.new()
	world.name = "World"
	add_child(world)

	var tile_set := _build_tile_set()

	var ground := TileMapLayer.new()
	ground.name = "GroundLayer"
	ground.tile_set = tile_set
	ground.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(ground)

	var deposits := TileMapLayer.new()
	deposits.name = "DepositLayer"
	deposits.tile_set = tile_set
	deposits.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	deposits.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(deposits)

	for y in MAP_ROWS:
		for x in MAP_COLS:
			var pos := Vector2i(x, y)
			var k: int = map.kind_at(x, y)
			ground.set_cell(pos, _town_source_id, T_DIRT if k == MapGen.Kind.HILLS else T_GRASS)
			match k:
				MapGen.Kind.FOREST:
					deposits.set_cell(pos, _town_source_id, T_TREE)
				MapGen.Kind.STONE:
					deposits.set_cell(pos, _dungeon_source_id, T_ROCK, 0)
				MapGen.Kind.HILLS:
					deposits.set_cell(pos, _dungeon_source_id, T_ROCK, ALT_ORE)

	_water_layer = Node2D.new()
	_water_layer.name = "WaterLayer"
	_water_layer.draw.connect(_draw_water)
	world.add_child(_water_layer)
	_water_layer.queue_redraw()

	_buildings_root = Node2D.new()
	_buildings_root.name = "Buildings"
	world.add_child(_buildings_root)
	_sync_new_building_nodes()

	_workers_root = Node2D.new()
	_workers_root.name = "Workers"
	world.add_child(_workers_root)

	_carriers_root = Node2D.new()
	_carriers_root.name = "Carriers"
	world.add_child(_carriers_root)

	_fog_layer = Node2D.new()
	_fog_layer.name = "FogLayer"
	_fog_layer.draw.connect(_draw_fog)
	world.add_child(_fog_layer)

	# Quadrado-fantasma do modo de construção — nasce invisível, `_update_ghost`
	# liga/desliga e pinta verde/vermelho a cada frame.
	_ghost = ColorRect.new()
	_ghost.name = "Ghost"
	_ghost.size = Vector2(CELL, CELL)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	world.add_child(_ghost)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_COLS * CELL
	camera.limit_bottom = MAP_ROWS * CELL
	world.add_child(camera)
	camera.make_current()

func _draw_water() -> void:
	for y in water_sim.rows:
		for x in water_sim.cols:
			var depth: float = water_sim.water_at(x, y)
			if depth < WATER_VISIBLE_MIN:
				continue
			var rect := Rect2(x * CELL, y * CELL, CELL, CELL)
			var t: float = clampf(depth / WATER_DEPTH_REFERENCE, 0.0, 1.0)
			_water_layer.draw_rect(rect, C_WATER_SHALLOW.lerp(C_WATER_DEEP, t))

func _draw_fog() -> void:
	for y in fog.rows:
		for x in fog.cols:
			if fog.is_visible(x, y):
				continue
			var rect := Rect2(x * CELL, y * CELL, CELL, CELL)
			_fog_layer.draw_rect(rect, C_FOG_EXPLORED if fog.is_explored(x, y) else C_FOG_UNSEEN)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var label := Label.new()
	label.name = "Instructions"
	label.text = "Reino em Construção\nWASD/setas: mover câmera · roda do mouse: zoom · clique: explorar/construir"
	label.position = Vector2(16, 12)
	if UITheme and UITheme.theme:
		label.theme = UITheme.theme
	canvas.add_child(label)

	_stock_label = Label.new()
	_stock_label.name = "Stock"
	_stock_label.position = Vector2(16, 56)
	if UITheme and UITheme.theme:
		_stock_label.theme = UITheme.theme
	canvas.add_child(_stock_label)

	_build_status_label = Label.new()
	_build_status_label.name = "BuildStatus"
	_build_status_label.position = Vector2(16, 150)
	if UITheme and UITheme.theme:
		_build_status_label.theme = UITheme.theme
	canvas.add_child(_build_status_label)

	_build_construction_panel(canvas)
	_update_hud()

# Painel de construção: um botão por tipo (ver `BUILDABLE_KINDS`), mostrando
# nome e custo. Clicar arma o modo de construção (`_on_build_button_pressed`);
# o botão fica desabilitado quando o Armazém não tem estoque pro custo (ver
# `_update_hud`, que reavalia isso todo frame). Ancorado no canto superior
# direito com posição fixa — o viewport do projeto é sempre 1280x720 (ver
# project.godot), não precisa reagir a resize.
const BUILD_PANEL_WIDTH := 260.0

func _build_construction_panel(canvas: CanvasLayer) -> void:
	var panel := VBoxContainer.new()
	panel.name = "BuildPanel"
	panel.position = Vector2(1280.0 - BUILD_PANEL_WIDTH - 16, 16)
	canvas.add_child(panel)

	var title := Label.new()
	title.text = "Construir:"
	if UITheme and UITheme.theme:
		title.theme = UITheme.theme
	panel.add_child(title)

	for kind in BUILDABLE_KINDS:
		var button := Button.new()
		button.name = "Build_%d" % kind
		button.custom_minimum_size = Vector2(BUILD_PANEL_WIDTH, 0)
		button.text = _build_button_text(kind)
		if UITheme and UITheme.theme:
			button.theme = UITheme.theme
		button.pressed.connect(_on_build_button_pressed.bind(kind))
		panel.add_child(button)
		_build_buttons[kind] = button

func _build_button_text(kind: int) -> String:
	var cost: Dictionary = Buildings.BUILD_COST.get(kind, {})
	var parts: Array = []
	for resource in cost:
		parts.append("%s %.0f" % [resource, cost[resource]])
	return "%s (%s)" % [BUILDING_NAME[kind], ", ".join(parts)]

func _update_hud() -> void:
	if _stock_label == null:
		return
	_stock_label.text = "madeira: %.1f    pedra: %.1f    minério: %.1f    comida: %.1f\ntábua: %.1f    bloco: %.1f    lingote: %.1f\npopulação: %d / %d (%d empregada)%s\nvila: nível %d (%.0f/%.0f XP) — alcance %d" % [
		buildings.stock.get("madeira", 0.0), buildings.stock.get("pedra", 0.0), buildings.stock.get("minério", 0.0), buildings.stock.get("comida", 0.0),
		buildings.stock.get("tábua", 0.0), buildings.stock.get("bloco", 0.0), buildings.stock.get("lingote", 0.0),
		int(population.count), buildings.housing_capacity(), population.employed(), " — faminta!" if _is_starving else "",
		progression.level, progression.xp, Progression.XP_PER_LEVEL, int(progression.reveal_radius()),
	]
	for kind in _build_buttons:
		_build_buttons[kind].disabled = not buildings.can_afford(kind)

# ---- Fase 2: prédios e trabalhador ----

# Sem sprite de prédio pronto no acervo (Tiny Town/Tiny Dungeon são chão e
# masmorra, não construções isoladas) — um retângulo com "telhado" gerado por
# código é suficiente pra distinguir tipo por cor nesta fase, no mesmo
# espírito do marcador de ouro do roguelike (02-jogo-roguelike/scenes/main.gd
# _make_gold_marker): melhor um placeholder legível do que adivinhar
# coordenada de tileset errada de novo (foi o que quase aconteceu com a
# pedra/minério na Fase 1).
func _make_building_node(building: Buildings.Building) -> Node2D:
	var node := Node2D.new()
	node.position = Vector2(building.cell) * CELL

	# Borda escura por baixo de tudo: garante silhueta legível mesmo se a cor
	# do prédio um dia acabar parecida com a do terreno embaixo dele de novo.
	var outline := ColorRect.new()
	outline.size = Vector2(CELL, CELL) * 0.86
	outline.position = Vector2(CELL, CELL) * 0.07
	outline.color = C_BUILDING_OUTLINE
	node.add_child(outline)

	var base := ColorRect.new()
	base.size = Vector2(CELL, CELL) * 0.74
	base.position = Vector2(CELL, CELL) * 0.13
	base.color = C_BUILDING[building.kind]
	node.add_child(base)

	var roof := ColorRect.new()
	roof.size = Vector2(CELL * 0.74, CELL * 0.28)
	roof.position = Vector2(CELL * 0.13, CELL * 0.13)
	roof.color = C_BUILDING_ROOF[building.kind]
	node.add_child(roof)

	# Raio-marca amarela: só fica visível no frame em que o prédio está de
	# fato POWERED (ver Buildings.advance/_compute_powered). É o único jeito
	# de perceber que a Oficina de Pedra está produzindo — ela não tem
	# trabalhador, então não tem a bolinha de estado que os outros prédios
	# ganham através do NPC alocado.
	var bolt := Sprite2D.new()
	bolt.name = "Energia"
	bolt.texture = _state_dot_texture
	bolt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bolt.modulate = STATE_COLORS[Worker.State.WORKING]
	bolt.scale = Vector2(1.6, 1.6)
	bolt.position = Vector2(CELL * 0.5, -6)
	bolt.visible = false
	node.add_child(bolt)

	return node

# Cria o Node2D de todo prédio ainda sem um — no frame 1 (`_build_world`)
# isso cobre os três prédios iniciais; a cada construção manual do jogador
# (`_build`) cobre só o prédio novo. `_nodes_built_up_to` evita recriar o nó
# de um prédio que já tem um.
func _sync_new_building_nodes() -> void:
	while _nodes_built_up_to < buildings.list.size():
		var building := buildings.list[_nodes_built_up_to]
		_nodes_built_up_to += 1
		var node := _make_building_node(building)
		_buildings_root.add_child(node)
		_building_nodes[building] = node

func _sync_building_nodes() -> void:
	for building in buildings.list:
		var node: Node2D = _building_nodes.get(building)
		if node:
			node.get_node("Energia").visible = building.powered

func _spawn_worker_node(w: Worker) -> void:
	var node := Node2D.new()

	var body := Sprite2D.new()
	body.name = "Corpo"
	body.texture = _char_texture
	body.region_enabled = true
	var coord: Vector2i = CHAR_CAST[w.id % CHAR_CAST.size()]
	body.region_rect = Rect2(
		coord.x * (CHAR_TILE + CHAR_MARGIN), coord.y * (CHAR_TILE + CHAR_MARGIN),
		CHAR_TILE, CHAR_TILE
	)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.scale = Vector2(WORKER_SCALE, WORKER_SCALE)
	body.centered = false
	# Ancorado pelos pés, não pela cabeça — ver 05-jogo-colonia/scenes/main.gd.
	body.position = Vector2(-CHAR_TILE * WORKER_SCALE * 0.5, -CHAR_TILE * WORKER_SCALE)
	node.add_child(body)

	var mark := Sprite2D.new()
	mark.name = "Estado"
	mark.texture = _state_dot_texture
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mark.scale = Vector2(2, 2)
	mark.position = Vector2(0, -CHAR_TILE * WORKER_SCALE - 11)
	node.add_child(mark)

	_workers_root.add_child(node)
	_worker_nodes[w.id] = node
	_sync_worker_node(w, node)

func _sync_worker_nodes() -> void:
	for w in workers.list:
		var node: Node2D = _worker_nodes.get(w.id)
		if node:
			_sync_worker_node(w, node)

func _sync_worker_node(w: Worker, node: Node2D) -> void:
	node.position = w.position
	node.get_node("Estado").modulate = STATE_COLORS.get(w.state, Color.WHITE)

# ---- Fase 3: carregador ----

func _spawn_carrier_node(c: Carrier) -> void:
	var node := Node2D.new()

	var body := Sprite2D.new()
	body.name = "Corpo"
	body.texture = _char_texture
	body.region_enabled = true
	body.region_rect = Rect2(
		CARRIER_CHAR_COORD.x * (CHAR_TILE + CHAR_MARGIN), CARRIER_CHAR_COORD.y * (CHAR_TILE + CHAR_MARGIN),
		CHAR_TILE, CHAR_TILE
	)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.scale = Vector2(WORKER_SCALE, WORKER_SCALE)
	body.centered = false
	body.position = Vector2(-CHAR_TILE * WORKER_SCALE * 0.5, -CHAR_TILE * WORKER_SCALE)
	node.add_child(body)

	# Um quadradinho da cor do recurso, só visível quando carregando algo —
	# é o que diferencia "indo buscar" de "voltando com carga" numa olhada,
	# sem precisar de animação.
	var cargo := ColorRect.new()
	cargo.name = "Carga"
	cargo.size = Vector2(10, 10)
	cargo.position = Vector2(-5, -CHAR_TILE * WORKER_SCALE - 16)
	cargo.visible = false
	node.add_child(cargo)

	_carriers_root.add_child(node)
	_carrier_nodes[c.id] = node
	_sync_carrier_node(c, node)

func _sync_carrier_nodes() -> void:
	for c in carriers.list:
		var node: Node2D = _carrier_nodes.get(c.id)
		if node:
			_sync_carrier_node(c, node)

func _sync_carrier_node(c: Carrier, node: Node2D) -> void:
	node.position = c.position
	var cargo: ColorRect = node.get_node("Carga")
	cargo.visible = c.carrying > 0.0
	if cargo.visible:
		cargo.color = C_CARGO.get(c.resource, Color.WHITE)

func _build_state_dot() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length()
			if d <= 3.6:
				img.set_pixel(x, y, Color.WHITE if d <= 2.4 else Color(0, 0, 0, 0.85))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
