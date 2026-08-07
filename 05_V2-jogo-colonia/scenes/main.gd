extends Node2D

# "Colônia Viva V2" — o mesmo jogo do Projeto 5, com os MORADORES no centro.
#
# O V1 provou o layout (mundo em tela cheia, loja em gaveta) e a simulação
# (cada morador decide sozinho, e construção sem gente não produz). O que ele
# não tinha era gente: os moradores eram sprites parados que se teletransportavam
# em linha reta, todos com a mesma cara e a mesma postura.
#
# Este projeto existe pra resolver exatamente isso — economia, eras e layout
# ficam como estavam de propósito:
#
#   * **Andar é andar.** Ciclo de passos, braços que balançam, quatro direções,
#     e rota que contorna as casas em vez de atravessá-las (Pathfinder).
#   * **Trabalhar tem gesto.** Machado, picareta, enxada, martelo ou livro,
#     conforme a construção — e a ferramenta gira de verdade na mão.
#   * **Cada um é um.** Pele, camisa, cabelo, barba e chapéu sorteados e
#     recoloridos por morador (VillagerArt), salvos junto com ele.
#   * **A cara conta.** Fome, cansaço e humor viram expressão no rosto.
#   * **Mais o que fazer.** Conversar, passear, carregar a produção até o
#     celeiro, levantar obra, comemorar a virada de era.
#   * **O vale reage.** Trilhas de terra se abrem sozinhas onde a colônia mais
#     pisa, chaminé solta fumaça, lavoura cresce, fogueira treme, pássaros passam.
#
# A cena cuida de mundo, UI e persistência. A matemática fica em Economy, a
# simulação dos moradores em Population, as posições do vale em Valley, a
# navegação em Pathfinder e a arte do morador em VillagerArt — nenhuma delas
# depende de cena, então dá pra testar tudo headless.

const SAVE_KEY := "colonia_v2"
const AUTOSAVE_INTERVAL := 10.0
const BUY_MULTIPLIERS := [1, 10, 25]

# A geometria do vale mora em Valley (scripts/valley.gd) — a cena desenha e a
# Population caminha usando a MESMA tabela de posições.
const TILE := Valley.TILE
const WORLD_SCALE := Valley.SCALE
const CELL := Valley.CELL
const WORLD_COLS := Valley.COLS
const WORLD_ROWS := Valley.ROWS
const PLAZA_RECT := Valley.PLAZA_RECT
const PLOT_CELLS := Valley.PLOT_CELLS
const DECOR_MAX_ROW := Valley.DECOR_MAX_ROW
# Duas linhas na tira do topo (estado da colônia + ações) em vez de botões
# flutuando sobre o mundo: qualquer coisa que flutue no rodapé acaba cobrindo
# os moradores dos lotes de baixo, que é exatamente o que este jogo não pode
# esconder.
const HUD_HEIGHT := 100
const DRAWER_WIDTH := 470

const TOWN_TEXTURE_PATH := "res://assets/town/tilemap_packed.png"
# Tileset do Projeto 2 (roguelike), reaproveitado nos ícones das eras primitivas.
const DUNGEON_TEXTURE_PATH := "res://assets/dungeon/tilemap_packed.png"

# --- tiles do Kenney Tiny Town (coordenadas conferidas no sheet) ---
# Grama lisa pesa mais que grama florida: o chão é fundo, não protagonista —
# encher tudo de flor deixa a tela ruidosa e some com quem anda em cima.
const T_GRASS := [
	Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(2, 0),
]
# Retalho de terra com borda de grama: 3×3 (canto/lado/centro).
const T_DIRT := [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	[Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)],
	[Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3)],
]
# Decoração de uma célula só (árvore pequena, arbusto, broto, cogumelo).
const T_DECOR := [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2)]
# Chão pisado de lote construído (grama com pedras): marca "aqui tem obra".
const T_PLOT_FLOOR := Vector2i(7, 3)
# Tonéis e caixas nos cantos da praça (célula relativa ao canto do PLAZA_RECT).
const T_PLAZA_PROPS := [
	{"cell": Vector2i(0, 0), "tile": Vector2i(10, 8)},
	{"cell": Vector2i(5, 0), "tile": Vector2i(11, 8)},
	{"cell": Vector2i(0, 3), "tile": Vector2i(11, 7)},
	{"cell": Vector2i(5, 3), "tile": Vector2i(10, 8)},
]

# Construções são CASAS de 2×2 tiles montadas do tileset (telhado em cima,
# parede com porta embaixo) — não o ícone de 16px solto que o 04 usava. No
# 04 a vila era uma tirinha de ícones; aqui ela ocupa a tela, e ícone solto
# em cima da grama lê como "item largado no chão", não como colônia.
# O ícone da função vira uma placa ao lado da porta.
const HOUSE_STYLES := {
	# Era 0 não tem casa: é acampamento (só o chão pisado e a placa da função).
	"acampamento": {},
	"madeira": {"roof": [Vector2i(0, 4), Vector2i(2, 4)], "base": [Vector2i(0, 7), Vector2i(1, 7)]},
	"telha": {"roof": [Vector2i(4, 4), Vector2i(6, 4)], "base": [Vector2i(2, 7), Vector2i(3, 7)]},
	"pedra": {"roof": [Vector2i(4, 4), Vector2i(6, 4)], "base": [Vector2i(4, 7), Vector2i(5, 7)]},
}

static func house_style_for(era_index: int) -> String:
	if era_index == 0:
		return "acampamento"
	if era_index <= 2:
		return "madeira"
	if era_index == 3:
		return "telha"
	return "pedra"

# Árvore alta: copa (linha de cima) + copa-com-tronco (linha de baixo). Usar só
# a metade de cima, como eu fazia antes, deixa a árvore visivelmente cortada.
const T_TREE_TOP := [Vector2i(3, 0), Vector2i(4, 0)]
const T_TREE_BOTTOM := [Vector2i(3, 1), Vector2i(4, 1)]

# Cada era tinge o mundo inteiro (mesmo tileset, clima diferente) em vez de
# trocar a arte — o custo é zero e a leitura de "outra época" continua.
const ERA_TINTS := [
	Color("a89b76"), Color("d6ea9c"), Color("b6d6bc"), Color("ab9d90"), Color("c6d4e6"),
]
const ERA_SKIES := [
	Color("2a2118"), Color("1e2a1c"), Color("1c2230"), Color("2a1e22"), Color("161d2b"),
]

const STARTING_VILLAGERS := 5

# Os moradores não escolhem mais um sprite de um elenco fixo: o sheet
# "Roguelike Characters" é um paper doll modular, e cada morador é uma
# combinação própria de pele, camisa, cabelo, barba e chapéu, montada e
# recolorida em VillagerArt. A cena só empresta a textura do sheet (pras
# ferramentas na mão) e o tamanho na tela.
const CHAR_TEXTURE_PATH := VillagerArt.SHEET_PATH
const CHAR_TILE := VillagerArt.TILE
const VILLAGER_SCALE := VillagerView.SCALE
const VILLAGER_BODY := Color("f2d0a4")   # cor de referência do morador no HUD

