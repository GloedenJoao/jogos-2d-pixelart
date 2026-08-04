class_name EraCompleteState
extends State

var game: Node2D

func enter(_params: Dictionary = {}) -> void:
	game.on_era_completed()

func on_continue() -> void:
	game.load_era(game.era_index + 1)
