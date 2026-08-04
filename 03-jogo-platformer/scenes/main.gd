extends Node2D

# "Andarilho das Eras" — platformer em 3 eras, cada uma com uma mecânica de
# movimento nova. Aqui ficam a montagem do mundo (tilemap com colisão, itens,
# inimigos), a câmera, o HUD e as regras de dano/checkpoint/conclusão.

const TILE := 18
const CAMERA_ZOOM := 3.0
const START_HEARTS := 3
const INVULNERABLE_TIME := 0.9

const TILES_TEXTURE_PATH := "res://assets/platformer/tilemap_packed.png"

const GEM_TILE := Vector2i(7, 3)
const SPIKE_TILE := Vector2i(8, 3)
const DOOR_TOP_TILE := Vector2i(10, 6)
const DOOR_BASE_TILE := Vector2i(10, 7)
const CHECKPOINT_OFF_TILE := Vector2i(4, 3)
const CHECKPOINT_ON_TILE := Vector2i(6, 3)
const HEART_FULL_TILE := Vector2i(4, 2)
const HEART_EMPTY_TILE := Vector2i(6, 2)

var state_machine: StateMachine
var era_index := 0
var level: LevelData
var player: Player
var enemies: Array[Enemy] = []

var hearts := START_HEARTS
var gems_taken := 0
var total_gems := 0
var deaths := 0
var respawn_cell := Vector2i.ZERO
var _invulnerable := 0.0
var demo_mode := false
var demo_bot := DemoBot.new()

var _tiles_texture: Texture2D
var _tile_source_id: int

var world: Node2D
var background: ColorRect
var tile_layer: TileMapLayer
var props_root: Node2D
var camera: Camera2D
var _gem_nodes: Dictionary = {}        # Vector2i -> Sprite2D
var _checkpoint_nodes: Dictionary = {} # Vector2i -> Sprite2D

var ui_root: Control
var era_label: Label
var gems_label: Label
var ability_label: Label
var message_label: Label
var hint_label: Label
var hearts_box: HBoxContainer
var era_overlay: CenterContainer
var era_overlay_title: Label
var era_overlay_text: Label
var era_overlay_button: Button
var final_overlay: CenterContainer
var final_overlay_text: Label

func _ready() -> void:
	_tiles_texture = load(TILES_TEXTURE_PATH)
	_build_world()
	_build_ui()
	_setup_state_machine()
	start_game(0)

func _setup_state_machine() -> void:
	state_machine = StateMachine.new()
	for entry in [["Playing", PlayingState.new()], ["EraComplete", EraCompleteState.new()], ["GameComplete", GameCompleteState.new()]]:
		var state: State = entry[1]
		state.name = entry[0]
		state.set("game", self)
		state_machine.add_child(state)
	add_child(state_machine)

func _dispatch(method_name: String) -> void:
	var current := state_machine.current_state
	if current and current.has_method(method_name):
		current.call(method_name)

func is_playing() -> bool:
	return state_machine != null and state_machine.current_state != null and state_machine.current_state.name == "Playing"

# ---- ciclo de jogo ----

func start_game(from_era: int = 0) -> void:
	total_gems = 0
	deaths = 0
	load_era(from_era)

func load_era(index: int) -> void:
	era_index = clampi(index, 0, Levels.count() - 1)
	var era := Levels.era(era_index)
	level = Levels.level_data(era_index)

	hearts = START_HEARTS
	gems_taken = 0
	_invulnerable = 0.0
	respawn_cell = level.spawn

	background.color = era.bg
	_build_tile_layer(era)
	_build_props()
	_spawn_enemies(era)

	player.abilities = Abilities.for_era(era_index)
	player.can_control = true
	_place_player(level.spawn)
	_setup_camera()

	era_overlay.visible = false
	final_overlay.visible = false

	_record_progress()
	if state_machine:
		state_machine.transition_to("Playing")
	_update_hud()

func restart_era() -> void:
	load_era(era_index)

