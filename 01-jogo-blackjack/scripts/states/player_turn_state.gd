class_name PlayerTurnState
extends State

var game: Node

func enter(_params: Dictionary = {}) -> void:
	game.dealer_hole_hidden = true
	game.render_hands()
	game.set_message("Sua vez — pedir carta ou parar?")
	game.set_betting_controls_visible(false)
	var allow_double: bool = game.player_hand.count() == 2 and game.balance >= game.bet * 2
	game.set_action_controls_visible(true, allow_double)
	game.set_resolve_controls_visible(false)

func on_hit() -> void:
	game.player_hand.add(game.deck.draw())
	game.render_hands()
	if game.player_hand.is_bust():
		game.set_message("Estourou!")
		transitioned.emit(self, "resolve", {})
	else:
		game.set_action_controls_visible(true, false)

func on_stand() -> void:
	transitioned.emit(self, "dealerturn", {})

func on_double() -> void:
	if game.player_hand.count() != 2 or game.balance < game.bet * 2:
		return
	game.bet *= 2
	game.update_bet_ui()
	game.player_hand.add(game.deck.draw())
	game.render_hands()
	if game.player_hand.is_bust():
		game.set_message("Estourou!")
		transitioned.emit(self, "resolve", {})
	else:
		transitioned.emit(self, "dealerturn", {})
