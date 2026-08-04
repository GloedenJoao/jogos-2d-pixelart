class_name VictoryState
extends State

var game: Node2D

func enter(_params: Dictionary = {}) -> void:
	game.on_floor_cleared()

func on_new_run() -> void:
	game.start_new_run()
	state_machine.transition_to("Playing")
