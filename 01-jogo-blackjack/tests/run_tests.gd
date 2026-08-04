extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_test_card_and_hand()
	_test_deck()
	_test_round_resolver()
	await _test_scene_initial_state()
	await _test_player_blackjack_round()
	await _test_dealer_bust_round()
	_report()

func _assert(cond: bool, message: String) -> void:
	if cond:
		_pass += 1
		print("  OK   - %s" % message)
	else:
		_fail += 1
		print("  FAIL - %s" % message)

func _test_card_and_hand() -> void:
	print("[Card/Hand]")
	var hand := Hand.new()
	hand.add(Card.new(Card.Suit.SPADES, 0)) # Ás
	hand.add(Card.new(Card.Suit.HEARTS, 9)) # 10
	_assert(hand.value() == 21, "Ás + 10 vale 21")
	_assert(hand.is_blackjack(), "duas cartas somando 21 é blackjack")

	var soft_hand := Hand.new()
	soft_hand.add(Card.new(Card.Suit.SPADES, 0)) # Ás = 11
	soft_hand.add(Card.new(Card.Suit.HEARTS, 5)) # 6
	soft_hand.add(Card.new(Card.Suit.CLUBS, 9)) # 10
	_assert(soft_hand.value() == 17, "Ás rebaixa de 11 pra 1 quando estouraria (11+6+10=27 -> 17)")

	var bust_hand := Hand.new()
	bust_hand.add(Card.new(Card.Suit.SPADES, 9)) # 10
	bust_hand.add(Card.new(Card.Suit.HEARTS, 9)) # 10
	bust_hand.add(Card.new(Card.Suit.CLUBS, 5)) # 6
	_assert(bust_hand.is_bust(), "10+10+6=26 estoura")

func _test_deck() -> void:
	print("[Deck]")
	var deck := Deck.new()
	_assert(deck.remaining() == 52, "baralho novo tem 52 cartas")
	var seen := {}
	for i in 52:
		var card: Card = deck.draw()
		seen["%d-%d" % [card.suit, card.rank_index]] = true
	_assert(seen.size() == 52, "as 52 cartas compradas são únicas")
	_assert(deck.remaining() == 0, "baralho esvaziou após 52 compras")
	var next_card := deck.draw()
	_assert(next_card != null and deck.remaining() == 51, "baralho reembaralha sozinho quando vazio")

func _test_round_resolver() -> void:
	print("[RoundResolver]")
	var dealer_17 := Hand.new()
	dealer_17.add(Card.new(Card.Suit.CLUBS, 9)) # 10
	dealer_17.add(Card.new(Card.Suit.DIAMONDS, 6)) # 7 -> 17

	var player_19 := Hand.new()
	player_19.add(Card.new(Card.Suit.SPADES, 9)) # 10
	player_19.add(Card.new(Card.Suit.HEARTS, 8)) # 9 -> 19
	_assert(RoundResolver.resolve(player_19, dealer_17) == RoundResolver.Outcome.PLAYER_WIN, "19 vence 17")
	_assert(RoundResolver.payout(RoundResolver.Outcome.PLAYER_WIN, 20) == 20, "vitória simples paga 1:1")

	var player_blackjack := Hand.new()
	player_blackjack.add(Card.new(Card.Suit.SPADES, 0))
	player_blackjack.add(Card.new(Card.Suit.HEARTS, 12))
	_assert(RoundResolver.resolve(player_blackjack, dealer_17) == RoundResolver.Outcome.PLAYER_BLACKJACK, "blackjack natural vence 17 do dealer")
	_assert(RoundResolver.payout(RoundResolver.Outcome.PLAYER_BLACKJACK, 20) == 30, "blackjack paga 3:2")

	var player_bust := Hand.new()
	player_bust.add(Card.new(Card.Suit.SPADES, 9))
	player_bust.add(Card.new(Card.Suit.HEARTS, 9))
	player_bust.add(Card.new(Card.Suit.CLUBS, 5))
	_assert(RoundResolver.resolve(player_bust, dealer_17) == RoundResolver.Outcome.PLAYER_BUST, "jogador estourado perde")

	var player_17 := Hand.new()
	player_17.add(Card.new(Card.Suit.SPADES, 9))
	player_17.add(Card.new(Card.Suit.HEARTS, 6))
	_assert(RoundResolver.resolve(player_17, dealer_17) == RoundResolver.Outcome.PUSH, "17 x 17 é empate")
	_assert(RoundResolver.payout(RoundResolver.Outcome.PUSH, 20) == 0, "empate não paga nem cobra")

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	for key in ["blackjack_balance", "blackjack_last_bet", "blackjack_hands_played", "blackjack_hands_won", "blackjack_best_balance"]:
		save_system.data.erase(key)
	save_system.save_data()