func on_playing_entered() -> void:
	var era := Levels.era(era_index)
	var ability: String = era.ability
	if ability == "":
		set_message("Chegue na porta no fim do caminho.")
	else:
		set_message("%s destravado! %s" % [Abilities.label(ability), Abilities.hint(ability)])

func on_era_completed() -> void:
	player.can_control = false
	player.velocity = Vector2.ZERO
	total_gems += gems_taken
	_record_progress()
	era_overlay_title.text = "%s concluída" % Levels.era(era_index).name
	var next_era := Levels.era(era_index + 1)
	era_overlay_text.text = "Gemas nesta era: %d/%d\nQuedas: %d\n\nPróxima: %s\n%s" % [
		gems_taken, level.gems.size(), deaths, next_era.name, next_era.subtitle
	]
	era_overlay_button.text = "Ir para %s" % next_era.name
	era_overlay.visible = true

func on_game_completed() -> void:
	player.can_control = false
	player.velocity = Vector2.ZERO
	total_gems += gems_taken
	SaveSystem.set_value("platformer_completed", true)
	SaveSystem.set_value("platformer_best_gems", maxi(int(SaveSystem.get_value("platformer_best_gems", 0)), total_gems))
	SaveSystem.save_data()
	final_overlay_text.text = "Você atravessou as três eras.\n\nGemas coletadas: %d\nQuedas: %d" % [total_gems, deaths]
	final_overlay.visible = true

func _record_progress() -> void:
	var reached: int = maxi(int(SaveSystem.get_value("platformer_era_reached", 0)), era_index)
	SaveSystem.set_value("platformer_era_reached", reached)
	SaveSystem.set_value("platformer_deaths", deaths)
	SaveSystem.save_data()

# ---- mundo ----

func _place_player(cell: Vector2i) -> void:
	player.global_position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
	player.reset_motion()

func _setup_camera() -> void:
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = level.width * TILE
	camera.limit_bottom = level.height * TILE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.reset_smoothing()

func _build_tile_set(era: Dictionary) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer() # -1 = adiciona no fim; passar 0 aqui não cria a camada

	var atlas := TileSetAtlasSource.new()
	atlas.texture = _tiles_texture
	atlas.texture_region_size = Vector2i(TILE, TILE)
	# A fonte precisa estar dentro do TileSet antes de mexer nas colisões: os
	# TileData só enxergam as camadas de física do TileSet a que pertencem.
	_tile_source_id = tile_set.add_source(atlas)

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	])
	for coord in _era_tiles(era):
		if not atlas.has_tile(coord):
			atlas.create_tile(coord)
		var tile_data := atlas.get_tile_data(coord, 0)
		tile_data.add_collision_polygon(0)
		tile_data.set_collision_polygon_points(0, 0, square)
	return tile_set

func _era_tiles(era: Dictionary) -> Array:
	return era.tiles.values()

# Escolhe o tile pela vizinhança: sem nada em cima é topo (com a ponta certa pra
# não ficar contorno no meio do terreno); com terra em cima é recheio.
func _tile_for_cell(era: Dictionary, cell: Vector2i) -> Vector2i:
	if level.is_solid(cell + Vector2i(0, -1)):
		return era.tiles.fill
	var open_left := not level.is_solid(cell + Vector2i(-1, 0))
	var open_right := not level.is_solid(cell + Vector2i(1, 0))
	if open_left and open_right:
		return era.tiles.single
	if open_left:
		return era.tiles.left
	if open_right:
		return era.tiles.right
	return era.tiles.mid

func _build_tile_layer(era: Dictionary) -> void:
	tile_layer.tile_set = _build_tile_set(era)
	tile_layer.clear()
	for cell in level.solids:
		tile_layer.set_cell(cell, _tile_source_id, _tile_for_cell(era, cell))

