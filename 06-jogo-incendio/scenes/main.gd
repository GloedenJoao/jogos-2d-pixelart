extends Node2D

# "O Vale em Chamas" — a tela.
#
# Tudo que decide alguma coisa está fora daqui: o incêndio em `FireSim`, as
# regras em `Mission`, as pessoas em `Agents`, a geometria em `Layout`. Esta
# cena desenha e escuta o mouse.
#
# ---- por que ela não se parece com a do Projeto 5 ----
#
# Lá o assunto eram pessoas andando pelo chão, então o HUD virou uma tira no
# topo e nada podia flutuar embaixo. Aqui o assunto é uma FRENTE que avança, e
# isso muda três coisas:
#
#   1. **O mapa é maior que a tela.** Um incêndio precisa de espaço pra ter
#      forma — frente, flanco, retaguarda. Daí a câmera, e daí o minimapa: um
#      jogo em que se descobre por acaso que uma casa queimou do outro lado
#      seria um jogo sobre arrastar a tela.
#   2. **Ferramenta é escolha constante.** Barra vertical fixa à esquerda, com
#      as três sempre visíveis e o custo à vista, em vez de menu.
#   3. **O vento é a informação mais cara do jogo.** Bússola grande no topo,
#      não um ícone discreto. Quem não olha o vento não entende por que perdeu.
#
# O desenho é um `_draw()` só, com corte pelo que está visível. Sprite por
# célula (o que o Projeto 5 fazia) daria mil e poucos nós num mapa deste
# tamanho, e o chão aqui muda o tempo todo — cada célula que queima ou vira
# aceiro teria de mexer no nó dela.

const SAVE_KEY := Mission.SAVE_KEY

const TOWN_PATH := "res://assets/town/tilemap_packed.png"
const TILE := Layout.TILE
const CELL := Layout.CELL

# --- tiles do Kenney Tiny Town (conferidos no sheet) ---
#
# Capim quase todo LISO. A primeira versão sorteava entre quatro tiles com peso
# igual, e um deles é o de flores amarelas — o resultado foi um vale coberto de
# pontinhos brilhantes onde o olho não achava mais nem o fogo nem as pessoas.
# Chão é fundo: num jogo em que a informação está no que se mexe, o que não se
# mexe tem que sumir.
const T_GRASS := [
	Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0),
	Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(2, 0),
]
const T_DIRT := Vector2i(1, 2)
const T_BRUSH := Vector2i(5, 0)
const T_FIELD := Vector2i(5, 1)
# Árvores INTEIRAS num tile só (copa com tronco). As da linha 1 são metades de
# árvore grande e, usadas sozinhas, viravam pares de bolotas verdes flutuando.
const T_TREE := [Vector2i(4, 2), Vector2i(3, 2), Vector2i(4, 2)]
const T_HOUSE_WALL := Vector2i(2, 6)
const T_HOUSE_ROOF := [Vector2i(1, 4), Vector2i(5, 4)]

# --- cores ---
const C_BURNT := Color("241f21")
const C_BURNT_SPECK := Color("3b3336")
const C_WATER := Color("24567a")
const C_WATER_LIGHT := Color("4b93bd")
const C_ROCK := Color("5c5a63")
const C_ROCK_DARK := Color("3e3d45")
const C_ROCK_LIGHT := Color("777680")
const C_EMBER := Color("d4622c")
const C_FLAME := [Color("ffe066"), Color("ffa62b"), Color("e8442c")]
const C_SMOKE := Color(0.75, 0.72, 0.70, 0.30)
const C_HEAT := Color(1.0, 0.45, 0.15)
const C_WET := Color(0.35, 0.65, 1.0)
const C_PANEL := Color("14100f")
const C_PANEL_EDGE := Color("3a2f2a")
const C_TEXT := Color("f3ece2")
const C_DIM := Color("9d9089")
const C_GOOD := Color("8ecf6b")
const C_BAD := Color("e8593f")
const C_TOOL_ON := Color("f2b134")

# Cada ferramenta tem uma cor, e a mesma cor aparece no botão, no marcador que
# fica no chão e no cursor. É como o jogador liga "o que eu escolhi" a "o que
# vai acontecer ali" sem ler nada.
const C_ORDER := {
	Tools.DIG: Color("c8a165"),
	Tools.WATER: Color("57b8e8"),
	Tools.BACKFIRE: Color("e8663f"),
}

var mission: Mission = null
var bot: ContainmentBot = null
var machine: StateMachine = null

var level_index := 0
var screen := "briefing"
var tool_id := Tools.DIG
var show_risk := false
var bot_active := false
var camera := Vector2.ZERO
var progress: Dictionary = {}

var _town: Texture2D = null
var _font: Font = null
var _time := 0.0
var _forecast := PackedFloat32Array()
var _forecast_clock := 0.0
var _hover := Vector2i(-1, -1)
var _bodies: Array = []            # texturas assadas, na ordem de agents.crew + civilians
var _faces: Array = []
var _notice := ""
var _notice_left := 0.0
var _panning := false

