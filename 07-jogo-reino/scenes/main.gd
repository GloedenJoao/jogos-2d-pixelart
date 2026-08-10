extends Node2D

# Fase 1: primeira tela do Reino. Mapa com relevo e depósitos (MapGen),
# nevoeiro de guerra (Fog), câmera navegável. Ainda não há economia nem
# trabalhadores — o ponto desta fase é provar que dá pra OLHAR o mapa que as
# fases seguintes vão construir em cima, e que altura/depósito/névoa
# funcionam juntos antes de existir qualquer prédio.
#
# A água (Fase 0) aparece como lagos nos pontos baixos do relevo: semeada nas
# células mais baixas do mapa gerado e deixada acomodar pelo autômato de
# verdade antes do primeiro desenho — não é uma cor pintada por cima do
# relevo, é o mesmo WaterSim.water_at() que a Fase 0 testou. Ainda não dá pra
# cavar canal nem represar aqui (isso pede uma ferramenta de jogador, que é
# Fase 2+); o que esta fase entrega é a prova visual de que "a altura que o
# MapGen gera serve pro WaterSim consumir sem adaptação" (ver
# tests/run_tests.gd _test_map_height_feeds_water_sim) é mais do que uma
# afirmação de teste.

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

var map := MapGen.new()
var fog := Fog.new()
var water_sim := WaterSim.new()
var camera: Camera2D
var _fog_layer: Node2D
var _water_layer: Node2D
var _vision_sources: Array = []

var _town_source_id := -1
var _dungeon_source_id := -1

func _ready() -> void:
	map.generate(MAP_COLS, MAP_ROWS, MAP_SEED)
	fog.setup(MAP_COLS, MAP_ROWS)
	_seed_lakes()

	_build_world()
	_build_hud()

	var start := Vector2i(MAP_COLS / 2, MAP_ROWS / 2)
	_vision_sources.append(Vector3(start.x, start.y, START_REVEAL_RADIUS))
	fog.update_visibility(_vision_sources)
	_fog_layer.queue_redraw()

	camera.position = Vector2(start) * CELL

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
	label.text = "Reino em Construção — Fase 1 (mapa)\nWASD/setas: mover câmera · roda do mouse: zoom · clique: explorar"
	label.position = Vector2(16, 12)
	if UITheme and UITheme.theme:
		label.theme = UITheme.theme
	canvas.add_child(label)