func _build_props() -> void:
	for child in props_root.get_children():
		child.queue_free()
	_gem_nodes.clear()
	_checkpoint_nodes.clear()

	for cell in level.gems:
		var gem := _make_tile_sprite(GEM_TILE, cell)
		props_root.add_child(gem)
		_gem_nodes[cell] = gem

	for cell in level.spikes:
		props_root.add_child(_make_tile_sprite(SPIKE_TILE, cell))

	for cell in level.checkpoints:
		var flag := _make_tile_sprite(CHECKPOINT_OFF_TILE, cell)
		props_root.add_child(flag)
		_checkpoint_nodes[cell] = flag

	props_root.add_child(_make_tile_sprite(DOOR_BASE_TILE, level.exit_cell))
	props_root.add_child(_make_tile_sprite(DOOR_TOP_TILE, level.exit_cell + Vector2i(0, -1)))

func _spawn_enemies(era: Dictionary) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()

	for cell in level.enemies:
		var enemy := Enemy.new()
		enemy.level = level
		# Camada própria: o inimigo colide com o cenário (máscara 1), mas atravessa
		# o jogador — quem resolve o contato é _check_enemies().
		enemy.collision_layer = 2
		enemy.collision_mask = 1
		var frames: Array[Vector2i] = []
		for frame in era.enemy_frames:
			frames.append(frame)
		enemy.frames = frames
		enemy.position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
		enemy.patrol_center = enemy.position.x
		world.add_child(enemy)
		enemies.append(enemy)

func _make_tile_sprite(coord: Vector2i, cell: Vector2i) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _tiles_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
	return sprite

# ---- regras por frame ----

func toggle_demo_mode() -> void:
	demo_mode = not demo_mode
	if demo_mode:
		demo_bot.reset()
		set_message("Modo demo ligado (B desliga).")
	else:
		player.clear_input_override()
		set_message("Modo demo desligado.")

func _physics_process(delta: float) -> void:
	if not is_playing() or player == null:
		return

	if demo_mode:
		demo_bot.step(self)

	_invulnerable = maxf(0.0, _invulnerable - delta)
	player.modulate.a = 0.5 if _invulnerable > 0.0 else 1.0

	var cell := _cell_of(player.global_position)

	if player.global_position.y > (level.height + 2) * TILE:
		hurt("Você caiu no vazio.")
		return

	_check_gems(cell)
	_check_checkpoints(cell)

	for spike in level.spikes:
		if spike == cell:
			hurt("Espinhos!")
			return

	if _check_enemies():
		return

	if cell == level.exit_cell or cell == level.exit_cell + Vector2i(0, -1):
		_finish_era()
		return

	_update_hud()

func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))

func _check_gems(cell: Vector2i) -> void:
	if not _gem_nodes.has(cell):
		return
	var gem: Sprite2D = _gem_nodes[cell]
	gem.queue_free()
	_gem_nodes.erase(cell)
	gems_taken += 1
	set_message("Gema coletada! (%d/%d)" % [gems_taken, level.gems.size()])

func _check_checkpoints(cell: Vector2i) -> void:
	if not _checkpoint_nodes.has(cell) or respawn_cell == cell:
		return
	respawn_cell = cell
	var flag: Sprite2D = _checkpoint_nodes[cell]
	flag.region_rect = Rect2(CHECKPOINT_ON_TILE.x * TILE, CHECKPOINT_ON_TILE.y * TILE, TILE, TILE)
	set_message("Checkpoint ativado.")

# Retorna true se o frame terminou por causa de um inimigo (pisão ou dano).
func _check_enemies() -> bool:
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var diff := enemy.global_position - player.global_position
		if absf(diff.x) > 13.0 or absf(diff.y) > 15.0:
			continue
		if player.velocity.y > 40.0 and diff.y > 4.0:
			enemy.defeat()
			player.bounce()
			set_message("Você pisou no inimigo!")
			return true
		hurt("Você levou um esbarrão.")
		return true
	return false

func hurt(reason: String) -> void:
	if _invulnerable > 0.0:
		return
	hearts -= 1
	deaths += 1
	_invulnerable = INVULNERABLE_TIME
	if hearts <= 0:
		set_message("%s Sem corações — a era recomeça." % reason)
		load_era(era_index)
		return
	set_message("%s Voltando ao último checkpoint." % reason)
	_place_player(respawn_cell)
	_update_hud()

