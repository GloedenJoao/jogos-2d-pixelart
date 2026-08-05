extends Node2D

# "Colônia Viva" — o clicker das "Eras da Civilização" virando colony sim:
# além de Economy (matemática de recursos), Population simula moradores
# individuais (Villager) que andam até o trabalho, produzem só enquanto
# presentes, e têm fome/energia/humor que competem com o trabalho.
# A cena cuida de UI, vila, moradores (sprites que só espelham Population) e
# persistência; toda a lógica testável sem cena está em Economy/Population.

const SAVE_KEY := "civilizacao"
const AUTOSAVE_INTERVAL := 10.0
const TOWN_TEXTURE_PATH := "res://assets/town/tilemap_packed.png"
# Tileset do Projeto 2 (roguelike), reaproveitado nos ícones das eras primitivas.
const DUNGEON_TEXTURE_PATH := "res://assets/dungeon/tilemap_packed.png"
const TILE := 16
const ICON_SCALE := 3
const VILLAGE_PER_ROW := 11
const VILLAGE_MAX_ICONS := 33

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
# Nomes que descrevem o "nível" do estoque de um recurso, do vazio à fartura —
# dá a sensação de que o mundo cresce junto com o número.
const STOCK_TIERS := [
	"vazio", "início", "pequeno estoque", "estoque", "fartura",
	"abundância", "excedente", "reserva vasta", "riqueza",
]
const STOCK_PIPS := 10
const BUY_MULTIPLIERS := [1, 10, 25]

# Cor de cada estado do Villager, pro pontinho na vila (ver _update_villager_sprites).
const VILLAGER_STATE_COLORS := {
	"idle": Color("9c9c9c"),
	"walking": Color("7ab8f0"),
	"working": Color("8fd17a"),
	"eating": Color("d8a45c"),
	"resting": Color("b98fd1"),
}
const VILLAGER_INITIAL_COUNT := 3

var economy := Economy.new()
var population := Population.new()
var state_machine: StateMachine
var _autosave_clock := 0.0

var _town_texture: Texture2D
var _dungeon_texture: Texture2D
var background: ColorRect
var ground: ColorRect
var village_root: Node2D
var villagers_root: Node2D
var _villager_dot_texture: ImageTexture
var _villager_nodes: Dictionary = {}   # villager id -> Sprite2D

var ui_root: Control
var era_label: Label
var era_subtitle: Label
var population_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var message_label: Label
var resource_rows: Dictionary = {}   # recurso -> {"amount","rate","tier","pips":[ColorRect]}
var gather_row: HBoxContainer
var buildings_box: VBoxContainer
var building_rows: Dictionary = {}   # id -> {"root","title","cost","button"}
var advance_button: Button
var advance_hint: RichTextLabel
var era_overlay: CenterContainer
var era_overlay_title: Label
var era_overlay_text: Label
var buy_multiplier := 1
var buy_multiplier_buttons: Dictionary = {}   # int -> Button

func _ready() -> void:
	population.rng.randomize()
	_town_texture = load(TOWN_TEXTURE_PATH)
	_dungeon_texture = load(DUNGEON_TEXTURE_PATH)
	_build_world()
	_build_ui()
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
	population.tick(delta, economy)
	economy.tick(delta, population.staffing_ratios())
	_autosave_clock += delta
	if _autosave_clock >= AUTOSAVE_INTERVAL:
		_autosave_clock = 0.0
		save_game()
	_update_hud()
	_update_villager_sprites()

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
		set_message("Recursos insuficientes para %s." % Buildings.find(id).name)
		return
	if n == 1:
		set_message("%s construído(a). Agora são %d." % [Buildings.find(id).name, economy.count_of(id)])
	else:
		set_message("%d× %s construído(as). Agora são %d." % [n, Buildings.find(id).name, economy.count_of(id)])
	population.sync_work_sites(economy)
	population.assign_jobs()
	_rebuild_village()
	_update_hud()
	save_game()