func _ready() -> void:
	_town = load(TOWN_PATH)
	_font = load(UITheme.PIXEL_FONT_PATH)
	progress = Mission.load_progress(get_node("/root/SaveSystem"))
	level_index = clampi(int(progress.get("unlocked", 1)) - 1, 0, Levels.count() - 1)

	machine = StateMachine.new()
	machine.name = "Screens"
	for entry in [["Briefing", BriefingState], ["Playing", PlayingState], ["Result", ResultState]]:
		var state = entry[1].new()
		state.name = entry[0]
		state.main = self
		machine.add_child(state)
	start_level(level_index)
	add_child(machine)

func _process(delta: float) -> void:
	_time += delta
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_notice = ""
	_pan_with_keys(delta)
	if screen != "playing":
		queue_redraw()

# ---- ciclo da fase ----

func start_level(index: int) -> void:
	level_index = clampi(index, 0, Levels.count() - 1)
	mission = Mission.new()
	mission.start(level_index)
	bot = ContainmentBot.new()
	bot.setup(mission)
	bot_active = false
	tool_id = Tools.DIG
	show_risk = false
	_notice = ""
	_forecast = PackedFloat32Array()
	_forecast_clock = 999.0
	_bake_people()
	_center_camera_on_fire()
	queue_redraw()

# Assar o corpo de cada pessoa uma vez, no começo da fase. É caro (compõe e
# recoloriza camadas) e não muda depois — fazer isso por frame derrubaria o
# jogo, e fazer sob demanda daria engasgo na primeira vez que alguém aparece.
func _bake_people() -> void:
	_bodies.clear()
	_faces.clear()
	for person in mission.agents.crew:
		_bodies.append(PersonArt.bake_body(person.look))
		_faces.append(PersonArt.bake_face(person.look))
	for civil in mission.agents.civilians:
		_bodies.append(PersonArt.bake_body(civil.look))
		_faces.append(PersonArt.bake_face(civil.look))

func _center_camera_on_fire() -> void:
	var focus := Vector2.ZERO
	var count := 0
	for cell in mission.parsed.ignitions:
		focus += Layout.cell_center(cell)
		count += 1
	if count == 0:
		focus = Layout.world_size(mission.sim.cols, mission.sim.rows) * 0.5
	else:
		focus /= float(count)
	var visible := Layout.viewport_rect().size
	camera = focus - visible * 0.5
	_clamp_camera()

func _clamp_camera() -> void:
	var limit := Layout.camera_limit(mission.sim.cols, mission.sim.rows)
	camera = Vector2(clampf(camera.x, 0.0, limit.x), clampf(camera.y, 0.0, limit.y))

func commit_result() -> void:
	progress = Mission.record(get_node("/root/SaveSystem"), level_index, mission.summary())

func refresh_forecast(delta: float) -> void:
	# A previsão é o cálculo mais caro do frame (um Dijkstra sobre o vale
	# inteiro). Duas vezes por segundo é mais que suficiente: o fogo anda uma
	# célula a cada dois segundos e meio.
	_forecast_clock += delta
	if _forecast_clock < 0.5:
		return
	_forecast_clock = 0.0
	_forecast = mission.sim.forecast()

# ---- entrada ----

