extends SceneTree

# Screenshots automatizados das telas-chave. Roda via:
#   Godot_..._console.exe --path . --script res://tests/visual_capture.gd
# PNGs em res://.visual_capture/ (gitignored), lidos direto com a ferramenta Read.

const OUT_DIR := "res://.visual_capture"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_inicio()
	await _capture_gaveta_aberta()
	await _capture_colonia_viva()
	await _capture_colonia_grande()

	print("Capturas salvas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase("colonia")
	save_system.save_data()

func _new_game() -> Node:
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	return instance

func _open_drawer(instance) -> void:
	instance.toggle_drawer()
	instance.drawer.position.x = 1280.0 - instance.DRAWER_WIDTH  # sem esperar a animação

# Avança a simulação de verdade (needs, decisões, caminhada) por N segundos.
func _simulate(instance, seconds: float) -> void:
	var step := 0.5
	var passos := int(seconds / step)
	for _i in passos:
		instance._process(step)

func _shoot(scenario_name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, scenario_name])
	print("  capturado: %s.png" % scenario_name)

func _capture_inicio() -> void:
	var instance = await _new_game()
	_simulate(instance, 2.0)
	instance.set_message("Cinco pessoas, um vale e nenhuma construção ainda.")
	await _shoot("01_vale_inicial")
	instance.queue_free()
	await process_frame

func _capture_gaveta_aberta() -> void:
	var instance = await _new_game()
	instance.economy.add("comida", 260.0)
	instance.economy.add("materiais", 90.0)
	instance.economy.owned = {"coletor": 4, "lascador": 2}
	instance.population.sync_work_sites(instance.economy)
	instance.population.assign_jobs()
	instance._rebuild_plots()
	_simulate(instance, 30.0)
	_open_drawer(instance)
	instance.set_message("A loja é uma gaveta: só cobre o mundo enquanto está aberta.")
	await _shoot("02_gaveta_aberta")
	instance.queue_free()
	await process_frame

func _capture_colonia_viva() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 1
	instance.economy.owned = {"coletor": 5, "lascador": 3, "fogueira": 2, "fazenda": 4, "oleiro": 2}
	instance.economy.add("comida", 3000.0)
	instance.economy.add("materiais", 900.0)
	instance.on_era_entered(1)
	instance.close_era_overlay()
	instance.population.sync_work_sites(instance.economy)
	instance.population.ensure_minimum(22)
	instance.population.assign_jobs()
	_simulate(instance, 150.0)
	instance.set_message("Cada morador decide sozinho: trabalhar, comer ou descansar.")
	await _shoot("03_colonia_viva")
	instance.queue_free()
	await process_frame

func _capture_colonia_grande() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 3
	instance.economy.owned = {
		"coletor": 12, "lascador": 8, "fogueira": 5,
		"fazenda": 9, "oleiro": 6, "escriba": 4,
		"mercado": 5, "mina": 4, "biblioteca": 3,
		"moinho_vapor": 3, "fabrica": 2, "escola": 2,
	}
	instance.economy.add("comida", 90000.0)
	instance.economy.add("materiais", 42000.0)
	instance.economy.add("conhecimento", 6400.0)
	instance.on_era_entered(3)
	instance.close_era_overlay()
	instance.population.sync_work_sites(instance.economy)
	instance.population.ensure_minimum(70)
	instance.population.assign_jobs()
	_simulate(instance, 150.0)
	instance.set_message("Era Industrial: a colônia inteira em movimento.")
	await _shoot("04_colonia_grande")
	instance.queue_free()
	await process_frame
