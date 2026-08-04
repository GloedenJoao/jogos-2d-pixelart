class_name GameCompleteState
extends State

var game: Node2D

func enter(_params: Dictionary = {}) -> void:
	game.on_game_completed()

func on_continue() -> void:
	game.start_game(0)