const STATE_LABELS := {
	"idle": "à toa", "walking": "a caminho", "working": "trabalhando",
	"eating": "comendo", "resting": "descansando", "socializing": "conversando",
	"celebrating": "comemorando", "building": "levantando obra",
}

# ---- arredores (V2) ----
# Terra pisada das trilhas que os moradores abrem sozinhos andando sempre pelo
# mesmo lugar (ver Pathfinder). Duas variações pra estrada não ficar lisa.
const T_TRAIL := [Vector2i(4, 3), Vector2i(5, 3)]
# Brotos: a lavoura ao redor das construções de comida, em três estágios.
const T_CROPS := [Vector2i(5, 1), Vector2i(5, 0), Vector2i(4, 2)]
# Poço, celeiro e cerca da praça.
const T_BUCKET := Vector2i(8, 8)
const T_STONE_FLOOR := Vector2i(7, 3)
const T_BARRELS := [Vector2i(10, 8), Vector2i(11, 8), Vector2i(8, 7)]
const T_FENCE_POST := Vector2i(11, 3)

# Construções que plantam: ganham lavoura em volta do lote.
const FARMING_BUILDINGS := ["coletor", "fazenda", "mercado", "agroindustria"]

const SMOKE_BUILDINGS := ["lascador", "oleiro", "fabrica", "moinho_vapor", "usina"]

const BIRD_COUNT := 3
# +1 pelo anel de seleção, que também mora em effects_root e nunca sai.
const MAX_FLOATING_TEXTS := 7

const RESOURCE_LABELS := {
	"comida": "Comida",
	"materiais": "Materiais",
	"conhecimento": "Conhecimento",
}
const RESOURCE_COLORS := {
	"comida": Color("8fd17a"),
	"materiais": Color("d8a45c"),
	"conhecimento": Color("7ab8f0"),
}

var economy := Economy.new()
var population := Population.new()
var state_machine: StateMachine
var _autosave_clock := 0.0
var _villager_nodes: Dictionary = {}   # id do Villager -> VillagerView no mundo

var _town_texture: Texture2D
var _dungeon_texture: Texture2D
var _char_texture: Texture2D

var world_root: Node2D          # tudo que é "mundo" (chão, lotes, moradores)
var ground_layer: TileMapLayer
var trail_layer: TileMapLayer
var decor_root: Node2D
var landmarks_root: Node2D
var plots_root: Node2D
var villagers_root: Node2D
var effects_root: Node2D
var sky_root: Node2D

var _trail_signature := -1
var _ambience_clock := 0.0
var _fire_sprites: Array = []
var _crop_sprites: Array = []
var _birds: Array = []
var _granary_barrels: Array = []
var _inspected_id := 0

var ui_root: Control
var sky: ColorRect
var era_label: Label
var era_progress: ProgressBar
var message_label: Label
var inspector_label: RichTextLabel
var selection_ring: Sprite2D
var resource_chips: Dictionary = {}   # recurso -> {"amount","rate"}
var population_count_label: Label
var population_detail_label: Label
var population_mood_label: Label
var gather_row: HBoxContainer
var drawer: PanelContainer
var drawer_button: Button
var drawer_open := false
var _drawer_tween: Tween
var buildings_box: VBoxContainer
var building_rows: Dictionary = {}    # id -> {"root","title","cost","button"}
var buy_multiplier := 1
var buy_multiplier_buttons: Dictionary = {}
var advance_button: Button
var advance_hint: RichTextLabel
var era_overlay: CenterContainer
var era_overlay_title: Label
var era_overlay_text: Label

func _ready() -> void:
	_town_texture = load(TOWN_TEXTURE_PATH)
	_dungeon_texture = load(DUNGEON_TEXTURE_PATH)
	_char_texture = load(CHAR_TEXTURE_PATH)
	_build_world()
	_build_hud()
	_build_drawer()
	_build_era_overlay()
	_setup_state_machine()
	load_game()

func _setup_state_machine() -> void:
	state_machine = StateMachine.new()
	for i in Eras.count():
		var state := EraState.new()
		state.name = "Era%d" % i
		state.era_index = i
		state.game = self
		state_machine.add_child(state)
	add_child(state_machine)

# ---- ciclo ----

func _process(delta: float) -> void:
	# Ordem importa: os moradores decidem/andam PRIMEIRO, e só então a economia
	# rende — a produção de cada construção é multiplicada pela fração das vagas
	# realmente ocupadas por alguém trabalhando agora. Colônia sem gente não
	# produz nada, e é essa a diferença entre este jogo e um clicker.
	population.tick(delta, economy)
	economy.tick(delta, population.staffing_ratios())
	_sync_villager_nodes()
	_handle_population_events()
	_animate_ambience(delta)
	_refresh_trails()

	_autosave_clock += delta
	if _autosave_clock >= AUTOSAVE_INTERVAL:
		_autosave_clock = 0.0
		save_game()
	_update_hud()

func gather(resource: String) -> void:
	if economy.gather(resource):
		set_message("+%s de %s" % [Economy.format_amount(economy.click_yield()), RESOURCE_LABELS[resource].to_lower()])
		_update_hud()

func _buy_amount(id: String) -> int:
	if buy_multiplier == -1:
		return economy.max_affordable(id)
	return buy_multiplier

func buy(id: String) -> void:
	var n := maxi(_buy_amount(id), 1)
	if not economy.buy_n(id, n):
		set_message("A colônia ainda não tem recursos para %s." % Buildings.find(id).name)
		return
	set_message("%s: agora são %d. As vagas de trabalho abriram." % [Buildings.find(id).name, economy.count_of(id)])
	population.sync_work_sites(economy)
	population.assign_jobs()
	# Clicar em "Construir" tem que acontecer NO VALE, não só na lista: uma
	# turma larga o que estava fazendo e vai levantar a obra.
	population.start_construction(id)
	_rebuild_plots()
	_update_hud()
	save_game()

func set_buy_multiplier(value: int) -> void:
	buy_multiplier = value
	for key in buy_multiplier_buttons:
		buy_multiplier_buttons[key].button_pressed = (key == value)
	_update_hud()

func advance_era() -> void:
	if not economy.advance():
		set_message("A colônia ainda não reuniu o que essa virada exige.")
		return
	state_machine.transition_to("Era%d" % economy.era_index)
	save_game()

