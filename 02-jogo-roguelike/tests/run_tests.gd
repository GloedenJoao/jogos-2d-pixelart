extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_test_dungeon_generator()
	_test_entity_and_combat()
	_test_inventory()
	_test_enemy_ai()
	_test_enemy_kinds()
	_test_meta_progression()
	await _test_scene_initial_state()
	await _test_bump_attack_kills_enemy()
	await _test_item_pickup()
	await _test_reach_exit_descends_to_next_floor()
	await _test_reach_exit_on_last_floor_triggers_victory()
	await _test_enemy_attack_triggers_game_over()
	await _test_upgrades_apply_to_run()
	await _test_buy_upgrade_spends_banked_gold()
	await _test_full_run_through_procedural_floors()
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

	rng.seed = 12345
	var shallow: DungeonData = DungeonGenerator.generate(40, 24, rng, 1)
	rng.seed = 12345
	var deep: DungeonData = DungeonGenerator.generate(40, 24, rng, 4)
	_assert(deep.floor_number == 4, "andar é registrado no calabouço gerado")
	_assert(deep.enemy_spawns.size() > shallow.enemy_spawns.size(), "andar mais fundo gera mais inimigos que o primeiro")

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

func _test_enemy_kinds() -> void:
	print("[EnemyKinds]")
	var floor1 := EnemyKinds.available_for_floor(1)
	var floor3 := EnemyKinds.available_for_floor(3)
	_assert(floor1.size() < floor3.size(), "andares mais fundos liberam mais tipos de criatura")
	for kind in floor1:
		_assert(kind.min_floor <= 1, "%s pode aparecer no primeiro andar" % kind.name)

	var hp_values := {}
	var attack_values := {}
	for kind in EnemyKinds.KINDS:
		hp_values[kind.hp] = true
		attack_values[kind.attack] = true
	_assert(hp_values.size() >= 3, "tipos têm HP variado (não são todos iguais)")
	_assert(attack_values.size() >= 3, "tipos têm ataque variado")

	var base: Dictionary = EnemyKinds.KINDS[0]
	var scaled_deep := EnemyKinds.scaled(base, 5)
	_assert(scaled_deep.hp > base.hp, "criatura no andar 5 tem mais HP que a base")
	_assert(scaled_deep.attack >= base.attack, "criatura no andar 5 não fica mais fraca")
	_assert(EnemyKinds.scaled(base, 1).hp == base.hp, "no primeiro andar os atributos são os da base")

	var enemy := EnemyKinds.make_entity(EnemyKinds.BOSS, Vector2i(2, 2), 5)
	_assert(enemy.get_meta("boss", false), "chefe é marcado como boss")
	_assert(enemy.hp > EnemyKinds.make_entity(EnemyKinds.KINDS[0], Vector2i.ZERO, 5).hp, "chefe é mais forte que criatura comum do mesmo andar")
	_assert(int(enemy.get_meta("aggro", 0)) == EnemyKinds.BOSS.aggro, "aggro do tipo vai pro meta da entidade")

	# A IA respeita o aggro individual: fungo é sedentário, morcego enxerga longe.
	var d := DungeonData.new()
	for x in 20:
		for y in 20:
			d.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR
	var player := Entity.new("Jogador", Vector2i(10, 10), 20, 4)
	var fungo := EnemyKinds.make_entity(EnemyKinds.find_kind("fungo"), Vector2i(15, 10), 3)
	var morcego := EnemyKinds.make_entity(EnemyKinds.find_kind("morcego"), Vector2i(15, 10), 3)
	_assert(EnemyAI.decide(fungo, player, d, {}).action == "idle", "fungo ignora o jogador a 5 células")
	_assert(EnemyAI.decide(morcego, player, d, {}).action == "move", "morcego persegue o jogador a 5 células")

