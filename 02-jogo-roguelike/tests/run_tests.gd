extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_test_dungeon_generator()
	_test_entity_and_combat()
	_test_inventory()
	_test_enemy_ai()
	await _test_scene_initial_state()
	await _test_bump_attack_kills_enemy()
	await _test_item_pickup()
	await _test_reach_exit_triggers_victory()
	await _test_enemy_attack_triggers_game_over()
	_report()

func _assert(cond: bool, message: String) -> void:
	if cond:
		_pass += 1
		print("  OK   - %s" % message)
	else:
		_fail += 1
		print("  FAIL - %s" % message)

# ---- lógica pura ----

func _test_dungeon_generator() -> void:
	print("[DungeonGenerator]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var d: DungeonData = DungeonGenerator.generate(40, 24, rng)
	_assert(d.rooms.size() >= 2, "gera pelo menos 2 salas com seed fixa")
	_assert(d.is_floor(d.entrance), "entrada é piso")
	_assert(d.is_floor(d.exit), "saída é piso")
	_assert(d.entrance != d.exit, "entrada e saída são células diferentes")
	_assert(_bfs_reachable(d, d.entrance, d.exit), "saída é alcançável a partir da entrada (corredores conectam as salas)")

func _bfs_reachable(d: DungeonData, from: Vector2i, to: Vector2i) -> bool:
	var visited := {from: true}
	var queue := [from]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			return true
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + dir
			if not visited.has(next) and d.is_floor(next):
				visited[next] = true
				queue.append(next)
	return false

func _test_entity_and_combat() -> void:
	print("[Entity/CombatResolver]")
	var attacker := Entity.new("Atacante", Vector2i.ZERO, 10, 5)
	var defender := Entity.new("Defensor", Vector2i.ONE, 8, 2)
	var result := CombatResolver.resolve_attack(attacker, defender)
	_assert(result.damage == 5, "dano igual ao attack do atacante")
	_assert(defender.hp == 3, "defensor perde HP igual ao dano")
	_assert(not result.defender_died, "defensor sobrevive com HP > 0")

	var result2 := CombatResolver.resolve_attack(attacker, defender)
	_assert(result2.defender_died, "segundo golpe derruba o defensor (HP <= 0)")
	_assert(defender.hp == 0, "HP não fica negativo")
	_assert(not defender.is_alive(), "is_alive() reflete a morte")

func _test_inventory() -> void:
	print("[Inventory]")
	var inv := Inventory.new()
	var player := Entity.new("Jogador", Vector2i.ZERO, 20, 4)
	player.hp = 10
	_assert(not inv.use_potion(player), "usar poção sem ter nenhuma falha")
	inv.add_potion()
	_assert(inv.potions == 1, "add_potion incrementa o contador")
	_assert(inv.use_potion(player), "usar poção com estoque funciona")
	_assert(player.hp == 10 + Inventory.POTION_HEAL, "poção cura o valor esperado")
	_assert(inv.potions == 0, "poção é consumida")
	inv.add_gold(15)
	inv.add_gold(5)
	_assert(inv.gold == 20, "add_gold acumula")

func _test_enemy_ai() -> void:
	print("[EnemyAI]")
	var d := DungeonData.new()
	for x in 5:
		for y in 5:
			d.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR
	var player := Entity.new("Jogador", Vector2i(2, 2), 20, 4)

	var adjacent_enemy := Entity.new("Perto", Vector2i(2, 1), 5, 2)
	var decision_attack: Dictionary = EnemyAI.decide(adjacent_enemy, player, d, {})
	_assert(decision_attack.action == "attack", "inimigo adjacente ataca")

	var near_enemy := Entity.new("Perseguidor", Vector2i(0, 0), 5, 2)
	var decision_move: Dictionary = EnemyAI.decide(near_enemy, player, d, {})
	_assert(decision_move.action == "move", "inimigo dentro do alcance de perseguição se move")
	var moved_to: Vector2i = decision_move.to
	_assert(d.is_floor(moved_to), "movimento decidido cai em piso válido")

	var far_enemy := Entity.new("Longe", Vector2i(0, 0), 5, 2)
	far_enemy.grid_pos = Vector2i(2, 2) + Vector2i(EnemyAI.AGGRO_RANGE + 2, 0)
	var decision_idle: Dictionary = EnemyAI.decide(far_enemy, player, d, {})
	_assert(decision_idle.action == "idle", "inimigo fora do alcance de perseguição fica parado")

# ---- cena principal ----

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["roguelike_runs_played", "roguelike_victories", "roguelike_total_gold"]:
		save_system.data.erase(key)
	save_system.save_data()

func _make_flat_dungeon(size: int = 5) -> DungeonData:
	var d := DungeonData.new()
	d.width = size
	d.height = size
	for x in size:
		for y in size:
			d.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR
	d.entrance = Vector2i(0, 0)
	d.exit = Vector2i(size - 1, size - 1)
	d.rooms = [Rect2i(0, 0, size, size)]
	return d

func _test_scene_initial_state() -> void:
	print("[main.tscn - estado inicial]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	_assert(packed != null, "carrega sem erro")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	_assert(instance.ui_root.theme != null, "UITheme foi aplicado")
	_assert(instance.state_machine.current_state.name == "Playing", "estado inicial é Playing")
	_assert(instance.player.hp == instance.STARTING_HP, "jogador começa com HP inicial")
	_assert(instance.player.grid_pos == instance.dungeon.entrance, "jogador começa na entrada do calabouço")

	instance.queue_free()
	await process_frame

func _test_bump_attack_kills_enemy() -> void:
	print("[Combate - bump attack mata inimigo fraco]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.start_new_run(_make_flat_dungeon())
	var weak_enemy := Entity.new("Fraco", Vector2i(1, 0), 3, 1)
	instance.enemies.append(weak_enemy)

	instance.try_move(Vector2i(1, 0))
	await process_frame

	_assert(instance.player.grid_pos == Vector2i(0, 0), "atacar não move o jogador pra célula do inimigo")
	_assert(instance.enemies.is_empty(), "inimigo com HP baixo morre num golpe (attack do jogador >= HP)")

	instance.queue_free()
	await process_frame

func _test_item_pickup() -> void:
	print("[Itens - pickup de poção e ouro]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var dungeon := _make_flat_dungeon()
	dungeon.items.append({"pos": Vector2i(1, 0), "type": "potion", "amount": 1})
	dungeon.items.append({"pos": Vector2i(2, 0), "type": "gold", "amount": 12})
	instance.start_new_run(dungeon)

	instance.try_move(Vector2i(1, 0))
	await process_frame
	_assert(instance.inventory.potions == 1, "poção no chão é coletada ao pisar em cima")
	_assert(instance.dungeon.item_at(Vector2i(1, 0)).is_empty(), "item coletado some do calabouço")

	instance.try_move(Vector2i(1, 0))
	await process_frame
	_assert(instance.inventory.gold == 12, "ouro no chão é coletado ao pisar em cima")

	instance.queue_free()
	await process_frame

func _test_reach_exit_triggers_victory() -> void:
	print("[Vitória - chegar na saída]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.start_new_run(_make_flat_dungeon())
	instance.player.grid_pos = Vector2i(3, 4)
	instance.inventory.add_gold(7)

	instance.try_move(Vector2i(1, 0))
	await process_frame

	_assert(instance.state_machine.current_state.name == "Victory", "chegar na saída transiciona pra Victory")
	_assert(instance.victory_overlay.visible, "overlay de vitória aparece")

	var save_system := root.get_node("/root/SaveSystem")
	_assert(save_system.get_value("roguelike_victories", 0) == 1, "vitória é persistida no SaveSystem")
	_assert(save_system.get_value("roguelike_total_gold", 0) == 7, "ouro coletado é somado ao total salvo")

	instance.queue_free()
	await process_frame

func _test_enemy_attack_triggers_game_over() -> void:
	print("[Derrota - inimigo mata o jogador]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.start_new_run(_make_flat_dungeon())
	instance.player.hp = 1
	var deadly_enemy := Entity.new("Fatal", Vector2i(1, 1), 999, 99)
	instance.enemies.append(deadly_enemy)

	instance.try_move(Vector2i(1, 0)) # jogador vai pra (1,0), inimigo em (1,1) fica adjacente e ataca
	await process_frame

	_assert(instance.player.hp == 0, "ataque fatal zera o HP do jogador")
	_assert(instance.state_machine.current_state.name == "GameOver", "HP zerado transiciona pra GameOver")
	_assert(instance.game_over_overlay.visible, "overlay de derrota aparece")

	var save_system := root.get_node("/root/SaveSystem")
	_assert(save_system.get_value("roguelike_runs_played", 0) == 1, "corrida derrotada conta em roguelike_runs_played")

	instance.queue_free()
	await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
