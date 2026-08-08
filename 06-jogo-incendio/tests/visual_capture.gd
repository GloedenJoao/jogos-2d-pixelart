extends SceneTree

# Screenshots automatizados das telas-chave. Roda via:
#   Godot_..._console.exe --path . --script res://tests/visual_capture.gd
# PNGs em res://.visual_capture/ (fora do git), lidos direto com a ferramenta Read.
#
# É o método padrão do repositório desde o Projeto 3: revisar o visual sem
# depender de alguém abrir o editor e jogar. Aqui ele vale ainda mais, porque
# quase tudo que importa na tela é ANIMADO (chama, fumaça, brasa, gente
# andando) e só existe num instante específico da partida.

const OUT_DIR := "res://.visual_capture"
const STEP := 0.1

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_briefing()
	await _capture_early()
	await _capture_working()
	await _capture_risk_overlay()
	await _capture_big_fire()
	await _capture_wind_level()
	await _capture_result()

	print("Capturas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _new_game(level_index: int = 0) -> Node:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase(Mission.SAVE_KEY)
	save_system.save_data()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	instance.start_level(level_index)
	instance.machine.transition_to("playing")
	await process_frame
	return instance

# Avança a partida de verdade (fogo, decisões, caminhada) por N segundos.
func _simulate(instance, seconds: float, bot: bool = true) -> void:
	instance.bot_active = bot
	for _i in int(seconds / STEP):
		if instance.mission.phase != Mission.PLAYING:
			break
		if bot:
			instance.bot.update(STEP)
		instance.mission.update(STEP)
	instance.refresh_forecast(1.0)

func _shoot(instance, scenario_name: String) -> void:
	instance.queue_redraw()
	# Frames de verdade antes do clique: a chama e a fumaça se movem em função
	# do relógio da cena, e com dois frames toda captura sai no mesmo quadro
	# de animação.
	for _i in 30:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, scenario_name])
	print("  %s" % scenario_name)

func _capture_briefing() -> void:
	var instance = await _new_game(0)
	instance.machine.transition_to("briefing")
	await _shoot(instance, "01_briefing")
	instance.queue_free()

func _capture_early() -> void:
	var instance = await _new_game(0)
	_simulate(instance, 12.0)
	await _shoot(instance, "02_foco_inicial")
	instance.queue_free()

func _capture_working() -> void:
	var instance = await _new_game(0)
	_simulate(instance, 40.0)
	await _shoot(instance, "03_turma_trabalhando")
	instance.queue_free()

func _capture_risk_overlay() -> void:
	var instance = await _new_game(0)
	_simulate(instance, 30.0)
	instance.show_risk = true
	instance.refresh_forecast(1.0)
	await _shoot(instance, "04_overlay_risco")
	instance.queue_free()

func _capture_big_fire() -> void:
	var instance = await _new_game(2)
	_simulate(instance, 55.0)
	await _shoot(instance, "05_incendio_grande")
	instance.queue_free()

func _capture_wind_level() -> void:
	var instance = await _new_game(4)
	_simulate(instance, 45.0)
	await _shoot(instance, "06_brasas_vento")
	instance.queue_free()

func _capture_result() -> void:
	var instance = await _new_game(0)
	_simulate(instance, 200.0)
	instance.machine.transition_to("result")
	await _shoot(instance, "07_resultado")
	instance.queue_free()
