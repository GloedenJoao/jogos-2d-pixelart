extends Node2D

const TILE_SIZE := 16
const DISPLAY_SCALE := 3
const DUNGEON_WIDTH := 40
const DUNGEON_HEIGHT := 24

const STARTING_HP := 20
const PLAYER_ATTACK := 4
const ENEMY_HP := 6
const ENEMY_ATTACK := 2

const DUNGEON_TEXTURE_PATH := "res://assets/dungeon/tilemap_packed.png"

const FLOOR_TILE_COORDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
const WALL_TILE_COORD := Vector2i(0, 3)
const PLAYER_TILE_COORD := Vector2i(1, 7)
const EXIT_TILE_COORD := Vector2i(5, 7)
const POTION_TILE_COORD := Vector2i(6, 9)

const ENEMY_KINDS := [
	{"name": "Limo", "tile": Vector2i(0, 9)},
	{"name": "Caranguejo", "tile": Vector2i(2, 9)},
	{"name": "Morcego", "tile": Vector2i(0, 10)},
	{"name": "Golem de Pedra", "tile": Vector2i(1, 10)},
	{"name": "Fungo Rastejante", "tile": Vector2i(2, 10)},
]

var state_machine: StateMachine
var rng := RandomNumberGenerator.new()

var dungeon: DungeonData
var player: Entity
var enemies: Array[Entity] = []
var inventory: Inventory

var tile_source_id: int
var _dungeon_texture: Texture2D

var world: Node2D
var floor_layer: TileMapLayer
var entities_root: Node2D
var camera: Camera2D
var player_sprite: Sprite2D
var exit_marker: Sprite2D
var _enemy_sprites: Dictionary = {} # Entity -> Sprite2D
var _item_sprites: Dictionary = {} # Vector2i -> Sprite2D

var ui_root: Control
var hp_label: Label
var gold_label: Label
var potions_label: Label
var message_label: Label
var hint_label: Label
var victory_overlay: CenterContainer
var victory_summary_label: Label
var game_over_overlay: CenterContainer
var game_over_summary_label: Label

func _ready() -> void:
	rng.randomize()
	_dungeon_texture = load(DUNGEON_TEXTURE_PATH)

	_build_world()
	_build_ui()
	_setup_state_machine()

	start_new_run()

func _setup_state_machine() -> void:
	state_machine = StateMachine.new()

	var playing := PlayingState.new()
	playing.name = "Playing"
	playing.game = self

	var victory := VictoryState.new()
	victory.name = "Victory"
	victory.game = self

	var game_over := GameOverState.new()
	game_over.name = "GameOver"
	game_over.game = self

	state_machine.add_child(playing)
	state_machine.add_child(victory)
	state_machine.add_child(game_over)
	add_child(state_machine)

func _dispatch(method_name: String) -> void:
	var current := state_machine.current_state
	if current and current.has_method(method_name):
		current.call(method_name)

# ---- ciclo de uma corrida ----

func start_new_run(forced_dungeon: DungeonData = null) -> void:
	dungeon = forced_dungeon if forced_dungeon else DungeonGenerator.generate(DUNGEON_WIDTH, DUNGEON_HEIGHT, rng)
	player = Entity.new("Você", dungeon.entrance, STARTING_HP, PLAYER_ATTACK)
	inventory = Inventory.new()

	enemies.clear()
	for pos in dungeon.enemy_spawns:
		var kind: Dictionary = ENEMY_KINDS[rng.randi_range(0, ENEMY_KINDS.size() - 1)]
		var enemy := Entity.new(kind.name, pos, ENEMY_HP, ENEMY_ATTACK)
		enemy.set_meta("tile", kind.tile)
		enemies.append(enemy)

	victory_overlay.visible = false
	game_over_overlay.visible = false

	_build_floor_layer()
	_rebuild_item_sprites()
	_rebuild_enemy_sprites()

	if state_machine:
		state_machine.transition_to("Playing")
	_render()

# ---- movimento / combate (chamado pelo PlayingState) ----

func try_move(dir: Vector2i) -> void:
	if state_machine.current_state.name != "Playing":
		return
	if not player.is_alive():
		return

	var target := player.grid_pos + dir
	if not dungeon.is_floor(target):
		return

	var enemy := _enemy_at(target)
	if enemy:
		var result := CombatResolver.resolve_attack(player, enemy)
		set_message("Você ataca %s (-%d HP)." % [enemy.display_name, result.damage])
		if result.defender_died:
			set_message("%s foi derrotado!" % enemy.display_name)
			_remove_enemy(enemy)
	else:
		player.grid_pos = target
		_check_item_pickup(target)
		if player.grid_pos == dungeon.exit:
			_render()
			state_machine.transition_to("Victory")
			return

	_enemies_take_turn()
	_render()

	if not player.is_alive():
		state_machine.transition_to("GameOver")

