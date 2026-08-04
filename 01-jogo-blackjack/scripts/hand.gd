class_name Hand
extends RefCounted

var cards: Array[Card] = []

func add(card: Card) -> void:
	cards.append(card)

func clear() -> void:
	cards.clear()

func count() -> int:
	return cards.size()

# Soma os valores rebaixando Áses de 11 pra 1 enquanto a mão estourar 21.
func value() -> int:
	var total := 0
	var aces := 0
	for card in cards:
		total += card.base_value()
		if card.is_ace():
			aces += 1
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total

func is_bust() -> bool:
	return value() > 21

func is_blackjack() -> bool:
	return cards.size() == 2 and value() == 21

func labels() -> Array[String]:
	var out: Array[String] = []
	for card in cards:
		out.append(card.label())
	return out
