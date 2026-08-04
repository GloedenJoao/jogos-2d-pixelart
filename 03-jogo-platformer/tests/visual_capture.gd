extends SceneTree

# Screenshots automatizados dos cenários-chave, sem clique manual. Roda via:
#   Godot_..._console.exe --path . --script res://tests/visual_capture.gd
# Os PNGs saem em res://.visual_capture/ (fora do controle de versão) e podem ser
# lidos direto com a ferramenta Read.

const OUT_DIR := "res://.visual_capture"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_era_gameplay(0, 150, "01_caverna")
	await _capture_era_gameplay(1, 220, "02_vila_pulo_duplo")
	await _capture_era_gameplay(2, 260, "03_industria_dash")
	await _capture_climbing_platforms()
	await _capture_era_complete()
	await _capture_game_complete()

	print("Capturas salvas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["platformer_era_reached", "platformer_completed", "platformer_best_gems", "platformer_deaths"]:
		save_system.data.erase(key)
	save_system.save_data()

func _new_game(era_index: int) -> Node:
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	instance.start_game(era_index)
	await physics_frame
	return instance

func _shoot(scenario_name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, scenario_name])
	print("  capturado: %s.png" % scenario_name)

# Deixa o piloto automático jogar e fotografa no meio da ação.
func _capture_era_gameplay(era_index: int, frames: int, scenario_name: String) -> void:
	var instance = await _new_game(era_index)
	var bot := DemoBot.new()
	for _i in frames:
		if instance.state_machine.current_state.name != "Playing":
			break
		bot.step(instance)
		await physics_frame
	await _shoot(scenario_name)
	instance.queue_free()
	await process_frame

# Jogador em cima das plataformas de gema, pra mostrar a verticalidade da fase.
func _capture_climbing_platforms() -> void:
	var instance = await _new_game(0)
	var gem: Vector2i = instance.level.gems[0]
	instance._place_player(gem + Vector2i(1, 0))
	instance.set_message("Gemas ficam nas plataformas altas.")
	for _i in 8:
		instance.player.set_input(0.0, false)
		await physics_frame
	await _shoot("04_plataformas")
	instance.queue_free()
	await process_frame

func _capture_era_complete() -> void:
	var instance = await _new_game(0)
	instance.gems_taken = 3
	instance.deaths = 1
	instance._place_player(instance.level.exit_cell)
	await physics_frame
	await _shoot("05_era_concluida")
	instance.queue_free()
	await process_frame

func _capture_game_complete() -> void:
	var instance = await _new_game(Levels.count() - 1)
	instance.total_gems = 11
	instance.gems_taken = 4
	instance.deaths = 3
	instance._place_player(instance.level.exit_cell)
	await physics_frame
	await _shoot("06_fim_da_jornada")
	instance.queue_free()
	await process_frame
