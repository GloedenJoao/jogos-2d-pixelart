class_name PlayingState
extends State

var game: Node2D

func enter(_params: Dictionary = {}) -> void:
	game.set_message("Explore a caverna e encontre a saída.")

func handle_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_W, KEY_UP:
			game.try_move(Vector2i(0, -1))
		KEY_S, KEY_DOWN:
			game.try_move(Vector2i(0, 1))
		KEY_A, KEY_LEFT:
			game.try_move(Vector2i(-1, 0))
		KEY_D, KEY_RIGHT:
			game.try_move(Vector2i(1, 0))
		KEY_U:
			game.try_use_potion()