func set_buy_multiplier(value: int) -> void:
	buy_multiplier = value
	for key in buy_multiplier_buttons:
		buy_multiplier_buttons[key].button_pressed = (key == value)
	_update_hud()

func advance_era() -> void:
	if not economy.advance():
		set_message("A civilização ainda não tem o que essa virada exige.")
		return
	state_machine.transition_to("Era%d" % economy.era_index)
	save_game()

func on_era_entered(era_index: int) -> void:
	var era := Eras.era(era_index)
	background.color = era.bg
	ground.color = era.ground
	era_label.text = "%s (%d/%d)" % [era.name, era_index + 1, Eras.count()]
	era_subtitle.text = era.subtitle
	_build_gather_buttons(era)
	_build_building_rows()
	_rebuild_village()
	population.sync_work_sites(economy)
	population.assign_jobs()
	_update_hud()

	if era_index > 0:
		era_overlay_title.text = era.name
		era_overlay_text.text = "%s\n\nNovas construções: %s" % [
			era.subtitle,
			", ".join(_unlocked_names(era_index)),
		]
		era_overlay.visible = true
	set_message("Bem-vindo à %s." % era.name)

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
	data["population"] = population.to_dict()
	data["saved_at"] = Time.get_unix_time_from_system()
	SaveSystem.set_value(SAVE_KEY, data)
	SaveSystem.save_data()

func load_game() -> void:
	var data = SaveSystem.get_value(SAVE_KEY, {})
	var offline_seconds := 0.0
	if data is Dictionary and not data.is_empty():
		economy.from_dict(data)
		var saved_at := float(data.get("saved_at", 0.0))
		if saved_at > 0.0:
			offline_seconds = maxf(0.0, Time.get_unix_time_from_system() - saved_at)
		var pop_data = data.get("population", {})
		if pop_data is Dictionary and not pop_data.is_empty():
			population.from_dict(pop_data, economy)

	state_machine.transition_to("Era%d" % economy.era_index)
	population.ensure_minimum(VILLAGER_INITIAL_COUNT)
	population.sync_work_sites(economy)
	population.assign_jobs()

	if offline_seconds >= 60.0:
		var result := economy.apply_offline(offline_seconds)
		population.apply_offline_catchup(offline_seconds, economy)
		var minutes := int(result.seconds / 60.0)
		set_message("Enquanto você esteve fora (%d min), a civilização seguiu produzindo." % minutes)
		_update_hud()

func reset_game() -> void:
	economy = Economy.new()
	population = Population.new()
	population.rng.randomize()
	SaveSystem.set_value(SAVE_KEY, {})
	SaveSystem.save_data()
	state_machine.transition_to("Era0")
	population.ensure_minimum(VILLAGER_INITIAL_COUNT)
	population.sync_work_sites(economy)

# ---- vila ----

func _texture_for(sheet: String) -> Texture2D:
	return _dungeon_texture if sheet == "dungeon" else _town_texture

func _make_icon(sheet: String, coord: Vector2i) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _texture_for(sheet)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(ICON_SCALE, ICON_SCALE)
	sprite.centered = false
	return sprite

# Redesenha a vila: decoração da era + um ícone por construção (com teto, senão
# a tela vira sopa de sprites em cima de 200 fazendas).
func _rebuild_village() -> void:
	for child in village_root.get_children():
		child.queue_free()

	var era := Eras.era(economy.era_index)
	var decor_x := 60.0
	for coord in era.decor:
		var decor := _make_icon("town", coord)
		decor.position = Vector2(decor_x, 452)
		village_root.add_child(decor)
		decor_x += 70.0

	var icons: Array = []
	for building in Buildings.for_era(economy.era_index):
		var shown: int = mini(economy.count_of(building.id), 8)
		for _i in shown:
			icons.append({"sheet": building.sheet, "coord": building.icon})

	for i in mini(icons.size(), VILLAGE_MAX_ICONS):
		var icon := _make_icon(icons[i].sheet, icons[i].coord)
		icon.position = Vector2(60 + (i % VILLAGE_PER_ROW) * 56, 530 + int(i / VILLAGE_PER_ROW) * 60)
		village_root.add_child(icon)

