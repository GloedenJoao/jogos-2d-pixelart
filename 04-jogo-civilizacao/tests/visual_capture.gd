extends SceneTree

# Screenshots automatizados das telas-chave. Roda via:
#   Godot_..._console.exe --path . --script res://tests/visual_capture.gd
# PNGs em res://.visual_capture/ (gitignored), lidos direto com a ferramenta Read.

const OUT_DIR := "res://.visual_capture"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_start()
	await _capture_growing_village()
	await _capture_era_overlay()
	await _capture_late_game()

	print("Capturas salvas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase("civilizacao")
	save_system.save_data()

func _new_game() -> Node:
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	return instance

func _shoot(scenario_name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, scenario_name])
	print("  capturado: %s.png" % scenario_name)

func _capture_start() -> void:
	var instance = await _new_game()
	for _i in 5:
		instance.gather("comida")
	instance._update_hud()
	await _shoot("01_idade_da_pedra")
	instance.queue_free()
	await process_frame

func _capture_growing_village() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 1
	instance.economy.owned = {"coletor": 6, "lascador": 4, "fogueira": 2, "fazenda": 3, "oleiro": 2}
	instance.economy.add("comida", 480.0)
	instance.economy.add("materiais", 260.0)
	instance.economy.add("conhecimento", 35.0)
	instance.on_era_entered(1)
	instance.close_era_overlay()
	instance.set_message("A vila cresce: cada construção continua produzindo sozinha.")
	await _shoot("02_vila_agricultura")
	instance.queue_free()
	await process_frame

func _capture_era_overlay() -> void:
	var instance = await _new_game()
	instance.economy.owned = {"coletor": 8, "lascador": 6, "fogueira": 3}
	var requirement := Eras.requirement(0)
	for resource in requirement:
		instance.economy.add(resource, float(requirement[resource]))
	instance._update_hud()
	instance.advance_era()
	await _shoot("03_virada_de_era")
	instance.queue_free()
	await process_frame

func _capture_late_game() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 4
	instance.economy.owned = {
		"coletor": 25, "lascador": 20, "fogueira": 12,
		"fazenda": 18, "oleiro": 14, "escriba": 10,
		"mercado": 9, "mina": 8, "biblioteca": 6,
		"moinho_vapor": 5, "fabrica": 5, "escola": 4,
		"agroindustria": 3, "usina": 2, "universidade": 1,
	}
	instance.economy.add("comida", 1850000.0)
	instance.economy.add("materiais", 920000.0)
	instance.economy.add("conhecimento", 145000.0)
	instance.on_era_entered(4)
	instance.close_era_overlay()
	instance.set_message("Era da Informação: a civilização inteira produzindo sozinha.")
	await _shoot("04_era_da_informacao")
	instance.queue_free()
	await process_frame