func on_era_entered(era_index: int) -> void:
	paint_era(era_index)
	_build_gather_buttons(Eras.era(era_index))
	_build_building_rows()
	_rebuild_plots()
	_update_hud()

	if era_index > 0:
		population.celebrate()
	if era_index > 0:
		var era := Eras.era(era_index)
		era_overlay_title.text = era.name
		era_overlay_text.text = "%s\n\nNovas construções: %s" % [era.subtitle, ", ".join(_unlocked_names(era_index))]
		era_overlay.visible = true
	set_message(Eras.era(era_index).subtitle)

func close_era_overlay() -> void:
	era_overlay.visible = false

func _unlocked_names(era_index: int) -> Array:
	var names := []
	for building in Buildings.unlocked_in(era_index):
		names.append(building.name)
	return names

# ---- persistência ----

func save_game() -> void:
	var data := economy.to_dict()
	data["saved_at"] = Time.get_unix_time_from_system()
	data["population"] = population.to_dict()
	SaveSystem.set_value(SAVE_KEY, data)
	SaveSystem.save_data()

func load_game() -> void:
	var data = SaveSystem.get_value(SAVE_KEY, {})
	var offline_seconds := 0.0
	if data is Dictionary and not data.is_empty():
		economy.from_dict(data)
		var saved_population = data.get("population", {})
		if saved_population is Dictionary and not saved_population.is_empty():
			population.from_dict(saved_population, economy)
		var saved_at := float(data.get("saved_at", 0.0))
		if saved_at > 0.0:
			offline_seconds = maxf(0.0, Time.get_unix_time_from_system() - saved_at)

	population.sync_work_sites(economy)
	# A colônia nunca fica vazia: mesmo sem nenhuma construção existe um punhado
	# de gente na praça — são eles que dão o que olhar antes da primeira compra.
	population.ensure_minimum(STARTING_VILLAGERS)
	population.assign_jobs()

	state_machine.transition_to("Era%d" % economy.era_index)

	if offline_seconds >= 60.0:
		var result := economy.apply_offline(offline_seconds)
		population.apply_offline_catchup(offline_seconds, economy)
		set_message("Enquanto você esteve fora (%d min), a colônia seguiu trabalhando." % int(result.seconds / 60.0))
		_update_hud()

func reset_game() -> void:
	economy = Economy.new()
	population = Population.new()
	# Os bonecos são donos de textura assada; deixar os antigos pendurados aqui
	# vazaria memória e ainda mostraria gente que não existe mais.
	for id in _villager_nodes.keys():
		_villager_nodes[id].queue_free()
	_villager_nodes.clear()
	_inspected_id = 0
	population.ensure_minimum(STARTING_VILLAGERS)
	SaveSystem.set_value(SAVE_KEY, {})
	SaveSystem.save_data()
	state_machine.transition_to("Era0")

# ---- moradores na tela ----

# Um boneco por morador, criado sob demanda e reaproveitado entre frames: a
# simulação (Population) é dona da posição/estado, a cena só espelha. O boneco
# é articulado (VillagerView) e a textura dele é assada na hora do nascimento,
# a partir da aparência sorteada — por isso a criação é o único momento caro,
# e ele é raro.
func _sync_villager_nodes() -> void:
	var seen := {}
	for v in population.villagers:
		seen[v.id] = true
		var view: VillagerView = _villager_nodes.get(v.id)
		if view == null:
			view = VillagerView.create(v, _char_texture, _town_texture)
			villagers_root.add_child(view)
			_villager_nodes[v.id] = view
		# O jeito de trabalhar vem da construção onde ele está empregado: é o
		# que troca o machado por picareta, enxada, martelo ou livro.
		view.set_work_kind(v.work_kind())
		view.sync(v)

	for id in _villager_nodes.keys():
		if not seen.has(id):
			_villager_nodes[id].queue_free()
			_villager_nodes.erase(id)

# ---- o que acontece quando alguém termina uma tarefa ----

# A Population enfileira acontecimentos e a cena os transforma em coisa vista:
# entrega no celeiro vira um "+recurso" subindo, obra e festa viram recado.
func _handle_population_events() -> void:
	for event in population.drain_events():
		match String(event.get("type", "")):
			"entrega":
				var resource := String(event.get("resource", ""))
				_spawn_floating_text(
					Valley.granary() + Vector2(0, -26),
					"+%s" % RESOURCE_LABELS.get(resource, resource).to_lower(),
					RESOURCE_COLORS.get(resource, Color.WHITE)
				)
			"obra":
				set_message("Uma turma foi levantar %s." % Buildings.find(String(event.get("building", ""))).get("name", "a obra"))
			"nascimento":
				_spawn_floating_text(Vector2(event.get("position", Vector2.ZERO)) + Vector2(0, -50), "nasceu", Color("ffd9a0"))

# Texto que sobe e some: o feedback mais barato que existe e o único que não
# rouba espaço da tela (a regra do projeto é nada de painel flutuante fixo).
# Com teto de quantos existem ao mesmo tempo: numa colônia grande nascem e
# entregam várias coisas por segundo, e sem o teto o vale some atrás de texto.
func _spawn_floating_text(at: Vector2, text: String, color: Color) -> void:
	if effects_root.get_child_count() > MAX_FLOATING_TEXTS:
		return
	var label := Label.new()
	label.theme = UITheme.theme
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = at
	effects_root.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", at.y - 34.0, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)

# ---- mundo ----

func _build_world() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)

	sky = ColorRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.add_child(sky)

	world_root = Node2D.new()
	world_root.name = "Mundo"
	world_root.position = Vector2(0, HUD_HEIGHT)
	add_child(world_root)

	ground_layer = TileMapLayer.new()
	ground_layer.name = "Chao"
	ground_layer.tile_set = _build_tileset(_town_texture)
	ground_layer.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	ground_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_root.add_child(ground_layer)

	# Camada própria pras trilhas: elas mudam com o tempo (aparecem onde se
	# pisa, somem onde não se pisa mais) e não dá pra sujar o chão fixo com isso.
	trail_layer = TileMapLayer.new()
	trail_layer.name = "Trilhas"
	trail_layer.tile_set = ground_layer.tile_set
	trail_layer.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	trail_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Translúcida: a trilha é grama gasta, não terra arada. Opaca demais, o
	# caminho vira uma cicatriz que compete com as construções.
	trail_layer.modulate = Color(1, 1, 1, 0.5)
	world_root.add_child(trail_layer)

	decor_root = Node2D.new()
	decor_root.name = "Decoracao"
	world_root.add_child(decor_root)

	landmarks_root = Node2D.new()
	landmarks_root.name = "Marcos"
	world_root.add_child(landmarks_root)

	plots_root = Node2D.new()
	plots_root.name = "Lotes"
	world_root.add_child(plots_root)

	villagers_root = Node2D.new()
	villagers_root.name = "Moradores"
	# Quem está mais embaixo na tela desenha na frente: sem isto, um morador ao
	# sul de outro pode aparecer atrás dele e a multidão fica com profundidade
	# invertida.
	villagers_root.y_sort_enabled = true
	world_root.add_child(villagers_root)

	effects_root = Node2D.new()
	effects_root.name = "Efeitos"
	world_root.add_child(effects_root)

	selection_ring = Sprite2D.new()
	selection_ring.name = "Selecao"
	selection_ring.texture = _ring_texture()
	selection_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	selection_ring.scale = Vector2(3, 3)
	selection_ring.visible = false
	effects_root.add_child(selection_ring)

	sky_root = Node2D.new()
	sky_root.name = "Ceu"
	world_root.add_child(sky_root)

	_paint_ground()
	_paint_decor()
	_build_landmarks()
	_build_birds()