func try_use_potion() -> void:
	if state_machine.current_state.name != "Playing":
		return
	if inventory.use_potion(player):
		set_message("Você usou uma poção. (+%d HP)" % Inventory.POTION_HEAL)
		_render()
	else:
		set_message("Sem poções pra usar (ou HP já cheio).")

func _enemy_at(pos: Vector2i) -> Entity:
	for enemy in enemies:
		if enemy.grid_pos == pos:
			return enemy
	return null

func _remove_enemy(enemy: Entity) -> void:
	enemies.erase(enemy)
	var sprite: Sprite2D = _enemy_sprites.get(enemy)
	if sprite:
		sprite.queue_free()
		_enemy_sprites.erase(enemy)

func _check_item_pickup(pos: Vector2i) -> void:
	var item := dungeon.item_at(pos)
	if item.is_empty():
		return
	if item.type == "gold":
		inventory.add_gold(item.amount)
		set_message("Você encontrou %d de ouro." % item.amount)
	else:
		inventory.add_potion(item.amount)
		set_message("Você encontrou uma poção.")
	dungeon.remove_item_at(pos)
	var sprite: Sprite2D = _item_sprites.get(pos)
	if sprite:
		sprite.queue_free()
		_item_sprites.erase(pos)

func _enemies_take_turn() -> void:
	var occupied: Dictionary = {}
	for enemy in enemies:
		occupied[enemy.grid_pos] = true
	occupied[player.grid_pos] = true

	for enemy in enemies.duplicate():
		if not enemy.is_alive():
			continue
		occupied.erase(enemy.grid_pos)
		var decision := EnemyAI.decide(enemy, player, dungeon, occupied)
		match decision.action:
			"attack":
				var result := CombatResolver.resolve_attack(enemy, player)
				set_message("%s ataca você (-%d HP)." % [enemy.display_name, result.damage])
			"move":
				enemy.grid_pos = decision.to
		occupied[enemy.grid_pos] = true

# ---- transições de fase (chamadas pelos states) ----

func on_floor_cleared() -> void:
	var runs_played: int = SaveSystem.get_value("roguelike_runs_played", 0) + 1
	var victories: int = SaveSystem.get_value("roguelike_victories", 0) + 1
	var total_gold: int = SaveSystem.get_value("roguelike_total_gold", 0) + inventory.gold
	SaveSystem.set_value("roguelike_runs_played", runs_played)
	SaveSystem.set_value("roguelike_victories", victories)
	SaveSystem.set_value("roguelike_total_gold", total_gold)
	SaveSystem.save_data()

	set_message("Você encontrou a saída da caverna!")
	victory_summary_label.text = "Ouro coletado: %d\nOuro total acumulado: %d" % [inventory.gold, total_gold]
	victory_overlay.visible = true

func on_player_defeated() -> void:
	var runs_played: int = SaveSystem.get_value("roguelike_runs_played", 0) + 1
	var total_gold: int = SaveSystem.get_value("roguelike_total_gold", 0) + inventory.gold
	SaveSystem.set_value("roguelike_runs_played", runs_played)
	SaveSystem.set_value("roguelike_total_gold", total_gold)
	SaveSystem.save_data()

	set_message("Você foi derrotado na caverna...")
	game_over_summary_label.text = "Ouro coletado nesta corrida: %d\nOuro total acumulado: %d" % [inventory.gold, total_gold]
	game_over_overlay.visible = true

# ---- renderização ----

func _render() -> void:
	player_sprite.position = _world_pos(player.grid_pos)
	for enemy in enemies:
		var sprite: Sprite2D = _enemy_sprites.get(enemy)
		if sprite:
			sprite.position = _world_pos(enemy.grid_pos)

	camera.position = player_sprite.position + Vector2(TILE_SIZE, TILE_SIZE) * DISPLAY_SCALE * 0.5

	hp_label.text = "HP: %d/%d" % [player.hp, player.max_hp]
	gold_label.text = "Ouro: %d" % inventory.gold
	potions_label.text = "Poções: %d" % inventory.potions

func set_message(text: String) -> void:
	message_label.text = text

func _world_pos(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos) * TILE_SIZE * DISPLAY_SCALE

func _floor_variant(pos: Vector2i) -> Vector2i:
	var idx := int(abs(pos.x * 928371 + pos.y * 12289)) % FLOOR_TILE_COORDS.size()
	return FLOOR_TILE_COORDS[idx]

func _adjacent_to_floor(pos: Vector2i) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if dungeon.is_floor(pos + Vector2i(dx, dy)):
				return true
	return false

func _build_floor_layer() -> void:
	floor_layer.clear()
	for x in dungeon.width:
		for y in dungeon.height:
			var pos := Vector2i(x, y)
			if dungeon.is_floor(pos):
				floor_layer.set_cell(pos, tile_source_id, _floor_variant(pos))
			elif _adjacent_to_floor(pos):
				floor_layer.set_cell(pos, tile_source_id, WALL_TILE_COORD)

	exit_marker.position = _world_pos(dungeon.exit)

