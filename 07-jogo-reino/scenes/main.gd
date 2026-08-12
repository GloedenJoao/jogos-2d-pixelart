extends Node2D

# Fase 4: processamento. Serraria e Oficina de Pedra transformam o bruto que
# já chegou no Armazém (madeira/pedra) em processado (tábua/bloco), 1:1,
# throttladas pelo estoque de insumo disponível — sem madeira, a Serraria
# fica com trabalhador WORKING mas não produz nada, mesma lógica de "só
# rende o que existe" do extrator (Fase 2/3), só que o limite agora é
# estoque em vez de depósito ou pátio. Diferente dos extratores, elas não
# ficam sobre um depósito nem têm pátio próprio — leem e escrevem direto no
# Armazém (ver o comentário em buildings.gd sobre por que isso é
# simplificação consciente, não descuido).
#
# Tudo daqui pra baixo é histórico das fases anteriores, sem mudança de
# arquitetura — ver a quebra completa em docs/plano-projeto7-reino.md:
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
const START_REVEAL_RADIUS := 9.0
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
}
const C_BUILDING_ROOF := {
	Buildings.Kind.LUMBERJACK: Color("5c3a20"),
	Buildings.Kind.QUARRY: Color("7a2f26"),
	Buildings.Kind.WAREHOUSE: Color("8a7c5c"),
	Buildings.Kind.SAWMILL: Color("8f6f2c"),
	Buildings.Kind.STONE_WORKSHOP: Color("454a54"),
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
}

var map := MapGen.new()
var fog := Fog.new()
var water_sim := WaterSim.new()
var pathfinder := Pathfinder.new()
var buildings := Buildings.new()
var workers := Workers.new()
var carriers := Carriers.new()
var camera: Camera2D
var _fog_layer: Node2D
var _water_layer: Node2D
var _buildings_root: Node2D
var _workers_root: Node2D
var _carriers_root: Node2D
var _worker_nodes: Dictionary = {}   # Worker.id -> Node2D
var _carrier_nodes: Dictionary = {}  # Carrier.id -> Node2D
var _vision_sources: Array = []
var _stock_label: Label

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

	var start := Vector2i(MAP_COLS / 2, MAP_ROWS / 2)
	pathfinder.setup(MAP_COLS, MAP_ROWS, CELL)
	_place_starting_buildings(start)

	_build_world()
	_build_hud()

	# Um trabalhador por prédio: a Fase 2 nasceu com "um trabalhador único" no
	# escopo, mas isso deixava metade dos extratores plantados no mapa sem
	# nunca produzir nada — pra quem está jogando, prédio parado e prédio
	# inexistente parecem a mesma coisa. Continua sendo "um trabalhador por
	# posto", não staffing fracionário: isso só passaria a valer a pena com
	# múltiplas vagas por prédio (ver o comentário em buildings.gd).
	for i in buildings.list.size():
		var building := buildings.list[i]
		if building.kind == Buildings.Kind.WAREHOUSE:
			continue
		var worker := workers.spawn(Vector2(start) * CELL)
		buildings.assign(i, worker)
		workers.send_to(worker, _work_spot_for(building), pathfinder)
		_spawn_worker_node(worker)

	var carrier := carriers.spawn(Vector2(start) * CELL)
	_spawn_carrier_node(carrier)

	_vision_sources.append(Vector3(start.x, start.y, START_REVEAL_RADIUS))
	fog.update_visibility(_vision_sources)
	_fog_layer.queue_redraw()

	camera.position = Vector2(start) * CELL

# O Armazém nasce na própria célula da vila — é o destino fixo do
# carregador, não precisa buscar depósito nenhum. Posto de Lenhador e
# Pedreira continuam buscando em anéis crescentes a célula de depósito mais
# próxima (ver Buildings.nearest_deposit_cell); uma semente de mapa sem
# floresta/pedra por perto simplesmente não ganha aquele prédio agora — não
# é erro, é o jogo dizendo "explore mais" (mesma ideia do plano: "depósito
# se esgota → motiva avançar pelo mapa").
func _place_starting_buildings(start: Vector2i) -> void:
	buildings.place(Buildings.Kind.WAREHOUSE, start)

	var forest_cell := Buildings.nearest_deposit_cell(map, MapGen.Kind.FOREST, start, BUILDING_SEARCH_RADIUS)
	if forest_cell.x >= 0:
		buildings.place(Buildings.Kind.LUMBERJACK, forest_cell)
	var stone_cell := Buildings.nearest_deposit_cell(map, MapGen.Kind.STONE, start, BUILDING_SEARCH_RADIUS)
	if stone_cell.x >= 0:
		buildings.place(Buildings.Kind.QUARRY, stone_cell)

	# Serraria e Oficina de Pedra (Fase 4) não dependem de depósito nenhum —
	# elas processam o que já chegou no Armazém, então "perto da vila" é a
	# única exigência. Só precisam de uma célula livre, não em cima de outro
	# prédio.
	var occupied := {}
	for building in buildings.list:
		occupied[building.cell] = true
	var sawmill_cell := _free_cell_near(start, Vector2i(2, -2), occupied)
	buildings.place(Buildings.Kind.SAWMILL, sawmill_cell)
	occupied[sawmill_cell] = true
	var workshop_cell := _free_cell_near(start, Vector2i(-2, -2), occupied)
	buildings.place(Buildings.Kind.STONE_WORKSHOP, workshop_cell)

	var solids: Array = []
	for building in buildings.list:
		solids.append(building.cell)
	pathfinder.rebuild(solids)

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
	workers.advance(delta, pathfinder)
	buildings.advance(delta, map, workers)
	carriers.advance(delta, pathfinder, buildings)
	pathfinder.decay(delta)
	_sync_worker_nodes()
	_sync_carrier_nodes()
	_update_hud()
	_pan_with_keys(delta)

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_scout_at(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / ZOOM_STEP)

func _zoom_by(factor: float) -> void:
	var z: float = clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

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
	for building in buildings.list:
		_buildings_root.add_child(_make_building_node(building))

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
	label.text = "Reino em Construção — Fase 4 (processamento)\nWASD/setas: mover câmera · roda do mouse: zoom · clique: explorar"
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
	_update_hud()

func _update_hud() -> void:
	if _stock_label == null:
		return
	_stock_label.text = "madeira: %.1f    pedra: %.1f    tábua: %.1f    bloco: %.1f" % [
		buildings.stock.get("madeira", 0.0), buildings.stock.get("pedra", 0.0),
		buildings.stock.get("tábua", 0.0), buildings.stock.get("bloco", 0.0),
	]

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

	return node

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
