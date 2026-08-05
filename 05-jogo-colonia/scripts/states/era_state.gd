class_name EraState
extends State

# Um estado por era: a StateMachine do framework guarda em que era a civilização
# está, e entrar num estado é o que reconfigura cenário, cliques e construções.

var game: Node2D
var era_index := 0

func enter(_params: Dictionary = {}) -> void:
	game.on_era_entered(era_index)
