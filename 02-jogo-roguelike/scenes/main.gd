extends Node2D

const TILE_SIZE := 16
const DISPLAY_SCALE := 3
const DUNGEON_WIDTH := 40
const DUNGEON_HEIGHT := 24

const STARTING_HP := 20
const PLAYER_ATTACK := 4

# Uma corrida é uma descida por vários andares; o último tem o chefe e a saída
# de verdade da caverna.
const FLOORS_PER_RUN := 5
const DESCEND_HEAL := 3

const DUNGEON_TEXTURE_PATH := "res://assets/dungeon/tilemap_packed.png"

const FLOOR_TILE_COORDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
const WALL_TILE_COORD := Vector2i(0, 3)
const PLAYER_TILE_COORD := Vector2i(1, 7)
const EXIT_TILE_COORD := Vector2i(5, 7)
const POTION_TILE_COORD := Vector2i(6, 9)

var state_machine: StateMachine
var rng := RandomNumberGenerator.new()

var dungeon: DungeonData
var player: Entity
var enemies: Array[Entity] = []
var inventory: Inventory
var floor_number := 1
var meta_levels: Dictionary = {}

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
var floor_label: Label
var camp_overlay: CenterContainer
var camp_gold_label: Label
var _camp_rows: Dictionary = {} # key -> {"label": Label, "button": Button}
var _camp_return_overlay: CenterContainer
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

# ---- meta-progressão ----

func load_meta_levels() -> Dictionary:
	var raw = SaveSystem.get_value("roguelike_upgrades", {})
	return raw if raw is Dictionary else {}

func banked_gold() -> int:
	return int(SaveSystem.get_value("roguelike_total_gold", 0))

func buy_upgrade(key: String) -> bool:
	var result := MetaProgression.purchase({"gold": banked_gold(), "levels": load_meta_levels()}, key)
	if not result.ok:
		return false
	SaveSystem.set_value("roguelike_total_gold", result.gold)
	SaveSystem.set_value("roguelike_upgrades", result.levels)
	SaveSystem.save_data()
	meta_levels = result.levels
	_refresh_camp_ui()
	return true

# ---- ciclo de uma corrida ----

func start_new_run(forced_dungeon: DungeonData = null, start_floor: int = 1) -> void:
	meta_levels = load_meta_levels()
	floor_number = maxi(1, start_floor)

	player = Entity.new(
		"Você",
		Vector2i.ZERO,
		MetaProgression.max_hp_for(meta_levels, STARTING_HP),
		MetaProgression.attack_for(meta_levels, PLAYER_ATTACK)
	)
	inventory = Inventory.new()
	inventory.add_potion(MetaProgression.starting_potions(meta_levels))

	_enter_floor(forced_dungeon)

func _enter_floor(forced_dungeon: DungeonData = null) -> void:
	dungeon = forced_dungeon if forced_dungeon else DungeonGenerator.generate(DUNGEON_WIDTH, DUNGEON_HEIGHT, rng, floor_number)
	dungeon.floor_number = floor_number
	player.grid_pos = dungeon.entrance

	enemies.clear()
	var boss_index := _boss_spawn_index()
	for i in dungeon.enemy_spawns.size():
		var kind: Dictionary = EnemyKinds.BOSS if i == boss_index else EnemyKinds.pick_for_floor(floor_number, rng)
		enemies.append(EnemyKinds.make_entity(kind, dungeon.enemy_spawns[i], floor_number))

	victory_overlay.visible = false
	game_over_overlay.visible = false
	camp_overlay.visible = false

	_build_floor_layer()
	_rebuild_item_sprites()
	_rebuild_enemy_sprites()

	if state_machine:
		state_machine.transition_to("Playing")
	_render()

# O chefe só aparece no último andar, guardando o spawn mais próximo da saída.
func _boss_spawn_index() -> int:
	if floor_number < FLOORS_PER_RUN or dungeon.enemy_spawns.is_empty():
		return -1
	var best := 0
	var best_dist := 1 << 30
	for i in dungeon.enemy_spawns.size():
		var pos: Vector2i = dungeon.enemy_spawns[i]
		var dist := absi(pos.x - dungeon.exit.x) + absi(pos.y - dungeon.exit.y)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best

func descend() -> void:
	floor_number += 1
	player.heal(DESCEND_HEAL)
	_enter_floor()
	set_message("Você desce para o andar %d da caverna. (+%d HP)" % [floor_number, DESCEND_HEAL])

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
			var reward := MetaProgression.apply_gold_bonus(meta_levels, int(enemy.get_meta("gold", 0)))
			inventory.add_gold(reward)
			set_message("%s foi derrotado! (+%d de ouro)" % [enemy.display_name, reward])
			_remove_enemy(enemy)
	else:
		player.grid_pos = target
		_check_item_pickup(target)
		if player.grid_pos == dungeon.exit:
			if floor_number < FLOORS_PER_RUN:
				descend()
				return
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
		var amount := MetaProgression.apply_gold_bonus(meta_levels, int(item.amount))
		inventory.add_gold(amount)
		set_message("Você encontrou %d de ouro." % amount)
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