func is_confirm(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT

func is_restart(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cell_under(event.position)
		if _panning:
			camera -= event.relative
			_clamp_camera()
		queue_redraw()

func handle_play_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: tool_id = Tools.DIG
			KEY_2: tool_id = Tools.WATER
			KEY_3: tool_id = Tools.BACKFIRE
			KEY_TAB: show_risk = not show_risk
			KEY_F: mission.cycle_speed()
			KEY_B: _toggle_bot()
			KEY_R: start_level(level_index)
			_: return
		queue_redraw()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			return
		if not event.pressed:
			return
		var cell := _cell_under(event.position)
		if cell.x < 0:
			_click_hud(event.position)
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mission.cancel(cell)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_try_order(cell)
		queue_redraw()

func _try_order(cell: Vector2i) -> void:
	if mission.order(tool_id, cell):
		return
	# Recusar em silêncio é o pior que uma interface pode fazer: o jogador
	# repete o clique achando que errou a mira. Cada recusa diz o motivo.
	if mission.remaining(tool_id) == 0:
		_flash("Acabou %s." % Tools.name_of(tool_id).to_lower())
	elif not Tools.can_target(tool_id, mission.sim, cell):
		var kind := mission.sim.kind_at(cell.x, cell.y)
		if mission.sim.state_at(cell.x, cell.y) == FireSim.BURNING and tool_id == Tools.DIG:
			_flash("Não dá pra cavar no meio do fogo.")
		elif mission.sim.state_at(cell.x, cell.y) == FireSim.BURNT:
			_flash("Aqui já queimou.")
		else:
			_flash("Não dá pra fazer isso em %s." % Terrain.name_of(kind))
	else:
		_flash("Já tem ordem aqui.")

func _flash(message: String) -> void:
	_notice = message
	_notice_left = 2.4

func _toggle_bot() -> void:
	bot_active = not bot_active
	_flash("Demonstração ligada." if bot_active else "Demonstração desligada.")

func _click_hud(position: Vector2) -> void:
	for i in Tools.ORDER.size():
		if _tool_button_rect(i).has_point(position):
			tool_id = Tools.ORDER[i]
			return
	if _minimap_rect().has_point(position):
		var scale := float(Layout.minimap_scale(mission.sim.cols, mission.sim.rows))
		var cell := (position - _minimap_rect().position) / scale
		camera = cell * CELL - Layout.viewport_rect().size * 0.5
		_clamp_camera()

func _pan_with_keys(delta: float) -> void:
	if screen != "playing":
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1.0
	if move == Vector2.ZERO:
		return
	camera += move.normalized() * 460.0 * delta
	_clamp_camera()

# Célula sob o ponteiro, ou (-1,-1) se o ponteiro está sobre o HUD. Devolver
# uma célula válida sob a barra de ferramentas faria o clique num botão cavar
# um buraco no vale atrás dele.
func _cell_under(position: Vector2) -> Vector2i:
	if not Layout.viewport_rect().has_point(position):
		return Vector2i(-1, -1)
	# Pelo MESMO offset que desenha o mundo. Enquanto isto usava
	# `world_origin() - camera` direto, a centralização de mapas pequenos
	# deslocava o desenho e não o clique: o jogador cavava algumas células ao
	# lado de onde tinha clicado, e nada na tela explicava por quê.
	var cell := Layout.cell_of(position - _world_offset())
	if mission == null or not mission.sim.inside(cell.x, cell.y):
		return Vector2i(-1, -1)
	return cell

# ---- desenho ----

func _draw() -> void:
	if mission == null:
		return
	_draw_world()
	_draw_side_bar()
	_draw_top_strip()
	if screen == "briefing":
		_draw_briefing()
	elif screen == "result":
		_draw_result()

func _visible_cells() -> Rect2i:
	var rect := Layout.viewport_rect()
	var top_left := Layout.cell_of(camera)
	var bottom_right := Layout.cell_of(camera + rect.size) + Vector2i.ONE
	return Rect2i(
		Vector2i(maxi(0, top_left.x), maxi(0, top_left.y)),
		Vector2i(
			mini(mission.sim.cols, bottom_right.x) - maxi(0, top_left.x),
			mini(mission.sim.rows, bottom_right.y) - maxi(0, top_left.y)
		)
	)

# Sorteio estável por célula. Uma soma tipo `(x * a + y * b) % n` parece
# aleatória e não é: se `b` e `n` tiverem fator comum, a coluna inteira recebe o
# mesmo tile. Foi o que aconteceu — o vale ganhou listras verticais de flores,
# perfeitamente alinhadas, que o olho lê como padrão de propósito.
func _scatter(x: int, y: int, n: int) -> int:
	var h: int = (x * 92837111) ^ (y * 689287499)
	h = (h ^ (h >> 15)) * 2246822519
	return absi(h) % n

func _tile(coord: Vector2i, at: Vector2, tint: Color = Color.WHITE) -> void:
	draw_texture_rect_region(
		_town, Rect2(at, Vector2(CELL, CELL)),
		Rect2(Vector2(coord) * TILE, Vector2(TILE, TILE)), tint
	)

# Mapa menor que a área visível fica CENTRADO nela. Sem isto, um vale baixo
# (a fase 1 tem 14 fileiras) era desenhado grudado no topo e sobrava uma faixa
# preta de duzentos pixels embaixo, que lê como bug, não como enquadramento.
func _world_offset() -> Vector2:
	var visible := Layout.viewport_rect().size
	var total := Layout.world_size(mission.sim.cols, mission.sim.rows)
	var slack := Vector2(maxf(0.0, visible.x - total.x), maxf(0.0, visible.y - total.y)) * 0.5
	return Layout.world_origin() + slack - camera

func _draw_world() -> void:
	var sim := mission.sim
	var off := _world_offset()
	var view := _visible_cells()

	# 1. chão
	for y in range(view.position.y, view.position.y + view.size.y):
		for x in range(view.position.x, view.position.x + view.size.x):
			var idx := sim.index_of(x, y)
			var at := Vector2(x, y) * CELL + off
			var kind: int = sim.kind[idx]
			var state: int = sim.state[idx]

			if kind == Terrain.WATER:
				_draw_water(at, x, y)
				continue
			if kind == Terrain.ROCK:
				_draw_rock(at, x, y)
				continue

			# Sob tudo vai grama: os tiles de mato, lavoura e mata do Kenney têm
			# fundo transparente, e sem uma base o vale ficaria furado.
			_tile(T_GRASS[_scatter(x, y, T_GRASS.size())], at)

			if state == FireSim.BURNT:
				_draw_ash(at, x, y, sim.heat[idx])
				continue

			match kind:
				Terrain.DIRT:
					_tile(T_DIRT, at)
				Terrain.BRUSH:
					_tile(T_BRUSH, at)
				Terrain.FIELD:
					_tile(T_FIELD, at)
				Terrain.TREE:
					_tile(T_TREE[_scatter(x, y, T_TREE.size())], at)

			# umidade: só aparece quando é bem mais que a natural, senão o vale
			# inteiro ficaria com um véu azul permanente.
			var wet: float = sim.moisture[idx] - Terrain.moisture_of(kind)
			if wet > 0.12:
				draw_rect(Rect2(at, Vector2(CELL, CELL)), Color(C_WET.r, C_WET.g, C_WET.b, minf(0.34, wet * 0.34)))

	# 2. casas (o telhado sobe pra fora da célula, senão a casa não cabe em 16px)
	for y in range(view.position.y, view.position.y + view.size.y):
		for x in range(view.position.x, view.position.x + view.size.x):
			var idx := sim.index_of(x, y)
			if sim.kind[idx] != Terrain.HOUSE or sim.state[idx] == FireSim.BURNT:
				continue
			var at := Vector2(x, y) * CELL + off
			var tint := Color.WHITE if sim.state[idx] != FireSim.BURNING else Color(1.0, 0.72, 0.6)
			_tile(T_HOUSE_ROOF[(x + y) % T_HOUSE_ROOF.size()], at - Vector2(0, CELL), tint)
			_tile(T_HOUSE_WALL, at, tint)

	# 3. calor: o aviso que vem ANTES da chama. É o que permite ao jogador
	#    reagir a um metro de distância em vez de reagir ao incêndio.
	for y in range(view.position.y, view.position.y + view.size.y):
		for x in range(view.position.x, view.position.x + view.size.x):
			var idx := sim.index_of(x, y)
			# Rocha e água acumulam calor no modelo (todo vizinho recebe), mas
			# não podem queimar — pintá-las de laranja dava ao jogador o aviso
			# mais enganoso possível: a barreira natural parecia estar prestes
			# a pegar fogo.
			if sim.state[idx] != FireSim.INTACT or not Terrain.is_flammable(sim.kind[idx]):
				continue
			var heat: float = sim.heat[idx]
			if heat <= 0.08:
				continue
			var at := Vector2(x, y) * CELL + off
			draw_rect(Rect2(at, Vector2(CELL, CELL)), Color(C_HEAT.r, C_HEAT.g, C_HEAT.b, minf(0.42, heat * 0.30)))

	if show_risk:
		_draw_risk(off, view)

	# 4. chamas e fumaça
	for y in range(view.position.y, view.position.y + view.size.y):
		for x in range(view.position.x, view.position.x + view.size.x):
			var idx := sim.index_of(x, y)
			if sim.state[idx] != FireSim.BURNING:
				continue
			_draw_flame(Vector2(x, y) * CELL + off, x, y, sim.fuel[idx] / maxf(0.01, Terrain.fuel_of(sim.kind[idx])))

	_draw_orders(off)
	_draw_people(off)
	_draw_embers(off)
	_draw_hover(off)

# Rocha e água são desenhadas, não tiradas do sheet: o Tiny Town não tem tile
# de água nenhum, e o que mais parecia pedra é um pedaço de muralha de castelo
# que, ladrilhado, virava uma parede bege atravessando o vale. Aqui elas
# precisam ler como BARREIRA NATURAL num relance, porque é assim que o jogador
# planeja — "deste lado o fogo não passa".

func _draw_water(at: Vector2, x: int, y: int) -> void:
	draw_rect(Rect2(at, Vector2(CELL, CELL)), C_WATER)
	for i in 2:
		var phase := _time * 1.4 + float(x) * 0.8 + float(y) * 0.5 + float(i) * 2.2
		var offset := (sin(phase) * 0.5 + 0.5) * float(CELL - 10)
		var width := 8.0 + sin(phase * 1.7) * 4.0
		draw_rect(Rect2(at + Vector2(4.0 + sin(phase * 0.9) * 6.0, 4.0 + offset), Vector2(width, 2)),
			Color(C_WATER_LIGHT.r, C_WATER_LIGHT.g, C_WATER_LIGHT.b, 0.7))

func _draw_rock(at: Vector2, x: int, y: int) -> void:
	draw_rect(Rect2(at, Vector2(CELL, CELL)), C_ROCK_DARK)
	# Blocos deslocados por linha: pedra empilhada, não azulejo. O padrão vem
	# de um hash da célula, então é estável entre quadros (pedra que muda de
	# desenho a cada frame chama mais atenção que o incêndio).
	var shift := (y % 2) * 8
	for row in 2:
		for column in 2:
			var block := at + Vector2(float(column * 16 + shift - 8), float(row * 16))
			var tone: Color = C_ROCK if ((x + y + row + column) % 3) != 0 else C_ROCK_LIGHT
			draw_rect(Rect2(block + Vector2(1, 1), Vector2(14, 14)), tone)

# Cinza com brasa: enquanto a célula ainda está quente, pontinhos laranja
# piscam nela. É o que mostra que o fogo ACABOU de passar por ali — sem isso a
# área queimada é um retângulo preto uniforme e o jogador perde a noção de
# para onde a frente está indo.
func _draw_ash(at: Vector2, x: int, y: int, heat: float) -> void:
	draw_rect(Rect2(at, Vector2(CELL, CELL)), C_BURNT)
	for i in 4:
		var sx := float((x * 7 + y * 13 + i * 29) % (CELL - 6)) + 3.0
		var sy := float((x * 11 + y * 5 + i * 17) % (CELL - 6)) + 3.0
		var glow := heat * (0.5 + 0.5 * sin(_time * 3.0 + float(x * 3 + y * 5 + i * 7)))
		var color: Color = C_BURNT_SPECK if glow < 0.12 else C_EMBER
		var alpha: float = 1.0 if glow < 0.12 else clampf(glow, 0.2, 0.9)
		draw_rect(Rect2(at + Vector2(sx, sy), Vector2(2, 2)), Color(color.r, color.g, color.b, alpha))

# Chama desenhada por código: nenhum pack CC0 traz fogo em pixel art que case
# com o Tiny Town, e fogo parado seria a pior coisa possível num jogo cujo
# assunto é o fogo se mexendo. Três línguas por célula, com altura oscilando em
# fases diferentes, e a cor subindo de vermelho na base a amarelo na ponta.
func _draw_flame(at: Vector2, x: int, y: int, fuel_ratio: float) -> void:
	var strength := clampf(0.4 + fuel_ratio * 0.6, 0.4, 1.0)
	var seed_value := float((x * 73 + y * 31) % 97)
	var center := at + Vector2(CELL * 0.5, CELL * 0.72)

	# Halo: a luz que a chama joga em volta. É o que faz o fogo parecer emitir
	# em vez de ser um adesivo, e é o que dá volume a uma frente vista de longe.
	var pulse := 0.82 + 0.18 * sin(_time * 6.0 + seed_value)
	draw_circle(center, 17.0 * strength * pulse, Color(1.0, 0.45, 0.12, 0.16))

	# Três línguas em forma de gota, cada uma com fase própria. A primeira
	# versão empilhava retângulos e o resultado, repetido por cinquenta células,
	# lia como um muro de tijolos — a silhueta é o que faz fogo parecer fogo.
	for i in 3:
		var phase := _time * 8.0 + seed_value + float(i) * 2.4
		var height := (13.0 + sin(phase) * 5.0) * strength
		var half := (4.5 + sin(phase * 1.4) * 1.4) * strength
		var base_x := at.x + 7.0 + float(i) * 9.0 + sin(phase * 0.7) * 1.5
		var base_y := at.y + CELL - 1.0
		var lean := sin(phase * 0.9) * 3.0
		for layer in 3:
			var shrink := 1.0 - float(layer) * 0.32
			draw_colored_polygon(PackedVector2Array([
				Vector2(base_x - half * shrink, base_y),
				Vector2(base_x + half * shrink, base_y),
				Vector2(base_x + half * shrink * 0.45, base_y - height * shrink * 0.6),
				Vector2(base_x + lean * shrink, base_y - height * shrink),
				Vector2(base_x - half * shrink * 0.45, base_y - height * shrink * 0.6),
			]), C_FLAME[2 - layer])

	# fumaça: sobe e some, calculada a partir do tempo (não guarda partícula)
	for i in 2:
		var t: float = fmod(_time * 0.55 + seed_value * 0.11 + float(i) * 0.5, 1.0)
		var rise := t * 52.0
		var alpha := (1.0 - t) * 0.30
		draw_circle(at + Vector2(CELL * 0.5 + sin(t * 5.0 + seed_value) * 8.0, CELL - 10.0 - rise),
			3.0 + t * 7.0, Color(C_SMOKE.r, C_SMOKE.g, C_SMOKE.b, alpha))

# O overlay que ensina a jogar: em quanto tempo o fogo chega a cada lugar.
#
# A primeira versão interpolava vermelho→VERDE conforme o tempo aumentava, e
# era invisível: o vale já é verde. Pintar informação da mesma cor do fundo é o
# mesmo que não pintar. Agora a rampa sai do vermelho e vai para o AZUL, que
# não existe em nenhum outro lugar deste mapa a não ser na água.
#
# E o azul-claro chapado é a informação mais valiosa do jogo: célula que o fogo
# NÃO alcança. É assim que um aceiro se anuncia como pronto — o outro lado
# muda de cor inteiro, antes de a chama chegar, e o jogador vê o próprio plano
# funcionando em vez de torcer.
const RISK_BANDS := [
	[12.0, Color(0.95, 0.16, 0.10, 0.55)],   # o fogo está em cima
	[28.0, Color(0.98, 0.45, 0.10, 0.48)],
	[55.0, Color(0.98, 0.78, 0.20, 0.38)],
	[95.0, Color(0.75, 0.70, 0.35, 0.26)],   # ainda dá tempo de sobra
]
const RISK_SAFE := Color(0.35, 0.72, 0.95, 0.30)

func _draw_risk(off: Vector2, view: Rect2i) -> void:
	if _forecast.size() != mission.sim.cols * mission.sim.rows:
		_forecast = mission.sim.forecast()
	for y in range(view.position.y, view.position.y + view.size.y):
		for x in range(view.position.x, view.position.x + view.size.x):
			var idx := mission.sim.index_of(x, y)
			if mission.sim.state[idx] != FireSim.INTACT or not Terrain.is_flammable(mission.sim.kind[idx]):
				continue
			var eta: float = _forecast[idx]
			var color := RISK_SAFE
			if eta < FireSim.FORECAST_INF:
				color = Color(0, 0, 0, 0)
				for band in RISK_BANDS:
					if eta <= float(band[0]):
						color = band[1]
						break
			if color.a <= 0.0:
				continue
			draw_rect(Rect2(Vector2(x, y) * CELL + off, Vector2(CELL, CELL)), color)

func _draw_orders(off: Vector2) -> void:
	for order in mission.agents.orders:
		var at: Vector2 = Vector2(order.cell) * CELL + off
		var color: Color = C_ORDER[order.tool_id]
		var pulse := 0.55 + 0.45 * sin(_time * 5.0)
		draw_rect(Rect2(at + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)),
			Color(color.r, color.g, color.b, 0.9 * pulse), false, 2.0)
		# quem já está sendo atendido ganha um preenchimento leve: o jogador
		# precisa distinguir "pedi" de "está acontecendo".
		if order.taken_by >= 0:
			draw_rect(Rect2(at + Vector2(5, 5), Vector2(CELL - 10, CELL - 10)),
				Color(color.r, color.g, color.b, 0.35))

func _draw_people(off: Vector2) -> void:
	var index := 0
	for person in mission.agents.crew:
		_draw_person(person.pos + off, person.facing, person.walk, person.moving, index,
			person.state == "working", "crew")
		index += 1
	for civil in mission.agents.civilians:
		if civil.state != "safe" and civil.state != "lost":
			_draw_person(civil.pos + off, civil.facing, civil.walk, civil.moving, index,
				false, civil.state)
		index += 1

func _draw_person(at: Vector2, facing: Vector2, walk: float, moving: bool, index: int,
		working: bool, role: String) -> void:
	if index >= _bodies.size():
		return
	var body: Texture2D = _bodies[index]
	var pose := PersonArt.POSE_BACK if facing.y < -0.35 else PersonArt.POSE_FRONT
	var flip := facing.x < -0.2
	var bob := 0.0
	if moving:
		bob = -absf(sin(walk * 3.2)) * 2.0
	elif working:
		bob = sin(_time * 8.0) * 1.5

	var size := Vector2(TILE, TILE) * Layout.SCALE
	var top_left := at - size * 0.5 + Vector2(0, bob - 6.0)
	var region := Rect2(Vector2(PersonArt.pose_offset(pose), 0), Vector2(TILE, TILE))
	# Sombra primeiro: sem ela o boneco parece colado no céu, e num mapa com
	# muita coisa laranja acontecendo a silhueta some.
	draw_circle(at + Vector2(0, 9), 7.0, Color(0, 0, 0, 0.28))

	if flip:
		draw_set_transform(top_left + Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(body, Rect2(Vector2.ZERO, size), region)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(body, Rect2(top_left, size), region)

	if pose == PersonArt.POSE_FRONT and index < _faces.size():
		var fear := 0.0
		var expr := PersonArt.expression_for_fire(role if role != "crew" else ("working" if working else "idle"),
			fear, fmod(_time + float(index), 4.0) < 0.12)
		var face_region := PersonArt.face_region(expr, PersonArt.FACE_FRONT)
		var face_size := Vector2(face_region.size) * Layout.SCALE
		draw_texture_rect_region(_faces[index],
			Rect2(top_left + Vector2(PersonArt.PART_HEAD.position) * Layout.SCALE, face_size), face_region)

	# Um anel embaixo separa quem manda de quem foge. Sem isso, no meio da
	# fumaça, brigadista e morador viram a mesma manchinha.
	if role == "crew":
		draw_arc(at + Vector2(0, 9), 8.0, 0.0, TAU, 12, C_TOOL_ON, 1.5)
	elif role == "panic":
		draw_arc(at + Vector2(0, 9), 8.0, 0.0, TAU, 12, C_BAD, 1.5)

func _draw_embers(off: Vector2) -> void:
	for pair in mission.sim.embers:
		var from: Vector2 = Layout.cell_center(pair[0]) + off
		var to: Vector2 = Layout.cell_center(pair[1]) + off
		draw_line(from, to, Color(1.0, 0.65, 0.25, 0.55), 2.0)
		draw_circle(to, 4.0, Color(1.0, 0.85, 0.4, 0.85))

func _draw_hover(off: Vector2) -> void:
	if _hover.x < 0 or screen != "playing":
		return
	var at := Vector2(_hover) * CELL + off
	var allowed := Tools.can_target(tool_id, mission.sim, _hover) and mission.remaining(tool_id) != 0
	var color: Color = C_ORDER[tool_id] if allowed else C_BAD
	draw_rect(Rect2(at, Vector2(CELL, CELL)), Color(color.r, color.g, color.b, 0.85), false, 2.0)

# ---- HUD ----

func _text(at: Vector2, message: String, size: int = 18, color: Color = C_TEXT) -> void:
	draw_string(_font, at, message, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _text_center(center_x: float, y: float, message: String, size: int = 18, color: Color = C_TEXT) -> void:
	var width := _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, Vector2(center_x - width * 0.5, y), message, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _panel(rect: Rect2, fill: Color = C_PANEL) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, C_PANEL_EDGE, false, 2.0)

func _tool_button_rect(slot: int) -> Rect2:
	return Rect2(10.0, 96.0 + float(slot) * 78.0, float(Layout.BAR_WIDTH) - 20.0, 68.0)

func _minimap_rect() -> Rect2:
	return Rect2(Layout.minimap_origin(mission.sim.cols, mission.sim.rows),
		Layout.minimap_size(mission.sim.cols, mission.sim.rows))

func _draw_side_bar() -> void:
	var bar := Rect2(0, 0, Layout.BAR_WIDTH, Layout.VIEWPORT.y)
	_panel(bar)

	_text(Vector2(12, 30), "Fase %d/%d" % [level_index + 1, Levels.count()], 16, C_DIM)
	_text(Vector2(12, 56), String(mission.level["name"]), 24, C_TOOL_ON)
	_text(Vector2(12, 78), String(mission.level["teaches"]).left(30), 12, C_DIM)

	for i in Tools.ORDER.size():
		var id: int = Tools.ORDER[i]
		var rect := _tool_button_rect(i)
		var left: int = mission.remaining(id)
		var usable := left != 0
		var active := id == tool_id
		var fill: Color = C_ORDER[id]
		fill.a = 0.30 if active else 0.10
		if not usable:
			fill = Color(0.25, 0.2, 0.2, 0.35)
		draw_rect(rect, fill)
		draw_rect(rect, C_ORDER[id] if active else C_PANEL_EDGE, false, 2.0)

		_text(rect.position + Vector2(10, 24), Tools.name_of(id), 20,
			C_TEXT if usable else C_DIM)
		_text(rect.position + Vector2(rect.size.x - 22, 24), Tools.key_of(id), 16, C_DIM)
		if Tools.is_limited(id):
			_text(rect.position + Vector2(10, 44), "restam %d" % left, 15,
				C_TEXT if usable else C_BAD)
		else:
			_text(rect.position + Vector2(10, 44), "sem limite", 15, C_DIM)
		_text(rect.position + Vector2(10, 60), "%.1fs por célula" % Tools.seconds_of(id), 12, C_DIM)

	# dica da ferramenta escolhida, em texto corrido e quebrado à mão
	var hint_y := 96.0 + float(Tools.ORDER.size()) * 78.0 + 14.0
	for line in _wrap(Tools.hint_of(tool_id), 26):
		_text(Vector2(12, hint_y), line, 13, C_DIM)
		hint_y += 15.0

	_draw_minimap()

# O vale inteiro num quadradinho. Cada célula é um pixel (ou dois): o que se
# procura aqui não é detalhe, é forma — onde está a frente, onde ela vai, e se
# sobrou casa de pé do outro lado do mapa.
func _draw_minimap() -> void:
	var rect := _minimap_rect()
	var scale := float(Layout.minimap_scale(mission.sim.cols, mission.sim.rows))
	_panel(Rect2(rect.position - Vector2(4, 4), rect.size + Vector2(8, 8)))
	var sim := mission.sim
	for y in sim.rows:
		for x in sim.cols:
			var idx := sim.index_of(x, y)
			var color := Color("3f6b3a")
			match sim.kind[idx]:
				Terrain.WATER: color = C_WATER
				Terrain.ROCK: color = Color("6b6b74")
				Terrain.DIRT: color = Color("8a6b4a")
				Terrain.BRUSH: color = Color("4f7a3a")
				Terrain.TREE: color = Color("2c5230")
				Terrain.FIELD: color = Color("7a8a3a")
			if sim.state[idx] == FireSim.BURNT:
				color = C_BURNT
			elif sim.state[idx] == FireSim.BURNING:
				color = C_FLAME[1]
			elif sim.kind[idx] == Terrain.HOUSE:
				color = C_TEXT
			draw_rect(Rect2(rect.position + Vector2(x, y) * scale, Vector2(scale, scale)), color)

	# retângulo do que está na tela: é o que transforma o minimapa em navegação
	var view := Rect2(camera / CELL * scale + rect.position,
		Layout.viewport_rect().size / CELL * scale)
	draw_rect(view, Color(1, 1, 1, 0.75), false, 1.0)

func _draw_top_strip() -> void:
	var strip := Rect2(Layout.BAR_WIDTH, 0, Layout.VIEWPORT.x - Layout.BAR_WIDTH, Layout.TOP_HEIGHT)
	_panel(strip)

	_draw_compass(Vector2(Layout.BAR_WIDTH + 44, Layout.TOP_HEIGHT * 0.5))

	var sim := mission.sim
	var x := Layout.BAR_WIDTH + 96.0
	var standing := sim.houses_standing()
	var goal := mission.goal_houses()
	_text(Vector2(x, 28), "CASAS", 14, C_DIM)
	_text(Vector2(x, 54), "%d/%d" % [standing, sim.houses_total()], 24,
		C_GOOD if standing > goal else (C_TEXT if standing == goal else C_BAD))
	_text(Vector2(x + 62, 54), "meta %d" % goal, 14, C_DIM)

	x += 150.0
	if mission.agents.civilians_total() > 0:
		_text(Vector2(x, 28), "GENTE", 14, C_DIM)
		_text(Vector2(x, 54), "%d/%d" % [mission.agents.safe_count, mission.agents.civilians_total()], 24,
			C_GOOD if mission.agents.safe_count == mission.agents.civilians_total() else C_TEXT)
		x += 120.0

	_text(Vector2(x, 28), "TEMPO", 14, C_DIM)
	_text(Vector2(x, 54), "%d:%02d" % [int(mission.elapsed) / 60, int(mission.elapsed) % 60], 24, C_TEXT)

	x += 110.0
	_text(Vector2(x, 28), "FOGO", 14, C_DIM)
	_text(Vector2(x, 54), "%d" % sim.burning_count(), 24, C_FLAME[1])

	# canto direito: os interruptores
	var right := Layout.VIEWPORT.x - 14.0
	_text(Vector2(right - 250, 26), "TAB risco: %s" % ("ligado" if show_risk else "desligado"), 14,
		C_TOOL_ON if show_risk else C_DIM)
	_text(Vector2(right - 250, 46), "F velocidade: %d×" % int(mission.speed()), 14, C_DIM)
	_text(Vector2(right - 110, 26), "B demonstração", 14, C_TOOL_ON if bot_active else C_DIM)
	_text(Vector2(right - 110, 46), "R recomeçar", 14, C_DIM)

	if _notice != "":
		var box := Rect2(Layout.BAR_WIDTH + 20, Layout.TOP_HEIGHT + 12, 420, 32)
		_panel(box, Color(0.1, 0.06, 0.05, 0.92))
		_text(box.position + Vector2(12, 22), _notice, 16, C_BAD)

# A bússola. Grande de propósito: é o único elemento do HUD que responde a uma
# pergunta que decide a partida ("de que lado vou perder primeiro?"), e ela
# gira de verdade — inclusive a oscilação lenta do vento, que é o que faz o
# jogador voltar a olhar de tempos em tempos.
func _draw_compass(center: Vector2) -> void:
	var wind := mission.sim.current_wind()
	var force := wind.length()
	draw_circle(center, 30.0, Color(0.09, 0.07, 0.06, 1.0))
	draw_arc(center, 30.0, 0.0, TAU, 32, C_PANEL_EDGE, 2.0)
	if force <= 0.02:
		_text_center(center.x, center.y + 5, "calmo", 14, C_DIM)
		_text_center(center.x, Layout.TOP_HEIGHT - 4, "VENTO", 12, C_DIM)
		return
	var direction := wind.normalized()
	var tip := center + direction * (12.0 + force * 16.0)
	var side := direction.orthogonal() * 8.0
	var tail := center - direction * 12.0
	draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]),
		C_TOOL_ON.lerp(C_BAD, clampf(force, 0.0, 1.0)))
	_text_center(center.x, Layout.TOP_HEIGHT - 4, "VENTO %d%%" % int(force * 100.0), 12, C_DIM)

