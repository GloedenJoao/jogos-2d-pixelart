extends SceneTree

# Diagnóstico do piloto automático (DemoBot): mostra o trajeto e onde ele empaca
# em cada era. Útil quando um mapa novo deixa de ser terminável.
#   Godot_..._console.exe --headless --path . --script res://tests/bot_debug.gd

func _initialize() -> void:
	await process_frame
	for era_index in Levels.count():
		await _run(era_index)
	quit(0)

func _run(era_index: int) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	instance.start_game(era_index)
	await physics_frame

	print("== era %d (%s) ==" % [era_index, Levels.era(era_index).name])
	var bot := DemoBot.new()
	var best_column := -1
	var stuck := 0
	for frame in 2400:
		if instance.state_machine.current_state.name != "Playing":
			print("  terminou no frame %d (corações: %d, gemas: %d)" % [frame, instance.hearts, instance.gems_taken])
			break
		bot.step(instance)
		await physics_frame
		var cell: Vector2i = instance._cell_of(instance.player.global_position)
		if cell.x > best_column:
			best_column = cell.x
			stuck = 0
		else:
			stuck += 1
		if frame % 60 == 0:
			print("  frame %4d cell %s estado %s hp %d" % [frame, cell, instance.player.state_name(), instance.hearts])
		if stuck >= 300:
			print("  >> travado: chegou até a coluna %d de %d (hp %d)" % [best_column, instance.level.width, instance.hearts])
			break
	instance.queue_free()
	await process_frame