# TileSet montado 100% em código (mesma técnica do Projeto 2): evita ter que
# configurar o atlas no editor e mantém tudo num arquivo de textura só.
func _build_tileset(texture: Texture2D) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)
	var cols := int(texture.get_width() / TILE)
	var rows := int(texture.get_height() / TILE)
	for c in cols:
		for r in rows:
			source.create_tile(Vector2i(c, r))
	tileset.add_source(source, 0)
	return tileset

func _paint_ground() -> void:
	# Semente fixa: o vale é sempre o mesmo entre sessões (é a colônia DELE,
	# não um mapa novo a cada abertura).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805

	for y in WORLD_ROWS:
		for x in WORLD_COLS:
			ground_layer.set_cell(Vector2i(x, y), 0, T_GRASS[rng.randi_range(0, T_GRASS.size() - 1)])

	for y in PLAZA_RECT.size.y:
		for x in PLAZA_RECT.size.x:
			var row := 0 if y == 0 else (2 if y == PLAZA_RECT.size.y - 1 else 1)
			var col := 0 if x == 0 else (2 if x == PLAZA_RECT.size.x - 1 else 1)
			ground_layer.set_cell(PLAZA_RECT.position + Vector2i(x, y), 0, T_DIRT[row][col])

func _paint_decor() -> void:
	for child in decor_root.get_children():
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var taken := {}
	for cell in PLOT_CELLS:
		# Os 2×2 do lote (mais uma folga em volta) ficam livres de decoração.
		for dx in range(-1, 3):
			for dy in range(-1, 3):
				taken[cell + Vector2i(dx, dy)] = true
	for y in PLAZA_RECT.size.y:
		for x in PLAZA_RECT.size.x:
			taken[PLAZA_RECT.position + Vector2i(x, y)] = true

	# Bosque nas bordas + mato solto no meio: dá profundidade ao vale sem
	# competir com os moradores, que vivem na faixa central.
	var placed := 0
	var attempts := 0
	while placed < 30 and attempts < 600:
		attempts += 1
		var cell := Vector2i(rng.randi_range(0, WORLD_COLS - 1), rng.randi_range(0, DECOR_MAX_ROW))
		var tall: bool = rng.randf() < 0.45 and cell.y >= 1
		var footprint := [cell, cell + Vector2i(0, -1)] if tall else [cell]
		var free := true
		for c in footprint:
			if taken.has(c):
				free = false
		if not free:
			continue
		for c in footprint:
			taken[c] = true

		if tall:
			var pick := rng.randi_range(0, T_TREE_TOP.size() - 1)
			var top := _make_sprite("town", T_TREE_TOP[pick])
			top.position = Vector2(cell + Vector2i(0, -1)) * CELL
			decor_root.add_child(top)
			var bottom := _make_sprite("town", T_TREE_BOTTOM[pick])
			bottom.position = Vector2(cell) * CELL
			decor_root.add_child(bottom)
		else:
			var sprite := _make_sprite("town", T_DECOR[rng.randi_range(0, T_DECOR.size() - 1)])
			sprite.position = Vector2(cell) * CELL
			decor_root.add_child(sprite)
		placed += 1

	# Tonéis soltos nos cantos livres da praça (fogueira, poço e celeiro têm
	# lugar próprio agora — ver _build_landmarks).
	for offset in T_PLAZA_PROPS:
		var cell: Vector2i = PLAZA_RECT.position + offset.cell
		if cell == Valley.HEARTH_CELL or cell == Valley.WELL_CELL or cell == Valley.GRANARY_CELL:
			continue
		var prop := _make_sprite("town", offset.tile)
		prop.position = Vector2(cell) * CELL
		decor_root.add_child(prop)

# ---- marcos do vale (V2) ----
#
# No V1 a praça era um retângulo de terra e TODAS as ações que não fossem
# trabalho aconteciam nele. Aqui ela tem endereços: a fogueira onde se come, o
# poço, e o celeiro onde a produção é entregue. Isso não muda regra nenhuma do
# jogo — muda o que o olho entende quando bate na tela: as pessoas vão a
# lugares, em vez de flutuarem para coordenadas.
func _build_landmarks() -> void:
	_build_hearth()
	_build_well()
	_build_granary()

func _build_hearth() -> void:
	var origin: Vector2 = Vector2(Valley.HEARTH_CELL) * CELL
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var floor_tile := _make_sprite("town", T_STONE_FLOOR)
			floor_tile.position = origin + Vector2(dx, dy) * CELL
			floor_tile.modulate = Color(1, 1, 1, 0.7)
			landmarks_root.add_child(floor_tile)

	# Brilho quente por baixo: é o que faz a fogueira parecer acesa em vez de
	# um ícone de fogo colado na grama.
	var glow := Sprite2D.new()
	glow.name = "BrilhoFogueira"
	glow.texture = _radial_texture(48, Color(1.0, 0.72, 0.35))
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.position = origin + Vector2(CELL, CELL) * 0.5
	glow.scale = Vector2(2.6, 2.0)
	glow.modulate = Color(1, 1, 1, 0.45)
	landmarks_root.add_child(glow)

	# A fogueira é desenhada aqui, não tirada de tile: o único "fogo" dos dois
	# tilesets é a tocha de parede do Tiny Dungeon, que sobre a grama lê como
	# uma bandeira escura, não como uma fogueira comunal.
	var fire := Sprite2D.new()
	fire.name = "Fogueira"
	fire.texture = _campfire_texture()
	fire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fire.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	fire.centered = false
	fire.position = origin
	landmarks_root.add_child(fire)

	_fire_sprites = [fire, glow]

func _build_well() -> void:
	var origin: Vector2 = Vector2(Valley.WELL_CELL) * CELL
	var base := _make_sprite("town", T_STONE_FLOOR)
	base.position = origin
	landmarks_root.add_child(base)
	for dx in [-1, 1]:
		var post := _make_sprite("town", T_FENCE_POST, 2)
		post.position = origin + Vector2(CELL * 0.5 + dx * 20 - 16, 6)
		landmarks_root.add_child(post)
	var bucket := _make_sprite("town", T_BUCKET, 2)
	bucket.position = origin + Vector2(CELL * 0.5 - 16, 10)
	landmarks_root.add_child(bucket)