func _wrap(text: String, columns: int) -> Array:
	var lines: Array = []
	var current := ""
	for word in text.split(" "):
		if current.length() + word.length() + 1 > columns:
			lines.append(current)
			current = word
		else:
			current = word if current == "" else current + " " + word
	if current != "":
		lines.append(current)
	return lines

# ---- painéis de tela cheia ----

func _draw_briefing() -> void:
	var rect := Rect2(Layout.BAR_WIDTH + 60, 150, Layout.VIEWPORT.x - Layout.BAR_WIDTH - 120, 380)
	_panel(rect, Color(0.06, 0.05, 0.05, 0.95))
	var x := rect.position.x + 28.0
	var y := rect.position.y + 52.0
	_text(Vector2(x, y), String(mission.level["name"]), 34, C_TOOL_ON)
	y += 42.0
	for line in _wrap(String(mission.level["brief"]), 62):
		_text(Vector2(x, y), line, 19, C_TEXT)
		y += 26.0
	y += 14.0
	_text(Vector2(x, y), "O QUE ESTA FASE ENSINA", 14, C_DIM)
	y += 24.0
	for line in _wrap(String(mission.level["teaches"]), 62):
		_text(Vector2(x, y), line, 18, C_GOOD)
		y += 24.0

	y += 18.0
	_text(Vector2(x, y), "Salvar pelo menos %d de %d casas%s." % [
		mission.goal_houses(), mission.sim.houses_total(),
		"" if mission.agents.civilians_total() == 0 else " e tirar %d pessoa(s) do vale" % mission.agents.civilians_total()
	], 18, C_TEXT)
	y += 30.0
	_text(Vector2(x, y), "Clique numa célula pra mandar um brigadista. Ele leva tempo pra chegar.", 16, C_DIM)
	y += 24.0
	_text(Vector2(x, y), "TAB mostra em quanto tempo o fogo chega a cada lugar.", 16, C_DIM)

	_text_center(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - 22.0,
		"ENTER ou clique pra começar", 20, C_TOOL_ON)