func _bank_run(was_victory: bool) -> int:
	var runs_played: int = int(SaveSystem.get_value("roguelike_runs_played", 0)) + 1
	var total_gold: int = banked_gold() + inventory.gold
	var deepest: int = maxi(int(SaveSystem.get_value("roguelike_deepest_floor", 0)), floor_number)
	SaveSystem.set_value("roguelike_runs_played", runs_played)
	SaveSystem.set_value("roguelike_total_gold", total_gold)
	SaveSystem.set_value("roguelike_deepest_floor", deepest)
	if was_victory:
		SaveSystem.set_value("roguelike_victories", int(SaveSystem.get_value("roguelike_victories", 0)) + 1)
	SaveSystem.save_data()
	return total_gold

func on_run_completed() -> void:
	var total_gold := _bank_run(true)
	set_message("Você escapou da caverna!")
	victory_summary_label.text = "Andares vencidos: %d\nOuro coletado: %d\nOuro no acampamento: %d" % [
		floor_number, inventory.gold, total_gold
	]
	victory_overlay.visible = true
	_refresh_camp_ui()

func on_player_defeated() -> void:
	var total_gold := _bank_run(false)
	set_message("Você foi derrotado na caverna...")
	game_over_summary_label.text = "Chegou até o andar %d\nOuro coletado: %d\nOuro no acampamento: %d" % [
		floor_number, inventory.gold, total_gold
	]
	game_over_overlay.visible = true
	_refresh_camp_ui()

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
	floor_label.text = "Andar: %d/%d" % [floor_number, FLOORS_PER_RUN]

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
		var tile: Vector2i = enemy.get_meta("tile", EnemyKinds.KINDS[0].tile)
		var sprite := _make_sprite(tile)
		sprite.modulate = enemy.get_meta("tint", Color(1, 1, 1))
		if enemy.get_meta("boss", false):
			# O chefe é visivelmente maior que as criaturas comuns.
			sprite.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE) * 1.25
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

	floor_label = Label.new()
	floor_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_child(floor_label)

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
	victory_title.text = "Você escapou da caverna!"
	victory_title.add_theme_font_size_override("font_size", 28)
	victory_vbox.add_child(victory_title)

	victory_summary_label = Label.new()
	victory_vbox.add_child(victory_summary_label)

	victory_vbox.add_child(_make_overlay_buttons(victory_overlay))

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

	game_over_vbox.add_child(_make_overlay_buttons(game_over_overlay))

	_build_camp_overlay()

# Linha de botões compartilhada entre vitória e derrota: acampamento (gastar
# ouro em upgrades permanentes) ou descer de novo.
func _make_overlay_buttons(owner_overlay: CenterContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var camp_button := Button.new()
	camp_button.text = "Acampamento"
	camp_button.custom_minimum_size = Vector2(180, 48)
	camp_button.mouse_filter = Control.MOUSE_FILTER_STOP
	camp_button.pressed.connect(func(): open_camp(owner_overlay))
	row.add_child(camp_button)

	var run_button := Button.new()
	run_button.text = "Nova corrida"
	run_button.custom_minimum_size = Vector2(180, 48)
	run_button.mouse_filter = Control.MOUSE_FILTER_STOP
	run_button.pressed.connect(func(): _dispatch("on_new_run"))
	row.add_child(run_button)

	return row

func _build_camp_overlay() -> void:
	camp_overlay = CenterContainer.new()
	camp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	camp_overlay.visible = false
	ui_root.add_child(camp_overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 380)
	camp_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Acampamento"
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	camp_gold_label = Label.new()
	camp_gold_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(camp_gold_label)

	for upgrade in MetaProgression.UPGRADES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		vbox.add_child(row)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var button := Button.new()
		button.custom_minimum_size = Vector2(160, 40)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		var key: String = upgrade.key
		button.pressed.connect(func(): buy_upgrade(key))
		row.add_child(button)

		_camp_rows[key] = {"label": label, "button": button}

	var close_button := Button.new()
	close_button.text = "Voltar"
	close_button.custom_minimum_size = Vector2(160, 44)
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.pressed.connect(close_camp)
	vbox.add_child(close_button)

	_refresh_camp_ui()

func open_camp(return_overlay: CenterContainer = null) -> void:
	_camp_return_overlay = return_overlay
	if return_overlay:
		return_overlay.visible = false
	_refresh_camp_ui()
	camp_overlay.visible = true

func close_camp() -> void:
	camp_overlay.visible = false
	if _camp_return_overlay:
		_camp_return_overlay.visible = true

func _refresh_camp_ui() -> void:
	if camp_gold_label == null:
		return
	var levels := load_meta_levels()
	var gold := banked_gold()
	camp_gold_label.text = "Ouro no acampamento: %d" % gold

	for upgrade in MetaProgression.UPGRADES:
		var row: Dictionary = _camp_rows.get(upgrade.key, {})
		if row.is_empty():
			continue
		var level := MetaProgression.get_level(levels, upgrade.key)
		var cost := MetaProgression.cost_for(levels, upgrade.key)
		row.label.text = "%s  Nv %d/%d — %s" % [upgrade.label, level, upgrade.max_level, upgrade.desc]
		if cost < 0:
			row.button.text = "No máximo"
			row.button.disabled = true
		else:
			row.button.text = "Comprar (%d)" % cost
			row.button.disabled = gold < cost