# O celeiro cresce: quanto mais a colônia guarda, mais tonel aparece. É o
# estoque virando coisa que se vê no vale, não só número na tira do topo.
func _build_granary() -> void:
	var origin: Vector2 = Vector2(Valley.GRANARY_CELL) * CELL
	for dx in 2:
		var floor_tile := _make_sprite("town", T_STONE_FLOOR)
		floor_tile.position = origin + Vector2(dx - 1, 0) * CELL
		floor_tile.modulate = Color(1, 1, 1, 0.7)
		landmarks_root.add_child(floor_tile)

	_granary_barrels.clear()
	var spots := [Vector2(-30, 4), Vector2(4, 0), Vector2(-14, 18), Vector2(24, 12), Vector2(-38, 20)]
	for i in spots.size():
		var barrel := _make_sprite("town", T_BARRELS[i % T_BARRELS.size()], 2)
		barrel.position = origin + spots[i]
		barrel.visible = i == 0
		landmarks_root.add_child(barrel)
		_granary_barrels.append(barrel)

func _build_birds() -> void:
	_birds.clear()
	var texture := _bird_texture()
	for i in BIRD_COUNT:
		var bird := Sprite2D.new()
		bird.texture = texture
		bird.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bird.scale = Vector2(2, 2)
		bird.modulate = Color(0.16, 0.17, 0.22, 0.75)
		bird.position = Vector2(-80.0 - i * 420.0, 40.0 + i * 26.0)
		sky_root.add_child(bird)
		_birds.append({"node": bird, "speed": 26.0 + i * 9.0, "base_y": 40.0 + i * 26.0})

# Círculo de luz gerado em memória: uma textura só serve pra fogueira e pra
# qualquer brilho futuro, sem arquivo novo no repositório.
func _radial_texture(size: int, tint: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x - half, y - half).length() / half
			if d <= 1.0:
				var falloff: float = pow(1.0 - d, 2.2)
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, falloff))
	return ImageTexture.create_from_image(img)

# Fogueira 16×16 desenhada como texto: três achas cruzadas e uma chama de três
# tons. Ler o desenho no código vale mais que caçar coordenada em tileset.
func _campfire_texture() -> Texture2D:
	var art := [
		"................",
		"................",
		"................",
		".......A........",
		"......AAA.......",
		".....ABBBA......",
		".....ABCBA......",
		"....ABBCBBA.....",
		"....ABBBBBA.....",
		".....AABAA......",
		"..DEED..DEED....",
		".DEEEEDDEEEED...",
		"..DDEEEEEEDD....",
		"...DEEEEEED.....",
		"................",
		"................",
	]
	var palette := {
		"A": Color("e0632a"), "B": Color("f2a03c"), "C": Color("ffe08a"),
		"D": Color("5a3d24"), "E": Color("8a6238"),
	}
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in art.size():
		var row: String = art[y]
		for x in row.length():
			if palette.has(row[x]):
				img.set_pixel(x, y, palette[row[x]])
	return ImageTexture.create_from_image(img)

func _bird_texture() -> Texture2D:
	var art := ["#...#", ".#.#.", "..#.."]
	var img := Image.create(5, 3, false, Image.FORMAT_RGBA8)
	for y in art.size():
		var row: String = art[y]
		for x in row.length():
			if row[x] == "#":
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

# Anel achatado sob os pés de quem está selecionado (não um retângulo em volta:
# a esta escala, moldura cobre a pessoa que ela deveria destacar).
func _ring_texture() -> Texture2D:
	var w := 20
	var h := 9
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d: float = Vector2((x - (w - 1) * 0.5) / (w * 0.5), (y - (h - 1) * 0.5) / (h * 0.5)).length()
			if d <= 1.0 and d >= 0.66:
				img.set_pixel(x, y, Color("ffe08a"))
	return ImageTexture.create_from_image(img)

# ---- inspecionar um morador ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		inspect_at(event.position - Vector2(0, HUD_HEIGHT))

# Toda a vida interior que o V2 acrescentou (necessidades, ofício, o que a
# pessoa está fazendo agora) precisa de alguma porta de entrada — senão vira
# simulação que só o código conhece. A porta é clicar em quem está na tela.
func inspect_at(world_position: Vector2) -> int:
	var best := 0
	var best_distance := 999999.0
	for v in population.villagers:
		var box := Rect2(v.position + Vector2(-22, -52), Vector2(44, 56))
		if not box.has_point(world_position):
			continue
		var distance: float = v.position.distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = v.id
	_inspected_id = best
	_update_inspector()
	return best

# Barra de cinco traços: o tipo "|" existe em qualquer fonte, então isto não
# depende de a Kenney Pixel ter caractere de bloco.
static func _need_bar(value: float, color: Color) -> String:
	var filled := clampi(int(round(clampf(value, 0.0, 1.0) * 5.0)), 0, 5)
	return "[color=#%s]%s[/color][color=#ffffff33]%s[/color]" % [
		color.to_html(false), "|".repeat(filled), "|".repeat(5 - filled)
	]

func _update_inspector() -> void:
	if inspector_label == null:
		return
	var v: Villager = population.get_villager(_inspected_id) if _inspected_id != 0 else null
	if v == null:
		selection_ring.visible = false
		inspector_label.text = "[color=#ffffff55]Clique num morador para saber quem é.[/color]"
		return

	selection_ring.visible = true
	selection_ring.position = v.position + Vector2(0, -2)

	var job: String = String(Buildings.find(v.job_id).get("name", "")) if v.has_job() else ""
	var doing: String = String(STATE_LABELS.get(v.state, v.state))
	if v.carrying != "":
		doing = "levando %s" % RESOURCE_LABELS.get(v.carrying, v.carrying).to_lower()
	inspector_label.text = "[b]%s[/b] · %s · [i]%s[/i]  %s %s %s" % [
		v.display_name,
		job if job != "" else "sem ofício",
		doing,
		_need_bar(v.hunger, RESOURCE_COLORS["comida"]),
		_need_bar(v.energy, Color("c58fff")),
		_need_bar(v.social, Color("9fd0ff")),
	]

# ---- vida do cenário ----