# ---- moradores ----

# Pool de sprites: reaproveita um Sprite2D por Villager entre frames (Fase 6 —
# nada de instanciar/destruir nó a cada tick, só reposiciona/recolore o que já
# existe). A simulação em si mora inteira em Population; isto só espelha.
func _update_villager_sprites() -> void:
	var seen := {}
	for v in population.villagers:
		seen[v.id] = true
		var sprite: Sprite2D = _villager_nodes.get(v.id)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.texture = _villager_dot_texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(6, 8)
			villagers_root.add_child(sprite)
			_villager_nodes[v.id] = sprite
		sprite.position = v.position
		sprite.modulate = VILLAGER_STATE_COLORS.get(v.state, Color.WHITE)

	for id in _villager_nodes.keys():
		if not seen.has(id):
			_villager_nodes[id].queue_free()
			_villager_nodes.erase(id)

# ---- HUD ----

func set_message(text: String) -> void:
	message_label.text = text

func _update_hud() -> void:
	population_label.text = "Moradores: %d  ·  Trabalhando: %d/%d  ·  Humor médio: %d%%" % [
		population.villagers.size(),
		population.count_in_state(Villager.STATE_WORKING),
		population.employed_count(),
		int(population.average_mood() * 100.0),
	]
	var rate := economy.production_per_second(population.staffing_ratios())
	for resource in Economy.RESOURCES:
		var row: Dictionary = resource_rows[resource]
		var value := economy.amount(resource)
		row.amount.text = Economy.format_amount(value)
		row.rate.text = Economy.format_rate(rate[resource])
		_update_stock_visual(row, value)

	for id in building_rows:
		var row: Dictionary = building_rows[id]
		var building := Buildings.find(id)
		var visible_now := economy.is_unlocked(id)
		row.root.visible = visible_now
		if not visible_now:
			continue
		var n := maxi(_buy_amount(id), 1)
		row.title.text = "%s  ×%d" % [building.name, economy.count_of(id)]
		row.cost.text = "[color=#cccccc]Custo (×%d):[/color] %s\n[color=#cccccc]Produz:[/color] %s" % [
			n, _format_costs_bbcode(economy.cost_of_n(id, n)), _format_production_bbcode(building.produces)
		]
		row.button.text = "Construir ×%d" % n
		row.button.disabled = not economy.can_buy_n(id, n)

	progress_bar.value = economy.era_progress() * 100.0
	if Eras.is_last(economy.era_index):
		progress_label.text = "Última era alcançada"
		advance_button.disabled = true
		advance_button.text = "Fim da linha do tempo"
		advance_hint.text = "Sua civilização chegou na Era da Informação."
	else:
		progress_label.text = "Progresso para a próxima era: %d%%" % int(economy.era_progress() * 100.0)
		advance_button.disabled = not economy.can_advance()
		advance_button.text = "Avançar para %s" % Eras.era(economy.era_index + 1).name
		advance_hint.text = "[color=#cccccc]Custo da virada:[/color] %s" % _format_costs_bbcode(Eras.requirement(economy.era_index))

func _resource_color_hex(resource: String) -> String:
	return RESOURCE_COLORS[resource].to_html(false)

