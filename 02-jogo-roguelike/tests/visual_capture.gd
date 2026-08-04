extends SceneTree

# Captura screenshots automatizados de cenários-chave do jogo, sem depender de
# clique manual (computer-use). Roda via:
#   Godot_..._console.exe --path <projeto> --script res://tests/visual_capture.gd
# Gera PNGs em res://.visual_capture/ (fora do controle de versão) que podem
# ser lidos diretamente com a ferramenta Read.

const OUT_DIR := "res://.visual_capture"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_exploring()
	await _capture_combat()
	await _capture_victory()
	await _capture_game_over()

	print("Capturas salvas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["roguelike_runs_played", "roguelike_victories", "roguelike_total_gold"]:
		save_system.data.erase(key)
	save_system.save_data()

func _new_instance() -> Node:
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

func _make_flat_dungeon(size: int = 10) -> DungeonData:
	var d := DungeonData.new()
	d.width = size
	d.height = size
	for x in size:
		for y in size:
			d.cells[Vector2i(x, y)] = DungeonData.Cell.FLOOR
	d.entrance = Vector2i(1, 1)
	d.exit = Vector2i(size - 2, size - 2)
	d.rooms = [Rect2i(0, 0, size, size)]
	d.items.append({"pos": Vector2i(3, 1), "type": "potion", "amount": 1})
	d.items.append({"pos": Vector2i(4, 1), "type": "gold", "amount": 10})
	return d

func _capture_exploring() -> void:
	_reset_save()
	var instance = await _new_instance()
	await _shoot("01_exploring")
	instance.queue_free()
	await process_frame

func _capture_combat() -> void:
	_reset_save()
	var instance = await _new_instance()
	instance.start_new_run(_make_flat_dungeon())
	instance.player.hp = 12
	var enemy := Entity.new("Limo", Vector2i(3, 2), 6, 2)
	enemy.set_meta("tile", Vector2i(0, 9))
	instance.enemies.append(enemy)
	instance._rebuild_enemy_sprites()
	instance.try_move(Vector2i(1, 0))
	instance.try_move(Vector2i(1, 0))
	instance.set_message("Você ataca Limo (-4 HP).")
	instance._render()
	await _shoot("02_combat")
	instance.queue_free()
	await process_frame

func _capture_victory() -> void:
	_reset_save()
	var instance = await _new_instance()
	instance.start_new_run(_make_flat_dungeon())
	instance.inventory.add_gold(23)
	instance.player.grid_pos = instance.dungeon.exit - Vector2i(1, 0)
	instance.try_move(Vector2i(1, 0))
	await _shoot("03_victory")
	instance.queue_free()
	await process_frame

func _capture_game_over() -> void:
	_reset_save()
	var instance = await _new_instance()
	instance.start_new_run(_make_flat_dungeon())
	instance.player.hp = 1
	var enemy := Entity.new("Fatal", Vector2i(2, 1), 999, 99)
	enemy.set_meta("tile", Vector2i(2, 9))
	instance.enemies.append(enemy)
	instance.try_move(Vector2i(1, 0))
	await _shoot("04_game_over")
	instance.queue_free()
	await process_frame
