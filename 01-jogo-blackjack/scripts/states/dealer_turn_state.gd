class_name DealerTurnState
extends State

const DRAW_DELAY := 0.6

var game: Node

func enter(_params: Dictionary = {}) -> void:
	game.dealer_hole_hidden = false
	game.render_hands()
	game.set_message("Vez do dealer...")
	game.set_betting_controls_visible(false)
	game.set_action_controls_visible(false)
	await _play_dealer()

# Dealer para em qualquer 17 (inclusive "soft 17").
func _play_dealer() -> void:
	while game.dealer_hand.value() < 17:
		await get_tree().create_timer(DRAW_DELAY).timeout
		game.dealer_hand.add(game.deck.draw())
		game.render_hands()
	transitioned.emit(self, "resolve", {})