func _rebuild_item_sprites() -> void:
	for sprite in _item_sprites.values():
		sprite.queue_free()
	_item_sprites.clear()
	for item in dungeon.items:
		var coord: Vector2i = POTION_TILE_COORD if item.type == "potion" else Vector2i(-1, -1)
		var sprite: Sprite2D
		if item.type == "gold":
			sprite = _make_gold_marker()
		else:
			sprite = _make_sprite(coord)
		sprite.position = _world_pos(item.pos)
		entities_root.add_child(sprite)
		_item_sprites[item.pos] = sprite

func _rebuild_enemy_sprites() -> void:
	for sprite in _enemy_sprites.values():
		sprite.queue_free()
	_enemy_sprites.clear()
	for enemy in enemies:
		var tile: Vector2i = enemy.get_meta("tile", ENEMY_KINDS[0].tile)
		var sprite := _make_sprite(tile)
		sprite.position = _world_pos(enemy.grid_pos)
		entities_root.add_child(sprite)
		_enemy_sprites[enemy] = sprite

func _make_sprite(atlas_coord: Vector2i) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _dungeon_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(atlas_coord.x * TILE_SIZE, atlas_coord.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	return sprite

func _make_gold_marker() -> Sprite2D:
	# Sem um ícone de moeda claro no tileset; desenha um marcador dourado simples.
	var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in TILE_SIZE:
		for y in TILE_SIZE:
			var center := Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= TILE_SIZE / 2.0 - 2.0:
				image.set_pixel(x, y, Color("f4c542"))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	return sprite

# ---- construção da cena ----

func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = _dungeon_texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var coords: Array[Vector2i] = FLOOR_TILE_COORDS.duplicate()
	coords.append(WALL_TILE_COORD)
	for coord in coords:
		if not atlas.has_tile(coord):
			atlas.create_tile(coord)
	tile_source_id = tile_set.add_source(atlas)
	return tile_set

func _build_world() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)

	floor_layer = TileMapLayer.new()
	floor_layer.name = "FloorLayer"
	floor_layer.tile_set = _build_tile_set()
	floor_layer.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
	floor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(floor_layer)

	entities_root = Node2D.new()
	entities_root.name = "Entities"
	world.add_child(entities_root)

	exit_marker = _make_sprite(EXIT_TILE_COORD)
	exit_marker.name = "ExitMarker"
	entities_root.add_child(exit_marker)

	player_sprite = _make_sprite(PLAYER_TILE_COORD)
	player_sprite.name = "PlayerSprite"
	entities_root.add_child(player_sprite)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	world.add_child(camera)

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
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 24)
	vbox.add_child(top_bar)

	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_child(hp_label)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_child(gold_label)

	potions_label = Label.new()
	potions_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_child(potions_label)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 22)
	top_bar.add_child(message_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(bottom_spacer)

	hint_label = Label.new()
	hint_label.text = "Setas/WASD para mover, ataque encostando no inimigo. U para usar poção."
	hint_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint_label)

	# Overlay de vitória.
	victory_overlay = CenterContainer.new()
	victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_overlay.visible = false
	ui_root.add_child(victory_overlay)

	var victory_panel := PanelContainer.new()
	victory_panel.custom_minimum_size = Vector2(360, 220)
	victory_overlay.add_child(victory_panel)

	var victory_vbox := VBoxContainer.new()
	victory_vbox.add_theme_constant_override("separation", 14)
	victory_panel.add_child(victory_vbox)

	var victory_title := Label.new()
	victory_title.text = "Saída encontrada!"
	victory_title.add_theme_font_size_override("font_size", 28)
	victory_vbox.add_child(victory_title)

	victory_summary_label = Label.new()
	victory_vbox.add_child(victory_summary_label)

	var victory_button := Button.new()
	victory_button.text = "Nova corrida"
	victory_button.custom_minimum_size = Vector2(180, 48)
	victory_button.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_button.pressed.connect(func(): _dispatch("on_new_run"))
	victory_vbox.add_child(victory_button)

	# Overlay de derrota.
	game_over_overlay = CenterContainer.new()
	game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.visible = false
	ui_root.add_child(game_over_overlay)

	var game_over_panel := PanelContainer.new()
	game_over_panel.custom_minimum_size = Vector2(360, 220)
	game_over_overlay.add_child(game_over_panel)

	var game_over_vbox := VBoxContainer.new()
	game_over_vbox.add_theme_constant_override("separation", 14)
	game_over_panel.add_child(game_over_vbox)

	var game_over_title := Label.new()
	game_over_title.text = "Você caiu na caverna"
	game_over_title.add_theme_font_size_override("font_size", 28)
	game_over_vbox.add_child(game_over_title)

	game_over_summary_label = Label.new()
	game_over_vbox.add_child(game_over_summary_label)

	var game_over_button := Button.new()
	game_over_button.text = "Tentar de novo"
	game_over_button.custom_minimum_size = Vector2(180, 48)
	game_over_button.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_button.pressed.connect(func(): _dispatch("on_new_run"))
	game_over_vbox.add_child(game_over_button)