func _format_costs_bbcode(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in Economy.RESOURCES:
		if costs.has(resource):
			parts.append("[color=#%s]%s %s[/color]" % [_resource_color_hex(resource), Economy.format_amount(float(costs[resource])), RESOURCE_LABELS[resource].to_lower()])
	return ", ".join(parts)

func _format_production_bbcode(produces: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in Economy.RESOURCES:
		if produces.has(resource):
			parts.append("[color=#%s]%s de %s[/color]" % [_resource_color_hex(resource), Economy.format_rate(float(produces[resource])), RESOURCE_LABELS[resource].to_lower()])
	return ", ".join(parts)

# "Eleva" o número puro a uma leitura de mundo: uma barra de pips que enche
# junto com a escala logarítmica do estoque, mais um nome de nível.
func _update_stock_visual(row: Dictionary, value: float) -> void:
	var filled := clampi(int(floor(log(value + 1.0))), 0, STOCK_PIPS)
	var pips: Array = row.pips
	for i in pips.size():
		var pip: ColorRect = pips[i]
		pip.color = row.color if i < filled else Color(row.color, 0.12)
	var tier_index := clampi(int(floor(log(value + 1.0) / log(10.0))), 0, STOCK_TIERS.size() - 1)
	row.tier.text = STOCK_TIERS[tier_index].capitalize()

# ---- construção da cena ----

func _build_world() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	background = ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(background)

	ground = ColorRect.new()
	ground.position = Vector2(0, 430)
	ground.size = Vector2(1280, 290)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(ground)

	village_root = Node2D.new()
	village_root.name = "Vila"
	add_child(village_root)

	villagers_root = Node2D.new()
	villagers_root.name = "Moradores"
	add_child(villagers_root)
	_villager_dot_texture = _make_villager_dot_texture()

# Textura 2×2 branca reaproveitada (com `modulate`/escala) pra desenhar cada
# morador como um pontinho colorido — não há sprite de personagem no pack de
# assets do projeto (Kenney Tiny Town é só cenário), e um pontinho já deixa a
# simulação visível/testável sem depender de arte nova.
func _make_villager_dot_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	ui_root = Control.new()
	ui_root.theme = UITheme.theme
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(columns)

	columns.add_child(_build_left_column())
	columns.add_child(_build_right_column())

	_build_era_overlay()

func _build_left_column() -> Control:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE

	era_label = Label.new()
	era_label.add_theme_font_size_override("font_size", 30)
	left.add_child(era_label)

	era_subtitle = Label.new()
	era_subtitle.add_theme_font_size_override("font_size", 20)
	left.add_child(era_subtitle)

	population_label = Label.new()
	population_label.add_theme_font_size_override("font_size", 16)
	population_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	left.add_child(population_label)

	var resources_panel := PanelContainer.new()
	resources_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(resources_panel)

	var resources_box := VBoxContainer.new()
	resources_box.add_theme_constant_override("separation", 6)
	resources_panel.add_child(resources_box)

	for resource in Economy.RESOURCES:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		resources_box.add_child(column)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)

		var name_label := Label.new()
		name_label.text = RESOURCE_LABELS[resource]
		name_label.custom_minimum_size = Vector2(180, 0)
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", RESOURCE_COLORS[resource])
		row.add_child(name_label)

		var amount_label := Label.new()
		amount_label.custom_minimum_size = Vector2(110, 0)
		amount_label.add_theme_font_size_override("font_size", 22)
		amount_label.add_theme_color_override("font_color", RESOURCE_COLORS[resource])
		row.add_child(amount_label)

		var rate_label := Label.new()
		rate_label.add_theme_font_size_override("font_size", 20)
		row.add_child(rate_label)

		var stock_row := HBoxContainer.new()
		stock_row.add_theme_constant_override("separation", 3)
		column.add_child(stock_row)

		var pips: Array = []
		for _i in STOCK_PIPS:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(14, 8)
			pip.color = Color(RESOURCE_COLORS[resource], 0.12)
			stock_row.add_child(pip)
			pips.append(pip)

		var tier_label := Label.new()
		tier_label.add_theme_font_size_override("font_size", 14)
		tier_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		stock_row.add_child(tier_label)

		resource_rows[resource] = {
			"amount": amount_label, "rate": rate_label,
			"pips": pips, "tier": tier_label, "color": RESOURCE_COLORS[resource],
		}

	gather_row = HBoxContainer.new()
	gather_row.add_theme_constant_override("separation", 10)
	left.add_child(gather_row)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 20)
	left.add_child(message_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(spacer)

	return left

func _build_right_column() -> Control:
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 10)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 16)
	right.add_child(header_row)

	var title := Label.new()
	title.text = "Construções"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	var multiplier_row := HBoxContainer.new()
	multiplier_row.add_theme_constant_override("separation", 4)
	header_row.add_child(multiplier_row)
	for value in BUY_MULTIPLIERS:
		var button := Button.new()
		button.text = "×%d" % value
		button.toggle_mode = true
		button.button_pressed = value == buy_multiplier
		button.custom_minimum_size = Vector2(46, 34)
		button.pressed.connect(func(): set_buy_multiplier(value))
		multiplier_row.add_child(button)
		buy_multiplier_buttons[value] = button
	var max_button := Button.new()
	max_button.text = "Máx"
	max_button.toggle_mode = true
	max_button.button_pressed = buy_multiplier == -1
	max_button.custom_minimum_size = Vector2(46, 34)
	max_button.pressed.connect(func(): set_buy_multiplier(-1))
	multiplier_row.add_child(max_button)
	buy_multiplier_buttons[-1] = max_button

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 420)
	# Sem rolagem horizontal: as linhas quebram texto em vez de vazar pra fora da tela.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)

	buildings_box = VBoxContainer.new()
	buildings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buildings_box.add_theme_constant_override("separation", 8)
	scroll.add_child(buildings_box)

	progress_label = Label.new()
	progress_label.add_theme_font_size_override("font_size", 20)
	right.add_child(progress_label)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 22)
	progress_bar.show_percentage = false
	right.add_child(progress_bar)

	advance_hint = RichTextLabel.new()
	advance_hint.bbcode_enabled = true
	advance_hint.fit_content = true
	advance_hint.scroll_active = false
	advance_hint.add_theme_font_size_override("normal_font_size", 18)
	right.add_child(advance_hint)

	advance_button = Button.new()
	advance_button.custom_minimum_size = Vector2(0, 52)
	advance_button.pressed.connect(advance_era)
	right.add_child(advance_button)

	return right