# Nada aqui muda regra de jogo: é só o vale respirando. Uma colônia onde só os
# moradores se mexem parece um teatro com o cenário desligado.
func _animate_ambience(delta: float) -> void:
	_ambience_clock += delta

	# Fogo: dois batimentos fora de fase, um no sprite e outro no brilho, pra
	# tremer sem parecer um piscar de LED.
	if _fire_sprites.size() == 2:
		var flame: Sprite2D = _fire_sprites[0]
		var glow: Sprite2D = _fire_sprites[1]
		var beat: float = sin(_ambience_clock * 7.3) * 0.5 + sin(_ambience_clock * 11.7) * 0.5
		flame.scale = Vector2(WORLD_SCALE, WORLD_SCALE * (1.0 + beat * 0.06))
		flame.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.85, 0.6), absf(beat) * 0.5)
		glow.modulate.a = 0.38 + beat * 0.09
		glow.scale = Vector2(2.6 + beat * 0.16, 2.0 + beat * 0.12)

	# Lavoura: os brotos passam pelos três estágios em ciclo lento.
	if not _crop_sprites.is_empty():
		var stage: int = int(_ambience_clock / 9.0) % T_CROPS.size()
		for entry in _crop_sprites:
			var sprite: Sprite2D = entry.node
			var coord: Vector2i = T_CROPS[(stage + int(entry.offset)) % T_CROPS.size()]
			sprite.region_rect = Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)

	# Celeiro: mais tonel conforme o estoque da colônia sobe.
	var stored: float = economy.amount("comida") + economy.amount("materiais")
	var visible_barrels: int = clampi(1 + int(log(maxf(stored, 1.0)) / 1.8), 1, _granary_barrels.size())
	for i in _granary_barrels.size():
		_granary_barrels[i].visible = i < visible_barrels

	# Pássaros: atravessam a tela e voltam pelo outro lado.
	var world_width: float = WORLD_COLS * CELL
	for bird in _birds:
		var node: Sprite2D = bird.node
		node.position.x += float(bird.speed) * delta
		node.position.y = float(bird.base_y) + sin(_ambience_clock * 1.4 + float(bird.speed)) * 9.0
		if node.position.x > world_width + 40.0:
			node.position.x = -40.0

# As trilhas mudam devagar; redesenhar só quando a quantidade de células muda
# evita reescrever o TileMapLayer inteiro todo frame.
func _refresh_trails() -> void:
	if population.pathfinder.trails_version == _trail_signature:
		return
	_trail_signature = population.pathfinder.trails_version
	trail_layer.clear()
	for cell in population.pathfinder.trail_cells():
		var pick: int = absi(int(cell.x) * 7 + int(cell.y) * 13) % T_TRAIL.size()
		trail_layer.set_cell(cell, 0, T_TRAIL[pick])

func _texture_for(sheet: String) -> Texture2D:
	return _dungeon_texture if sheet == "dungeon" else _town_texture

func _make_sprite(sheet: String, coord: Vector2i, scale_factor: int = WORLD_SCALE) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _texture_for(sheet)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.centered = false
	return sprite

# Posição em pixels (dentro de world_root) do centro de uma célula.
func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL, CELL) * 0.5

func plaza_center() -> Vector2:
	return Vector2(PLAZA_RECT.position + PLAZA_RECT.size / 2) * CELL

# Cada TIPO de construção ocupa um lote fixo do vale. Comprar mais cópias não
# enche a tela de ícones repetidos (o erro do 04, que virava sopa de sprites):
# o lote ganha um contador e a construção fica plantada onde sempre esteve, pra
# o jogador aprender o mapa da própria colônia.
func _rebuild_plots() -> void:
	for child in plots_root.get_children():
		child.queue_free()
	_crop_sprites.clear()

	for i in Buildings.ALL.size():
		var building: Dictionary = Buildings.ALL[i]
		var count := economy.count_of(building.id)
		if count <= 0:
			continue
		var cell: Vector2i = PLOT_CELLS[i]
		var origin := Vector2(cell) * CELL

		var style: Dictionary = HOUSE_STYLES[house_style_for(int(building.era))]
		var is_camp: bool = style.is_empty()

		# Chão do lote (2×2): terra batida no acampamento, piso de pedra na casa.
		for dx in 2:
			for dy in 2:
				var floor_tile := _make_sprite("town", T_DIRT[1][1] if is_camp else T_PLOT_FLOOR)
				floor_tile.position = origin + Vector2(dx, dy) * CELL
				floor_tile.modulate = Color(1, 1, 1, 0.85)
				plots_root.add_child(floor_tile)

		if not is_camp:
			for dx in 2:
				var roof := _make_sprite("town", style.roof[dx])
				roof.position = origin + Vector2(dx, 0) * CELL
				plots_root.add_child(roof)
				var base := _make_sprite("town", style.base[dx])
				base.position = origin + Vector2(dx, 1) * CELL
				plots_root.add_child(base)

		# O que essa construção faz: grande e no meio do acampamento (é tudo que
		# ele tem), pequeno como placa no canto quando já existe uma casa.
		var icon := _make_sprite(building.sheet, building.icon, 3 if is_camp else 2)
		icon.position = origin + (Vector2(CELL, CELL) * 0.5 if is_camp else Vector2(CELL * 2 - 34, CELL * 2 - 36))
		plots_root.add_child(icon)

		var badge := Label.new()
		badge.theme = UITheme.theme
		badge.text = "×%d" % count
		badge.add_theme_font_size_override("font_size", 18)
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("shadow_offset_x", 2)
		badge.add_theme_constant_override("shadow_offset_y", 2)
		badge.position = origin + Vector2(2, CELL * 2 - 26)
		plots_root.add_child(badge)

		# Quem planta tem lavoura em volta, quem tem forno solta fumaça: a
		# construção passa a dizer o que se faz nela mesmo sem ler a placa.
		if FARMING_BUILDINGS.has(building.id):
			_plant_crops(cell)
		if not is_camp and SMOKE_BUILDINGS.has(building.id):
			_add_chimney(origin)

# Canteiro nas laterais do lote (as células que a decoração já deixa livres).
func _plant_crops(cell: Vector2i) -> void:
	var patches := [
		Vector2i(cell.x - 1, cell.y), Vector2i(cell.x - 1, cell.y + 1),
		Vector2i(cell.x + 2, cell.y), Vector2i(cell.x + 2, cell.y + 1),
	]
	for i in patches.size():
		var patch: Vector2i = patches[i]
		if patch.x < 0 or patch.y < 0 or patch.x >= WORLD_COLS or patch.y >= WORLD_ROWS:
			continue
		var sprite := _make_sprite("town", T_CROPS[0], 2)
		sprite.position = Vector2(patch) * CELL + Vector2(8, 14)
		plots_root.add_child(sprite)
		# Deslocamento por canteiro: a lavoura amadurece em ondas, não toda de
		# uma vez, senão o vale inteiro pisca junto.
		_crop_sprites.append({"node": sprite, "offset": i % T_CROPS.size()})

func _add_chimney(origin: Vector2) -> void:
	var smoke := CPUParticles2D.new()
	smoke.texture = _radial_texture(12, Color(0.85, 0.85, 0.88))
	smoke.amount = 8
	smoke.lifetime = 2.6
	smoke.position = origin + Vector2(CELL * 1.35, 6)
	smoke.direction = Vector2(0.2, -1)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 12.0
	smoke.initial_velocity_max = 22.0
	smoke.gravity = Vector2(4, -6)
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.5
	smoke.color = Color(1, 1, 1, 0.32)
	plots_root.add_child(smoke)

