class_name Deck
extends RefCounted

var cards: Array[Card] = []

func _init() -> void:
	build()
	shuffle()

func build() -> void:
	cards.clear()
	for suit in Card.Suit.values():
		for rank_index in range(Card.RANK_LABELS.size()):
			cards.append(Card.new(suit, rank_index))

func shuffle() -> void:
	cards.shuffle()

func draw() -> Card:
	if cards.is_empty():
		build()
		shuffle()
	return cards.pop_back()

func remaining() -> int:
	return cards.size()