func _finish_era() -> void:
	if era_index >= Levels.count() - 1:
		state_machine.transition_to("GameComplete")
	else:
		state_machine.transition_to("EraComplete")

# ---- HUD ----

func set_message(text: String) -> void:
	message_label.text = text

func _update_hud() -> void:
	var era := Levels.era(era_index)
	era_label.text = "%s (%d/%d)" % [era.name, era_index + 1, Levels.count()]
	gems_label.text = "Gemas: %d/%d" % [gems_taken, level.gems.size()]
	ability_label.text = Abilities.summary(era_index)

	for i in hearts_box.get_child_count():
		var heart: TextureRect = hearts_box.get_child(i)
		var coord: Vector2i = HEART_FULL_TILE if i < hearts else HEART_EMPTY_TILE
		var atlas: AtlasTexture = heart.texture
		atlas.region = Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)

# ---- construção da cena ----

func _build_world() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	background = ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(background)

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	tile_layer = TileMapLayer.new()
	tile_layer.name = "Tiles"
	tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(tile_layer)

	props_root = Node2D.new()
	props_root.name = "Props"
	world.add_child(props_root)

	player = Player.new()
	player.name = "Player"
	# Inimigos ficam numa camada própria: eles colidem com o cenário, mas não
	# empurram nem travam o jogador (o contato é resolvido no _physics_process).
	player.collision_layer = 1
	player.collision_mask = 1
	world.add_child(player)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	player.add_child(camera)

func _make_heart_rect() -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = _tiles_texture
	atlas.region = Rect2(HEART_FULL_TILE.x * TILE, HEART_FULL_TILE.y * TILE, TILE, TILE)
	var rect := TextureRect.new()
	rect.texture = atlas
	rect.custom_minimum_size = Vector2(36, 36)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect

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

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 24)
	vbox.add_child(top_bar)

	era_label = Label.new()
	era_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_child(era_label)

	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 4)
	for _i in START_HEARTS:
		hearts_box.add_child(_make_heart_rect())
	top_bar.add_child(hearts_box)

	gems_label = Label.new()
	gems_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_child(gems_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 22)
	top_bar.add_child(message_label)

	var mid_spacer := Control.new()
	mid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(mid_spacer)

	ability_label = Label.new()
	ability_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(ability_label)

	hint_label = Label.new()
	hint_label.text = "A/D ou setas para andar, Espaço/W para pular, Shift/J para dash, R reinicia a era, B liga o modo demo."
	hint_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint_label)

	_build_era_overlay()
	_build_final_overlay()

func _build_era_overlay() -> void:
	era_overlay = CenterContainer.new()
	era_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	era_overlay.visible = false
	ui_root.add_child(era_overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 280)
	era_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	era_overlay_title = Label.new()
	era_overlay_title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(era_overlay_title)

	era_overlay_text = Label.new()
	era_overlay_text.add_theme_font_size_override("font_size", 20)
	vbox.add_child(era_overlay_text)

	era_overlay_button = Button.new()
	era_overlay_button.custom_minimum_size = Vector2(240, 48)
	era_overlay_button.mouse_filter = Control.MOUSE_FILTER_STOP
	era_overlay_button.pressed.connect(func(): _dispatch("on_continue"))
	vbox.add_child(era_overlay_button)

func _build_final_overlay() -> void:
	final_overlay = CenterContainer.new()
	final_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	final_overlay.visible = false
	ui_root.add_child(final_overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 260)
	final_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Fim da jornada"
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	final_overlay_text = Label.new()
	final_overlay_text.add_theme_font_size_override("font_size", 20)
	vbox.add_child(final_overlay_text)

	var button := Button.new()
	button.text = "Recomeçar da primeira era"
	button.custom_minimum_size = Vector2(280, 48)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(func(): _dispatch("on_continue"))
	vbox.add_child(button)