func _build_gather_buttons(era: Dictionary) -> void:
	for child in gather_row.get_children():
		child.queue_free()
	for resource in era.click_resources:
		var button := Button.new()
		button.text = "Coletar %s" % RESOURCE_LABELS[resource].to_lower()
		button.custom_minimum_size = Vector2(220, 52)
		var captured: String = resource
		button.pressed.connect(func(): gather(captured))
		gather_row.add_child(button)

func _build_building_rows() -> void:
	for child in buildings_box.get_children():
		child.queue_free()
	building_rows.clear()

	for building in Buildings.ALL:
		var panel := PanelContainer.new()
		panel.visible = economy.is_unlocked(building.id)
		buildings_box.add_child(panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		panel.add_child(row)

		var icon := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = _texture_for(building.sheet)
		atlas.region = Rect2(building.icon.x * TILE, building.icon.y * TILE, TILE, TILE)
		icon.texture = atlas
		icon.custom_minimum_size = Vector2(48, 48)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.custom_minimum_size = Vector2(240, 0)
		row.add_child(info)

		var title := Label.new()
		title.add_theme_font_size_override("font_size", 22)
		title.clip_text = true
		info.add_child(title)

		var desc := Label.new()
		desc.text = building.desc
		desc.add_theme_font_size_override("font_size", 16)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)

		var cost := RichTextLabel.new()
		cost.bbcode_enabled = true
		cost.fit_content = true
		cost.scroll_active = false
		cost.custom_minimum_size = Vector2(220, 0)
		cost.add_theme_font_size_override("normal_font_size", 16)
		info.add_child(cost)

		var button := Button.new()
		button.text = "Construir"
		button.custom_minimum_size = Vector2(150, 48)
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
	panel.custom_minimum_size = Vector2(560, 300)
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
	button.text = "Continuar construindo"
	button.custom_minimum_size = Vector2(280, 52)
	button.pressed.connect(close_era_overlay)
	vbox.add_child(button)
