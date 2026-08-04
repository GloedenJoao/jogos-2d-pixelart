class_name ResolveState
extends State

var game: Node

func enter(_params: Dictionary = {}) -> void:
	game.dealer_hole_hidden = false
	game.render_hands()
	var outcome := RoundResolver.resolve(game.player_hand, game.dealer_hand)
	var delta := RoundResolver.payout(outcome, game.bet)
	game.apply_balance_delta(delta)
	game.set_message(_outcome_message(outcome, delta))
	game.persist_round(outcome)
	game.set_betting_controls_visible(false)
	game.set_action_controls_visible(false)
	game.set_resolve_controls_visible(true)

func _outcome_message(outcome: RoundResolver.Outcome, delta: int) -> String:
	match outcome:
		RoundResolver.Outcome.PLAYER_BLACKJACK:
			return "Blackjack! Você ganhou %d fichas." % delta
		RoundResolver.Outcome.PLAYER_WIN:
			return "Você venceu! +%d fichas." % delta
		RoundResolver.Outcome.DEALER_BUST:
			return "Dealer estourou! +%d fichas." % delta
		RoundResolver.Outcome.PUSH:
			return "Empate — aposta devolvida."
		RoundResolver.Outcome.DEALER_WIN:
			return "Dealer venceu. %d fichas." % delta
		RoundResolver.Outcome.PLAYER_BUST:
			return "Você estourou. %d fichas." % delta
	return ""

func on_new_round() -> void:
	transitioned.emit(self, "betting", {})