func _draw_result() -> void:
	var won := mission.phase == Mission.WON
	var rect := Rect2(Layout.BAR_WIDTH + 120, 170, Layout.VIEWPORT.x - Layout.BAR_WIDTH - 240, 340)
	_panel(rect, Color(0.06, 0.05, 0.05, 0.95))
	var center_x := rect.position.x + rect.size.x * 0.5
	var y := rect.position.y + 56.0
	_text_center(center_x, y, "O fogo apagou" if won else "O vale se perdeu", 34, C_GOOD if won else C_BAD)
	y += 34.0
	_text_center(center_x, y, mission.outcome, 18, C_DIM)

	y += 46.0
	var summary := mission.summary()
	_text_center(center_x, y, "%d de %d casas de pé" % [summary["houses"], summary["houses_total"]], 20, C_TEXT)
	y += 28.0
	if summary["civilians"] > 0:
		_text_center(center_x, y, "%d de %d pessoas a salvo" % [summary["saved"], summary["civilians"]], 20, C_TEXT)
		y += 28.0
	_text_center(center_x, y, "%d células queimadas em %d:%02d" % [
		summary["burnt"], int(mission.elapsed) / 60, int(mission.elapsed) % 60], 18, C_DIM)

	y += 44.0
	if won:
		var stars: int = summary["stars"]
		var line := ""
		for i in 3:
			line += "★ " if i < stars else "☆ "
		_text_center(center_x, y, line, 30, C_TOOL_ON)

	var last := level_index + 1 >= Levels.count()
	_text_center(center_x, rect.position.y + rect.size.y - 24.0,
		("ENTER: recomeçar · R: recomeçar" if not won else
		("ENTER: fase seguinte · R: repetir" if not last else "ENTER: jogar de novo")), 18, C_TOOL_ON)
