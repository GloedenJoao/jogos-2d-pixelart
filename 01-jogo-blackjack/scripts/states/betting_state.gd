class_name BettingState
extends State

var game: Node

func enter(_params: Dictionary = {}) -> void:
	if game.balance < game.MIN_BET:
		game.balance = game.STARTING_BALANCE
		game.set_message("Você zerou as fichas — saldo reiniciado em %d." % game.STARTING_BALANCE)
	else:
		game.set_message("Faça sua aposta.")
	game.player_hand.clear()
	game.dealer_hand.clear()
	game.dealer_hole_hidden = true
	game.bet = clampi(game.bet, game.MIN_BET, game.balance)
	game.update_chips_ui()
	game.update_bet_ui()
	game.render_hands()
	game.set_betting_controls_visible(true)
	game.set_action_controls_visible(false)
	game.set_resolve_controls_visible(false)

func on_bet_minus() -> void:
	game.bet = clampi(game.bet - game.BET_STEP, game.MIN_BET, game.balance)
	game.update_bet_ui()

func on_bet_plus() -> void:
	game.bet = clampi(game.bet + game.BET_STEP, game.MIN_BET, game.balance)
	game.update_bet_ui()

func on_deal() -> void:
	if game.bet <= 0 or game.bet > game.balance:
		return
	game.player_hand.add(game.deck.draw())
	game.dealer_hand.add(game.deck.draw())
	game.player_hand.add(game.deck.draw())
	game.dealer_hand.add(game.deck.draw())
	game.render_hands()
	if game.player_hand.is_blackjack():
		transitioned.emit(self, "resolve", {})
	else:
		transitioned.emit(self, "playerturn", {})