func _force_deck(instance: Node, draw_order: Array) -> void:
	# draw() usa pop_back(), então quem compra primeiro tem que estar no fim do array.
	var reversed: Array = draw_order.duplicate()
	reversed.reverse()
	instance.deck.cards.assign(reversed)

func _test_scene_initial_state() -> void:
	print("[main.tscn - estado inicial]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	_assert(packed != null, "carrega sem erro")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	_assert(instance.theme != null, "UITheme foi aplicado")
	_assert(instance.state_machine.current_state.name == "Betting", "estado inicial é Betting")
	_assert(instance.balance == instance.STARTING_BALANCE, "saldo inicial é o padrão quando não há save")

	instance.queue_free()
	await process_frame

func _test_player_blackjack_round() -> void:
	print("[Rodada - blackjack do jogador]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var starting_balance: int = instance.balance
	instance.bet = 20
	_force_deck(instance, [
		Card.new(Card.Suit.SPADES, 0),   # jogador: Ás
		Card.new(Card.Suit.HEARTS, 4),   # dealer: 5
		Card.new(Card.Suit.CLUBS, 12),   # jogador: K -> 21 (blackjack)
		Card.new(Card.Suit.DIAMONDS, 5), # dealer: 6 -> 11
	])
	instance.state_machine.current_state.on_deal()
	await process_frame

	_assert(instance.state_machine.current_state.name == "Resolve", "blackjack natural vai direto pra Resolve")
	_assert(instance.balance == starting_balance + 30, "blackjack paga 3:2 sobre a aposta de 20")
	_assert(instance.resolve_controls.visible, "controles de nova rodada aparecem")

	instance.queue_free()
	await process_frame

func _test_dealer_bust_round() -> void:
	print("[Rodada - dealer estoura]")
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var starting_balance: int = instance.balance
	instance.bet = 20
	_force_deck(instance, [
		Card.new(Card.Suit.SPADES, 9),   # jogador: 10
		Card.new(Card.Suit.HEARTS, 5),   # dealer: 6
		Card.new(Card.Suit.CLUBS, 6),    # jogador: 7 -> 17
		Card.new(Card.Suit.DIAMONDS, 5), # dealer: 6 -> 12
		Card.new(Card.Suit.SPADES, 12),  # dealer compra: K -> 22 (estourou)
	])
	instance.state_machine.current_state.on_deal()
	await process_frame
	_assert(instance.state_machine.current_state.name == "PlayerTurn", "sem blackjack natural vai pra PlayerTurn")

	instance.state_machine.current_state.on_stand()
	await process_frame
	_assert(instance.state_machine.current_state.name == "DealerTurn", "parar move pra DealerTurn")

	await create_timer(1.2).timeout
	_assert(instance.state_machine.current_state.name == "Resolve", "dealer termina de comprar e resolve a rodada")
	_assert(instance.balance == starting_balance + 20, "dealer estourado paga 1:1")

	var save_system := root.get_node("/root/SaveSystem")
	_assert(save_system.get_value("blackjack_hands_played", 0) == 1, "persist_round grava mãos jogadas")
	_assert(save_system.get_value("blackjack_hands_won", 0) == 1, "persist_round conta a vitória")

	instance.queue_free()
	await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
