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

	await _capture_betting()
	await _capture_player_turn()
	await _capture_blackjack_resolve()
	await _capture_stats_overlay()

	print("Capturas salvas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["blackjack_balance", "blackjack_last_bet", "blackjack_hands_played", "blackjack_hands_won", "blackjack_best_balance"]:
		save_system.data.erase(key)
	save_system.save_data()

func _force_deck(instance: Node, draw_order: Array) -> void:
	# draw() usa pop_back(), então quem compra primeiro tem que estar no fim do array.
	var reversed: Array = draw_order.duplicate()
	reversed.reverse()
	instance.deck.cards.assign(reversed)

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

func _capture_betting() -> void:
	_reset_save()
	var instance = await _new_instance()
	await _shoot("01_betting")
	instance.queue_free()
	await process_frame

func _capture_player_turn() -> void:
	_reset_save()
	var instance = await _new_instance()
	instance.bet = 50
	_force_deck(instance, [
		Card.new(Card.Suit.SPADES, 9),   # jogador: 10
		Card.new(Card.Suit.HEARTS, 5),   # dealer: 6
		Card.new(Card.Suit.CLUBS, 6),    # jogador: 7 -> 17
		Card.new(Card.Suit.DIAMONDS, 5), # dealer (oculta): 6
	])
	instance.state_machine.current_state.on_deal()
	await create_timer(0.6).timeout # espera a animação de distribuir cartas terminar
	await _shoot("02_player_turn")
	instance.queue_free()
	await process_frame

func _capture_blackjack_resolve() -> void:
	_reset_save()
	var instance = await _new_instance()
	instance.bet = 20
	_force_deck(instance, [
		Card.new(Card.Suit.SPADES, 0),   # jogador: Ás
		Card.new(Card.Suit.HEARTS, 4),   # dealer: 5
		Card.new(Card.Suit.CLUBS, 12),   # jogador: K -> 21 (blackjack)
		Card.new(Card.Suit.DIAMONDS, 5), # dealer: 6 -> 11
	])
	instance.state_machine.current_state.on_deal()
	await create_timer(0.6).timeout
	await _shoot("03_blackjack_resolve")
	instance.queue_free()
	await process_frame

func _capture_stats_overlay() -> void:
	_reset_save()
	var save_system := root.get_node("/root/SaveSystem")
	save_system.set_value("blackjack_hands_played", 12)
	save_system.set_value("blackjack_hands_won", 7)
	save_system.set_value("blackjack_best_balance", 780)
	save_system.save_data()
	var instance = await _new_instance()
	instance._toggle_stats()
	await _shoot("04_stats_overlay")
	instance.queue_free()
	await process_frame
