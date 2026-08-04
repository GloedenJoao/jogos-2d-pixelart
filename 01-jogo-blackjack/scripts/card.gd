class_name Card
extends RefCounted

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

const RANK_LABELS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUIT_SYMBOLS := {
	Suit.HEARTS: "♥",
	Suit.DIAMONDS: "♦",
	Suit.CLUBS: "♣",
	Suit.SPADES: "♠",
}

var suit: Suit
var rank_index: int # 0 = Ás, 1..9 = 2..10, 10 = J, 11 = Q, 12 = K

func _init(p_suit: Suit, p_rank_index: int) -> void:
	suit = p_suit
	rank_index = p_rank_index

func rank_label() -> String:
	return RANK_LABELS[rank_index]

func suit_symbol() -> String:
	return SUIT_SYMBOLS[suit]

func is_red() -> bool:
	return suit == Suit.HEARTS or suit == Suit.DIAMONDS

func is_ace() -> bool:
	return rank_index == 0

# Valor base do Ás é 11; Hand.value() rebaixa pra 1 quando estoura 21.
func base_value() -> int:
	if rank_index == 0:
		return 11
	if rank_index >= 9:
		return 10
	return rank_index + 1

func label() -> String:
	return "%s%s" % [rank_label(), suit_symbol()]