func _test_meta_progression() -> void:
	print("[MetaProgression]")
	var levels := {}
	_assert(MetaProgression.get_level(levels, "vitalidade") == 0, "upgrade começa no nível 0")
	var first_cost := MetaProgression.cost_for(levels, "vitalidade")
	_assert(first_cost == MetaProgression.find("vitalidade").base_cost, "primeiro nível custa o custo-base")

	var poor := MetaProgression.purchase({"gold": first_cost - 1, "levels": levels}, "vitalidade")
	_assert(not poor.ok and poor.reason == "sem_ouro", "sem ouro suficiente a compra falha")
	_assert(MetaProgression.get_level(levels, "vitalidade") == 0, "compra falha não altera o estado original")

	var bought := MetaProgression.purchase({"gold": 100, "levels": levels}, "vitalidade")
	_assert(bought.ok, "com ouro suficiente a compra passa")
	_assert(bought.gold == 100 - first_cost, "ouro é descontado")
	_assert(MetaProgression.get_level(bought.levels, "vitalidade") == 1, "nível sobe pra 1")
	_assert(MetaProgression.cost_for(bought.levels, "vitalidade") > first_cost, "próximo nível custa mais caro")

	var maxed := {"vitalidade": MetaProgression.find("vitalidade").max_level}
	_assert(MetaProgression.is_maxed(maxed, "vitalidade"), "nível máximo é detectado")
	_assert(MetaProgression.cost_for(maxed, "vitalidade") == -1, "sem custo quando está no máximo")
	_assert(not MetaProgression.purchase({"gold": 9999, "levels": maxed}, "vitalidade").ok, "não dá pra passar do nível máximo")

	var full := {"vitalidade": 2, "forca": 1, "suprimentos": 3, "sorte": 2}
	_assert(MetaProgression.max_hp_for(full, 20) == 28, "vitalidade Nv2 dá +8 de HP máximo")
	_assert(MetaProgression.attack_for(full, 4) == 5, "força Nv1 dá +1 de ataque")
	_assert(MetaProgression.starting_potions(full) == 3, "suprimentos Nv3 dá 3 poções iniciais")
	_assert(MetaProgression.apply_gold_bonus(full, 100) == 130, "sorte Nv2 dá +30% de ouro")
	_assert(MetaProgression.apply_gold_bonus({}, 100) == 100, "sem upgrades o ouro não muda")

# ---- cena principal ----

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["roguelike_runs_played", "roguelike_victories", "roguelike_total_gold", "roguelike_deepest_floor", "roguelike_upgrades"]:
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

