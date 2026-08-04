extends SceneTree

# Testes headless do platformer. Além das checagens de dados (mapas, habilidades),
# roda a física de verdade: o jogador é controlado por um "bot" que segura as
# mesmas teclas que um humano seguraria, e cada era precisa ser terminável.

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_test_level_data()
	_test_levels_are_playable_maps()
	_test_abilities()
	await _test_scene_boots()
	await _test_gravity_and_walk()
	await _test_jump()
	await _test_double_jump_only_after_unlock()
	await _test_dash_only_in_last_era()
	await _test_gem_pickup()
	await _test_spike_hurts_and_respawns_at_checkpoint()
	await _test_stomp_defeats_enemy()
	await _test_fall_out_of_level_costs_heart()
	await _test_exit_completes_era_and_saves()
	await _test_bot_finishes_every_era()
	_report()

func _assert(cond: bool, message: String) -> void:
	if cond:
		_pass += 1
		print("  OK   - %s" % message)
	else:
		_fail += 1
		print("  FAIL - %s" % message)

# ---- dados ----

func _test_level_data() -> void:
	print("[LevelData]")
	var data := LevelData.parse([
		"....G.",
		"..P..E",
		"###^##",
	])
	_assert(data.width == 6 and data.height == 3, "tamanho vem do mapa")
	_assert(data.spawn == Vector2i(2, 1), "spawn lido do 'P'")
	_assert(data.exit_cell == Vector2i(5, 1), "saída lida do 'E'")
	_assert(data.gems == [Vector2i(4, 0)], "gema lida do 'G'")
	_assert(data.spikes == [Vector2i(3, 2)], "espinho lido do '^'")
	_assert(data.is_solid(Vector2i(0, 2)) and not data.is_solid(Vector2i(0, 0)), "sólidos vêm do '#'")
	_assert(not data.is_inside(Vector2i(9, 9)), "célula fora do mapa é detectada")

func _test_levels_are_playable_maps() -> void:
	print("[Levels - sanidade dos mapas]")
	_assert(Levels.count() == 3, "três eras definidas")
	for i in Levels.count():
		var era := Levels.era(i)
		var data := Levels.level_data(i)
		var widths := {}
		for row in era.map:
			widths[row.length()] = true
		_assert(widths.size() == 1, "%s: todas as linhas do mapa têm a mesma largura" % era.id)
		_assert(data.spawn != data.exit_cell, "%s: spawn e saída são células diferentes" % era.id)
		_assert(data.is_solid(data.spawn + Vector2i(0, 1)), "%s: jogador nasce em cima de chão" % era.id)
		_assert(data.is_solid(data.exit_cell + Vector2i(0, 1)), "%s: a porta fica apoiada no chão" % era.id)
		_assert(data.gems.size() >= 4, "%s: tem gemas pra coletar" % era.id)
		_assert(data.enemies.size() >= 1 and data.spikes.size() >= 1, "%s: tem inimigos e espinhos" % era.id)
		_assert(data.checkpoints.size() >= 1, "%s: tem pelo menos um checkpoint" % era.id)

func _test_abilities() -> void:
	print("[Abilities]")
	var era0 := Abilities.for_era(0)
	_assert(not era0.double_jump and not era0.dash, "era 1 só tem andar e pular")
	var era1 := Abilities.for_era(1)
	_assert(era1.double_jump and not era1.dash, "era 2 destrava o pulo duplo")
	var era2 := Abilities.for_era(2)
	_assert(era2.double_jump and era2.dash, "era 3 acumula pulo duplo e dash")
	_assert(Abilities.unlocked_in(1) == "double_jump", "a era 2 é a que destrava o pulo duplo")

# ---- cena ----

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["platformer_era_reached", "platformer_completed", "platformer_best_gems", "platformer_deaths"]:
		save_system.data.erase(key)
	save_system.save_data()

func _new_game(era_index: int = 0) -> Node:
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	instance.start_game(era_index)
	instance.player.set_input(0.0, false)
	await physics_frame
	return instance

func _step(instance, frames: int, dir: float = 0.0, jump: bool = false, dash: bool = false) -> void:
	for _i in frames:
		instance.player.set_input(dir, jump, dash)
		await physics_frame

func _settle(instance, frames: int = 30) -> void:
	await _step(instance, frames, 0.0, false)

