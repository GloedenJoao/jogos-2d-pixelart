class_name PlayingState
extends State

var game: Node2D

func enter(_params: Dictionary = {}) -> void:
	game.on_playing_entered()

func handle_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
			game.restart_era()
		KEY_B:
			game.toggle_demo_mode()