func _test_reach_exit_descends_to_next_floor() -> void:
	print("[Andares - saída leva ao próximo andar]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.start_new_run(_make_flat_dungeon())
	instance.player.hp = 10
	instance.player.grid_pos = Vector2i(3, 4)
	instance.inventory.add_gold(9)
	instance.inventory.add_potion(2)

	instance.try_move(Vector2i(1, 0))
	await process_frame

	_assert(instance.floor_number == 2, "chegar na saída do andar 1 desce pro andar 2")
	_assert(instance.state_machine.current_state.name == "Playing", "continua jogando (sem tela de vitória)")
	_assert(not instance.victory_overlay.visible, "overlay de vitória não aparece no meio da descida")
	_assert(instance.player.grid_pos == instance.dungeon.entrance, "jogador reaparece na entrada do novo andar")
	_assert(instance.dungeon.floor_number == 2, "novo calabouço sabe em que andar está")
	_assert(instance.inventory.gold == 9 and instance.inventory.potions == 2, "ouro e poções seguem com o jogador entre andares")
	_assert(instance.player.hp == 10 + instance.DESCEND_HEAL, "descer cura um pouco o jogador")

	var save_system := root.get_node("/root/SaveSystem")
	_assert(int(save_system.get_value("roguelike_runs_played", 0)) == 0, "descer não fecha a corrida")

	instance.queue_free()
	await process_frame

func _test_reach_exit_on_last_floor_triggers_victory() -> void:
	print("[Vitória - saída do último andar]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.start_new_run(_make_flat_dungeon(), instance.FLOORS_PER_RUN)
	instance.player.grid_pos = Vector2i(3, 4)
	instance.inventory.add_gold(7)

	instance.try_move(Vector2i(1, 0))
	await process_frame

	_assert(instance.state_machine.current_state.name == "Victory", "chegar na saída do último andar transiciona pra Victory")
	_assert(instance.victory_overlay.visible, "overlay de vitória aparece")

	var save_system := root.get_node("/root/SaveSystem")
	_assert(int(save_system.get_value("roguelike_victories", 0)) == 1, "vitória é persistida no SaveSystem")
	_assert(int(save_system.get_value("roguelike_total_gold", 0)) == 7, "ouro coletado é somado ao total salvo")
	_assert(int(save_system.get_value("roguelike_deepest_floor", 0)) == instance.FLOORS_PER_RUN, "andar mais fundo alcançado é salvo")

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

func _test_upgrades_apply_to_run() -> void:
	print("[Meta-progressão - upgrades valem na próxima corrida]")
	_reset_save()
	var save_system := root.get_node("/root/SaveSystem")
	save_system.set_value("roguelike_upgrades", {"vitalidade": 2, "forca": 1, "suprimentos": 2, "sorte": 2})
	save_system.save_data()

	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var dungeon := _make_flat_dungeon()
	dungeon.items.append({"pos": Vector2i(1, 0), "type": "gold", "amount": 10})
	instance.start_new_run(dungeon)

	_assert(instance.player.max_hp == instance.STARTING_HP + 8, "vitalidade Nv2 aumenta o HP máximo do jogador")
	_assert(instance.player.attack == instance.PLAYER_ATTACK + 1, "força Nv1 aumenta o ataque do jogador")
	_assert(instance.inventory.potions == 2, "suprimentos Nv2 dá 2 poções no começo da corrida")
	_assert(instance.floor_number == 1, "toda corrida recomeça no andar 1")

	instance.try_move(Vector2i(1, 0))
	await process_frame
	_assert(instance.inventory.gold == 13, "sorte Nv2 aplica +30% no ouro coletado (10 -> 13)")

	instance.queue_free()
	await process_frame

func _test_buy_upgrade_spends_banked_gold() -> void:
	print("[Acampamento - comprar upgrade com o ouro guardado]")
	_reset_save()
	var save_system := root.get_node("/root/SaveSystem")
	save_system.set_value("roguelike_total_gold", 50)
	save_system.save_data()

	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var cost := MetaProgression.cost_for({}, "vitalidade")
	_assert(instance.buy_upgrade("vitalidade"), "compra no acampamento passa com ouro suficiente")
	_assert(int(save_system.get_value("roguelike_total_gold", 0)) == 50 - cost, "ouro guardado é debitado e persistido")
	_assert(MetaProgression.get_level(instance.load_meta_levels(), "vitalidade") == 1, "nível do upgrade é persistido")

	_assert(not instance.buy_upgrade("sorte"), "compra sem ouro suficiente é recusada")
	_assert(int(save_system.get_value("roguelike_total_gold", 0)) == 50 - cost, "compra recusada não mexe no ouro")

	instance.open_camp(instance.game_over_overlay)
	_assert(instance.camp_overlay.visible, "abrir acampamento mostra o painel")
	_assert(not instance.game_over_overlay.visible, "painel anterior some enquanto o acampamento está aberto")
	instance.close_camp()
	_assert(not instance.camp_overlay.visible and instance.game_over_overlay.visible, "voltar fecha o acampamento e devolve o painel anterior")

	instance.start_new_run(_make_flat_dungeon())
	_assert(instance.player.max_hp == instance.STARTING_HP + MetaProgression.find("vitalidade").amount, "a corrida seguinte já nasce com o upgrade comprado")

	instance.queue_free()
	await process_frame

# Corrida inteira em calabouços procedurais (não forçados), pra pegar erro de
# geração/spawn nos andares mais fundos e a aparição do chefe no último.
func _test_full_run_through_procedural_floors() -> void:
	print("[Corrida completa - 5 andares procedurais]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.start_new_run()
	var floors_seen: Array[int] = []
	var boss_seen := false

	for _i in instance.FLOORS_PER_RUN:
		floors_seen.append(instance.floor_number)
		for enemy in instance.enemies:
			if enemy.get_meta("boss", false):
				boss_seen = true
		# Teleporta pra uma célula adjacente à saída e dá o último passo pelo jogo.
		# Sem inimigos no caminho, o passo é movimento e não bump attack.
		instance.enemies.clear()
		instance.player.hp = 999
		instance.player.grid_pos = instance.dungeon.exit - Vector2i(1, 0)
		if not instance.dungeon.is_floor(instance.player.grid_pos):
			instance.player.grid_pos = instance.dungeon.exit - Vector2i(0, 1)
			instance.try_move(Vector2i(0, 1))
		else:
			instance.try_move(Vector2i(1, 0))
		await process_frame

	_assert(floors_seen == [1, 2, 3, 4, 5], "a corrida passa pelos 5 andares em ordem")
	_assert(boss_seen, "o chefe aparece em algum andar da corrida (último)")
	_assert(instance.state_machine.current_state.name == "Victory", "sair do último andar termina a corrida em vitória")
	_assert(int(root.get_node("/root/SaveSystem").get_value("roguelike_deepest_floor", 0)) == 5, "andar mais fundo salvo é 5")

	instance.queue_free()
	await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