func _test_scene_boots() -> void:
	print("[Cena - boot]")
	var instance = await _new_game()
	_assert(instance.ui_root.theme != null, "UITheme aplicado")
	_assert(instance.state_machine.current_state.name == "Playing", "começa jogando")
	_assert(instance.era_index == 0, "começa na primeira era")
	_assert(instance.player != null and instance.player.state_machine != null, "jogador tem máquina de estados de animação")
	_assert(instance.enemies.size() == instance.level.enemies.size(), "inimigos do mapa foram instanciados")
	_assert(instance.hearts == instance.START_HEARTS, "começa com todos os corações")
	instance.queue_free()
	await process_frame

func _test_gravity_and_walk() -> void:
	print("[Física - gravidade e caminhada]")
	var instance = await _new_game()
	var player = instance.player
	player.global_position.y -= 30.0
	await _settle(instance, 40)
	_assert(player.is_on_floor(), "o jogador cai e pousa no chão")
	_assert(player.state_name() == "Idle", "parado no chão fica no estado Idle")

	var x0: float = player.global_position.x
	await _step(instance, 30, 1.0, false)
	_assert(player.global_position.x > x0 + 20.0, "andar pra direita move o jogador")
	_assert(player.state_name() == "Run", "andando o estado vira Run")
	_assert(player.facing == 1, "o jogador olha pra direita")

	await _step(instance, 30, -1.0, false)
	_assert(player.facing == -1, "andar pra esquerda inverte o lado que ele olha")

	await _settle(instance, 30)
	_assert(player.state_name() == "Idle", "sem input ele volta pro Idle")
	instance.queue_free()
	await process_frame

func _test_jump() -> void:
	print("[Física - pulo]")
	var instance = await _new_game()
	var player = instance.player
	await _settle(instance, 20)
	var y0: float = player.global_position.y

	await _step(instance, 1, 0.0, true)
	_assert(player.state_name() == "Jump", "apertar pulo entra no estado Jump")
	var peak: float = y0
	for _i in 40:
		player.set_input(0.0, true)
		await physics_frame
		peak = minf(peak, player.global_position.y)
	_assert(y0 - peak > 40.0, "o pulo levanta mais de 2 tiles (subiu %.0f px)" % (y0 - peak))

	await _settle(instance, 60)
	_assert(player.is_on_floor(), "ele volta pro chão")
	_assert(absf(player.global_position.y - y0) < 2.0, "pousa na mesma altura de onde saiu")
	instance.queue_free()
	await process_frame

func _peak_after_jump(instance, use_double: bool) -> float:
	var player = instance.player
	await _settle(instance, 20)
	var y0: float = player.global_position.y
	var peak := y0
	var pressed_second := false
	for i in 60:
		var jump := true
		if use_double and player.velocity.y > 0.0 and not pressed_second:
			# solta um frame e aperta de novo pra disparar o segundo pulo
			jump = i % 2 == 1
			if jump:
				pressed_second = true
		player.set_input(0.0, jump)
		await physics_frame
		peak = minf(peak, player.global_position.y)
	return y0 - peak

func _test_double_jump_only_after_unlock() -> void:
	print("[Pulo duplo - só a partir da era 2]")
	var instance = await _new_game(0)
	var single: float = await _peak_after_jump(instance, true)
	_assert(instance.player.abilities.double_jump == false, "na era 1 o pulo duplo está travado")
	instance.queue_free()
	await process_frame

	var instance2 = await _new_game(1)
	var double: float = await _peak_after_jump(instance2, true)
	_assert(instance2.player.abilities.double_jump == true, "na era 2 o pulo duplo está destravado")
	_assert(double > single + 15.0, "com pulo duplo ele sobe bem mais (%.0f px contra %.0f px)" % [double, single])
	instance2.queue_free()
	await process_frame

func _test_dash_only_in_last_era() -> void:
	print("[Dash - só na era 3]")
	var instance = await _new_game(1)
	var player = instance.player
	await _settle(instance, 20)
	var x0: float = player.global_position.x
	await _step(instance, 12, 1.0, false, true)
	var without_dash: float = player.global_position.x - x0
	_assert(player.state_name() != "Dash", "na era 2 apertar dash não faz nada")
	instance.queue_free()
	await process_frame

	var instance2 = await _new_game(2)
	var player2 = instance2.player
	await _settle(instance2, 20)
	player2.facing = 1
	var x1: float = player2.global_position.x
	await _step(instance2, 1, 1.0, false, true)
	_assert(player2.state_name() == "Dash", "na era 3 o dash entra no estado Dash")
	await _step(instance2, 11, 1.0, false, true)
	var with_dash: float = player2.global_position.x - x1
	_assert(with_dash > without_dash + 10.0, "o dash cobre mais distância no mesmo tempo (%.0f px contra %.0f px)" % [with_dash, without_dash])
	instance2.queue_free()
	await process_frame

