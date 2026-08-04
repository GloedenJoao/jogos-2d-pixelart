class_name RoundResolver
extends RefCounted

enum Outcome { PLAYER_BLACKJACK, PLAYER_WIN, DEALER_WIN, PUSH, PLAYER_BUST, DEALER_BUST }

static func resolve(player: Hand, dealer: Hand) -> Outcome:
	if player.is_bust():
		return Outcome.PLAYER_BUST
	if dealer.is_bust():
		return Outcome.DEALER_BUST
	if player.is_blackjack() and not dealer.is_blackjack():
		return Outcome.PLAYER_BLACKJACK
	if dealer.is_blackjack() and not player.is_blackjack():
		return Outcome.DEALER_WIN
	if player.value() > dealer.value():
		return Outcome.PLAYER_WIN
	if player.value() < dealer.value():
		return Outcome.DEALER_WIN
	return Outcome.PUSH

# Retorna a variação no saldo do jogador (pode ser negativa).
static func payout(outcome: Outcome, bet: int) -> int:
	match outcome:
		Outcome.PLAYER_BLACKJACK:
			return int(bet * 1.5)
		Outcome.PLAYER_WIN, Outcome.DEALER_BUST:
			return bet
		Outcome.PUSH:
			return 0
		Outcome.DEALER_WIN, Outcome.PLAYER_BUST:
			return -bet
	return 0

static func is_win(outcome: Outcome) -> bool:
	return outcome == Outcome.PLAYER_BLACKJACK or outcome == Outcome.PLAYER_WIN or outcome == Outcome.DEALER_BUST