func paint_era(era_index: int) -> void:
	var era := Eras.era(era_index)
	sky.color = ERA_SKIES[clampi(era_index, 0, ERA_SKIES.size() - 1)]
	ground_layer.modulate = ERA_TINTS[clampi(era_index, 0, ERA_TINTS.size() - 1)]
	decor_root.modulate = ground_layer.modulate
	era_label.text = "%s  ·  %d/%d" % [era.name, era_index + 1, Eras.count()]

# ---- HUD (tira fina no topo) ----

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	ui_root = Control.new()
	ui_root.theme = UITheme.theme
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui_root)

	var bar := PanelContainer.new()
	bar.name = "BarraSuperior"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Nada de `bar.size = ...` aqui: com anchors TOP_WIDE, atribuir size mexe no
	# offset e a barra acaba com o DOBRO da largura da tela, jogando o botão da
	# gaveta pra fora do viewport (sem erro nenhum no Output).
	bar.custom_minimum_size = Vector2(0, HUD_HEIGHT)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color("11121c")
	bar_style.border_color = Color("e94560")
	bar_style.border_width_bottom = 3
	bar_style.set_content_margin_all(8)
	bar_style.content_margin_left = 18
	bar_style.content_margin_right = 18
	bar.add_theme_stylebox_override("panel", bar_style)
	ui_root.add_child(bar)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	bar.add_child(lines)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	lines.add_child(row)

	var era_box := VBoxContainer.new()
	era_box.custom_minimum_size = Vector2(215, 0)
	era_box.add_theme_constant_override("separation", 2)
	row.add_child(era_box)

	era_label = Label.new()
	era_label.add_theme_font_size_override("font_size", 26)
	era_box.add_child(era_label)

	era_progress = ProgressBar.new()
	era_progress.custom_minimum_size = Vector2(210, 10)
	era_progress.show_percentage = false
	era_box.add_child(era_progress)

	for resource in Economy.RESOURCES:
		row.add_child(_build_resource_chip(resource))

	row.add_child(_build_population_chip())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	drawer_button = Button.new()
	drawer_button.text = "Construções  ▸"
	drawer_button.custom_minimum_size = Vector2(190, 48)
	drawer_button.pressed.connect(toggle_drawer)
	row.add_child(drawer_button)

	# Segunda linha da tira: coleta manual + o recado do jogo.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	lines.add_child(actions)

	gather_row = HBoxContainer.new()
	gather_row.add_theme_constant_override("separation", 8)
	actions.add_child(gather_row)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	message_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	message_label.clip_text = true
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(message_label)

	# Ficha do morador clicado. Fica NA TIRA, não num painel flutuante: a regra
	# do projeto é que nada cobre o vale, e um cartão pairando sobre a colônia
	# esconderia exatamente a coisa que ele está tentando explicar.
	inspector_label = RichTextLabel.new()
	inspector_label.bbcode_enabled = true
	inspector_label.fit_content = true
	inspector_label.scroll_active = false
	inspector_label.custom_minimum_size = Vector2(470, 26)
	inspector_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inspector_label.add_theme_font_size_override("normal_font_size", 17)
	actions.add_child(inspector_label)

func _build_resource_chip(resource: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150, 0)
	box.add_theme_constant_override("separation", 0)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)

	var dot := ColorRect.new()
	dot.color = RESOURCE_COLORS[resource]
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dot)

	var amount := Label.new()
	amount.text = "0"
	amount.add_theme_font_size_override("font_size", 26)
	amount.add_theme_color_override("font_color", RESOURCE_COLORS[resource])
	top.add_child(amount)

	var caption := Label.new()
	caption.text = RESOURCE_LABELS[resource]
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(caption)

	var rate := Label.new()
	rate.text = "0/s"
	rate.add_theme_font_size_override("font_size", 15)
	rate.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	top.add_child(rate)

	resource_chips[resource] = {"amount": amount, "rate": rate}
	return box

# A colônia é o recurso principal: quantos moradores existem, quantos estão de
# fato trabalhando e como está o humor deles. Fica ao lado dos recursos porque
# é o número que o jogador precisa vigiar, não um detalhe de rodapé.
func _build_population_chip() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(230, 0)
	box.add_theme_constant_override("separation", 0)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)

	var dot := ColorRect.new()
	dot.color = VILLAGER_BODY
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dot)

	population_count_label = Label.new()
	population_count_label.text = "0"
	population_count_label.add_theme_font_size_override("font_size", 26)
	population_count_label.add_theme_color_override("font_color", VILLAGER_BODY)
	top.add_child(population_count_label)

	population_detail_label = Label.new()
	population_detail_label.add_theme_font_size_override("font_size", 15)
	population_detail_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	top.add_child(population_detail_label)

	population_mood_label = Label.new()
	population_mood_label.text = "Moradores"
	population_mood_label.add_theme_font_size_override("font_size", 15)
	population_mood_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(population_mood_label)

	return box

# ---- gaveta de construções ----