func _test_gem_pickup() -> void:
	print("[Gemas]")
	var instance = await _new_game()
	var gem_cell: Vector2i = instance.level.gems[0]
	instance._place_player(gem_cell)
	await physics_frame
	_assert(instance.gems_taken == 1, "encostar na gema coleta")
	_assert(not instance._gem_nodes.has(gem_cell), "a gema some do mundo")
	instance.queue_free()
	await process_frame

func _test_spike_hurts_and_respawns_at_checkpoint() -> void:
	print("[Espinhos e checkpoint]")
	var instance = await _new_game()
	var checkpoint: Vector2i = instance.level.checkpoints[0]
	instance._place_player(checkpoint)
	await physics_frame
	_assert(instance.respawn_cell == checkpoint, "encostar no checkpoint muda o ponto de respawn")

	var hearts_before: int = instance.hearts
	instance._place_player(instance.level.spikes[0])
	await physics_frame
	_assert(instance.hearts == hearts_before - 1, "espinho custa um coração")
	_assert(instance._cell_of(instance.player.global_position) == checkpoint, "ele volta pro checkpoint, não pro início")
	instance.queue_free()
	await process_frame

func _test_stomp_defeats_enemy() -> void:
	print("[Inimigos - pisão]")
	var instance = await _new_game()
	var enemy = instance.enemies[0]
	var player = instance.player
	await _settle(instance, 10)
	player.global_position = enemy.global_position + Vector2(0, -14)
	player.velocity = Vector2(0, 120)
	await physics_frame
	_assert(not enemy.alive, "cair em cima derrota o inimigo")
	_assert(player.velocity.y < 0.0, "o jogador quica depois do pisão")
	_assert(instance.hearts == instance.START_HEARTS, "pisar não custa coração")

	var enemy2 = instance.enemies[1] if instance.enemies.size() > 1 else null
	if enemy2:
		instance._invulnerable = 0.0
		player.global_position = enemy2.global_position
		player.velocity = Vector2.ZERO
		await physics_frame
		_assert(instance.hearts == instance.START_HEARTS - 1, "encostar de lado custa um coração")
	instance.queue_free()
	await process_frame

func _test_fall_out_of_level_costs_heart() -> void:
	print("[Queda no vazio]")
	var instance = await _new_game()
	var hearts_before: int = instance.hearts
	instance.player.global_position.y = (instance.level.height + 4) * instance.TILE
	await physics_frame
	_assert(instance.hearts == hearts_before - 1, "cair pra fora do mapa custa um coração")
	_assert(instance.player.global_position.y < instance.level.height * instance.TILE, "ele reaparece dentro do mapa")
	instance.queue_free()
	await process_frame

func _test_exit_completes_era_and_saves() -> void:
	print("[Conclusão de era]")
	var instance = await _new_game(0)
	instance._place_player(instance.level.exit_cell)
	await physics_frame
	_assert(instance.state_machine.current_state.name == "EraComplete", "chegar na porta conclui a era")
	_assert(instance.era_overlay.visible, "overlay de era concluída aparece")

	instance._dispatch("on_continue")
	await physics_frame
	_assert(instance.era_index == 1, "o botão leva pra próxima era")
	_assert(instance.player.abilities.double_jump, "a era nova já entra com a habilidade destravada")
	_assert(int(root.get_node("/root/SaveSystem").get_value("platformer_era_reached", 0)) == 1, "progresso de era é salvo")

	instance.load_era(Levels.count() - 1)
	instance._place_player(instance.level.exit_cell)
	await physics_frame
	_assert(instance.state_machine.current_state.name == "GameComplete", "a porta da última era termina o jogo")
	_assert(root.get_node("/root/SaveSystem").get_value("platformer_completed", false) == true, "conclusão do jogo é salva")
	instance.queue_free()
	await process_frame

# ---- bot: cada era precisa ser terminável ----

func _test_bot_finishes_every_era() -> void:
	print("[Bot - cada era é terminável de ponta a ponta]")
	var bot := DemoBot.new()
	for era_index in Levels.count():
		var instance = await _new_game(era_index)
		bot.reset()
		var finished := false
		var frames := 0
		while frames < 3600 and not finished:
			if instance.state_machine.current_state.name != "Playing":
				finished = true
				break
			bot.step(instance)
			await physics_frame
			frames += 1
		var era_name: String = Levels.era(era_index).name
		_assert(finished, "%s: o bot chega na porta segurando direita e pulando (%d frames)" % [era_name, frames])
		_assert(instance.hearts > 0, "%s: o bot termina sem perder todos os corações" % era_name)
		instance.queue_free()
		await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