func _build_drawer() -> void:
	drawer = PanelContainer.new()
	drawer.name = "Gaveta"
	drawer.size = Vector2(DRAWER_WIDTH, 720 - HUD_HEIGHT)
	drawer.position = Vector2(1280, HUD_HEIGHT)   # fora da tela = fechada
	var style := StyleBoxFlat.new()
	style.bg_color = Color("131522")
	style.border_color = Color("e94560")
	style.border_width_left = 3
	style.set_content_margin_all(16)
	drawer.add_theme_stylebox_override("panel", style)
	ui_root.add_child(drawer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	drawer.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title := Label.new()
	title.text = "Construções"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(48, 40)
	close.pressed.connect(toggle_drawer)
	header.add_child(close)

	var multiplier_row := HBoxContainer.new()
	multiplier_row.add_theme_constant_override("separation", 4)
	column.add_child(multiplier_row)

	var multiplier_caption := Label.new()
	multiplier_caption.text = "Construir"
	multiplier_caption.add_theme_font_size_override("font_size", 16)
	multiplier_caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	multiplier_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	multiplier_row.add_child(multiplier_caption)

	for value in BUY_MULTIPLIERS:
		var button := Button.new()
		button.text = "×%d" % value
		button.toggle_mode = true
		button.button_pressed = value == buy_multiplier
		button.custom_minimum_size = Vector2(52, 34)
		button.pressed.connect(func(): set_buy_multiplier(value))
		multiplier_row.add_child(button)
		buy_multiplier_buttons[value] = button
	var max_button := Button.new()
	max_button.text = "Máx"
	max_button.toggle_mode = true
	max_button.custom_minimum_size = Vector2(52, 34)
	max_button.pressed.connect(func(): set_buy_multiplier(-1))
	multiplier_row.add_child(max_button)
	buy_multiplier_buttons[-1] = max_button

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	buildings_box = VBoxContainer.new()
	buildings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buildings_box.add_theme_constant_override("separation", 6)
	scroll.add_child(buildings_box)

	advance_hint = RichTextLabel.new()
	advance_hint.bbcode_enabled = true
	advance_hint.fit_content = true
	advance_hint.scroll_active = false
	advance_hint.add_theme_font_size_override("normal_font_size", 17)
	column.add_child(advance_hint)

	advance_button = Button.new()
	advance_button.custom_minimum_size = Vector2(0, 50)
	advance_button.pressed.connect(advance_era)
	column.add_child(advance_button)

func _build_gather_buttons(era: Dictionary) -> void:
	for child in gather_row.get_children():
		gather_row.remove_child(child)
		child.queue_free()
	for resource in era.click_resources:
		var button := Button.new()
		button.text = "+ %s" % RESOURCE_LABELS[resource]
		button.custom_minimum_size = Vector2(150, 34)
		var captured: String = resource
		button.pressed.connect(func(): gather(captured))
		gather_row.add_child(button)

func _build_building_rows() -> void:
	for child in buildings_box.get_children():
		buildings_box.remove_child(child)
		child.queue_free()
	building_rows.clear()

	for building in Buildings.ALL:
		var panel := PanelContainer.new()
		panel.visible = economy.is_unlocked(building.id)
		buildings_box.add_child(panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)

		var icon := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = _texture_for(building.sheet)
		atlas.region = Rect2(building.icon.x * TILE, building.icon.y * TILE, TILE, TILE)
		icon.texture = atlas
		icon.custom_minimum_size = Vector2(40, 40)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)

		var title := Label.new()
		title.add_theme_font_size_override("font_size", 20)
		title.clip_text = true
		info.add_child(title)

		var cost := RichTextLabel.new()
		cost.bbcode_enabled = true
		cost.fit_content = true
		cost.scroll_active = false
		cost.custom_minimum_size = Vector2(200, 0)
		cost.add_theme_font_size_override("normal_font_size", 15)
		info.add_child(cost)

		var button := Button.new()
		button.text = "Construir"
		button.custom_minimum_size = Vector2(110, 42)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var captured: String = building.id
		button.pressed.connect(func(): buy(captured))
		row.add_child(button)

		building_rows[building.id] = {"root": panel, "title": title, "cost": cost, "button": button}

func _build_era_overlay() -> void:
	era_overlay = CenterContainer.new()
	era_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	era_overlay.visible = false
	ui_root.add_child(era_overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 280)
	era_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Nova era"
	header.add_theme_font_size_override("font_size", 22)
	vbox.add_child(header)

	era_overlay_title = Label.new()
	era_overlay_title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(era_overlay_title)

	era_overlay_text = Label.new()
	era_overlay_text.add_theme_font_size_override("font_size", 20)
	era_overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	era_overlay_text.custom_minimum_size = Vector2(500, 0)
	vbox.add_child(era_overlay_text)

	var button := Button.new()
	button.text = "Voltar para a colônia"
	button.custom_minimum_size = Vector2(280, 50)
	button.pressed.connect(close_era_overlay)
	vbox.add_child(button)

# ---- atualização do HUD ----

# Humor médio vira palavra: "0,62" não diz nada pra quem está olhando a colônia.
static func _mood_word(mood: float) -> String:
	if mood >= 0.8:
		return "ótimo"
	if mood >= 0.6:
		return "bom"
	if mood >= 0.4:
		return "abalado"
	if mood >= 0.2:
		return "ruim"
	return "péssimo"

func _resource_color_hex(resource: String) -> String:
	return RESOURCE_COLORS[resource].to_html(false)

func _format_costs_bbcode(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in Economy.RESOURCES:
		if costs.has(resource):
			parts.append("[color=#%s]%s[/color]" % [_resource_color_hex(resource), Economy.format_amount(float(costs[resource]))])
	return " · ".join(parts)

func _format_production_bbcode(produces: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in Economy.RESOURCES:
		if produces.has(resource):
			parts.append("[color=#%s]%s[/color]" % [_resource_color_hex(resource), Economy.format_rate(float(produces[resource]))])
	return " · ".join(parts)

func _update_hud() -> void:
	var rate := economy.production_per_second()
	for resource in Economy.RESOURCES:
		var chip: Dictionary = resource_chips[resource]
		chip.amount.text = Economy.format_amount(economy.amount(resource))
		chip.rate.text = Economy.format_rate(rate[resource])

	population_count_label.text = str(population.villagers.size())
	# "Trabalhando" agora inclui quem está carregando a produção e quem está
	# levantando obra: continua sendo o trabalho da colônia (ver a nota de
	# equilíbrio em Population), e separar isso na tira só confundiria.
	var busy: int = population.count_in_state(Villager.STATE_WORKING) \
		+ population.count_in_state(Villager.STATE_BUILDING) + population.count_carrying()
	population_detail_label.text = "%d trabalhando" % busy
	population_mood_label.text = "Moradores · humor %s" % _mood_word(population.average_mood())
	_update_inspector()

	era_progress.value = economy.era_progress() * 100.0

	for id in building_rows:
		var row: Dictionary = building_rows[id]
		var building := Buildings.find(id)
		var unlocked := economy.is_unlocked(id)
		row.root.visible = unlocked
		if not unlocked:
			continue
		var n := maxi(_buy_amount(id), 1)
		row.title.text = "%s  ×%d" % [building.name, economy.count_of(id)]
		row.cost.text = "%s  →  %s" % [_format_costs_bbcode(economy.cost_of_n(id, n)), _format_production_bbcode(building.produces)]
		row.button.text = "Construir ×%d" % n
		row.button.disabled = not economy.can_buy_n(id, n)

	if Eras.is_last(economy.era_index):
		advance_button.disabled = true
		advance_button.text = "Fim da linha do tempo"
		advance_hint.text = "A colônia chegou na última era."
	else:
		advance_button.disabled = not economy.can_advance()
		advance_button.text = "Avançar para %s" % Eras.era(economy.era_index + 1).name
		advance_hint.text = "[color=#cccccc]Virada de era (%d%%):[/color] %s" % [
			int(economy.era_progress() * 100.0), _format_costs_bbcode(Eras.requirement(economy.era_index))
		]

func toggle_drawer() -> void:
	drawer_open = not drawer_open
	drawer_button.text = "Construções  ◂" if drawer_open else "Construções  ▸"
	var target_x := 1280.0 - DRAWER_WIDTH if drawer_open else 1280.0
	if _drawer_tween != null and _drawer_tween.is_valid():
		_drawer_tween.kill()
	_drawer_tween = create_tween()
	_drawer_tween.tween_property(drawer, "position:x", target_x, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_message(text: String) -> void:
	message_label.text = text
