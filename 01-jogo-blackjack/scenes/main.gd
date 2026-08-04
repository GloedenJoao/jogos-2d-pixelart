extends Control

const MIN_BET := 10
const BET_STEP := 10
const STARTING_BALANCE := 500
const CARD_SIZE := Vector2(80, 112)
const CARDS_PATH := "res://assets/cards/"
const CHIP_SIZE := 22
const CHIP_DENOMS := [100, 50, 10]
const CHIP_COLORS := {100: Color("2c2c2c"), 50: Color("1f7a3d"), 10: Color("1a5fb4")}
const DEAL_STAGGER := 0.08

var state_machine: StateMachine
var deck: Deck
var player_hand: Hand
var dealer_hand: Hand
var bet: int
var balance: int
var dealer_hole_hidden := true

var chips_label: Label
var message_label: Label
var dealer_value_label: Label
var player_value_label: Label
var dealer_hand_box: HBoxContainer
var player_hand_box: HBoxContainer
var bet_label: Label
var bet_chips_box: HBoxContainer
var betting_controls: HBoxContainer
var action_controls: HBoxContainer
var resolve_controls: HBoxContainer
var deal_button: Button
var hit_button: Button
var stand_button: Button
var double_button: Button
var new_round_button: Button
var music_slider: HSlider
var sfx_slider: HSlider
var stats_overlay: CenterContainer
var stats_hands_label: Label
var stats_wins_label: Label
var stats_best_label: Label

var _last_player_count := 0
var _last_dealer_count := 0

func _ready() -> void:
	theme = UITheme.theme
	deck = Deck.new()
	player_hand = Hand.new()
	dealer_hand = Hand.new()
	balance = SaveSystem.get_value("blackjack_balance", STARTING_BALANCE)
	bet = clampi(SaveSystem.get_value("blackjack_last_bet", MIN_BET), MIN_BET, max(MIN_BET, balance))

	_build_ui()

	var music_volume: float = SaveSystem.get_value("music_volume", 0.8)
	var sfx_volume: float = SaveSystem.get_value("sfx_volume", 0.8)
	music_slider.value = music_volume
	sfx_slider.value = sfx_volume
	AudioManager.set_music_volume(music_volume)
	AudioManager.set_sfx_volume(sfx_volume)

	_setup_state_machine()

func _setup_state_machine() -> void:
	state_machine = StateMachine.new()

	var betting := BettingState.new()
	betting.name = "Betting"
	betting.game = self

	var player_turn := PlayerTurnState.new()
	player_turn.name = "PlayerTurn"
	player_turn.game = self

	var dealer_turn := DealerTurnState.new()
	dealer_turn.name = "DealerTurn"
	dealer_turn.game = self

	var resolve := ResolveState.new()
	resolve.name = "Resolve"
	resolve.game = self

	state_machine.add_child(betting)
	state_machine.add_child(player_turn)
	state_machine.add_child(dealer_turn)
	state_machine.add_child(resolve)
	add_child(state_machine)

func _dispatch(method_name: String) -> void:
	var current := state_machine.current_state
	if current and current.has_method(method_name):
		current.call(method_name)

# ---- API usada pelos estados ----

func set_message(text: String) -> void:
	message_label.text = text

func update_chips_ui() -> void:
	chips_label.text = "Fichas: %d" % balance

func update_bet_ui() -> void:
	bet_label.text = "Aposta: %d" % bet
	_rebuild_bet_chips()

func set_betting_controls_visible(v: bool) -> void:
	betting_controls.visible = v

func set_action_controls_visible(v: bool, allow_double := false) -> void:
	action_controls.visible = v
	double_button.disabled = not allow_double

func set_resolve_controls_visible(v: bool) -> void:
	resolve_controls.visible = v

func apply_balance_delta(delta: int) -> void:
	balance += delta
	update_chips_ui()

func persist_round(outcome: RoundResolver.Outcome) -> void:
	SaveSystem.set_value("blackjack_balance", balance)
	SaveSystem.set_value("blackjack_last_bet", bet)
	var hands_played: int = SaveSystem.get_value("blackjack_hands_played", 0) + 1
	SaveSystem.set_value("blackjack_hands_played", hands_played)
	if RoundResolver.is_win(outcome):
		var hands_won: int = SaveSystem.get_value("blackjack_hands_won", 0) + 1
		SaveSystem.set_value("blackjack_hands_won", hands_won)
	var best_balance: int = SaveSystem.get_value("blackjack_best_balance", STARTING_BALANCE)
	if balance > best_balance:
		SaveSystem.set_value("blackjack_best_balance", balance)
	SaveSystem.save_data()

func render_hands() -> void:
	var prev_player_count := _last_player_count
	_clear_box(player_hand_box)
	for i in player_hand.cards.size():
		var node := _build_card_node(player_hand.cards[i], false)
		player_hand_box.add_child(node)
		if i >= prev_player_count:
			_animate_card_in(node, i - prev_player_count)
	_last_player_count = player_hand.cards.size()
	player_value_label.text = "Você: %d" % player_hand.value()

	var prev_dealer_count := _last_dealer_count
	_clear_box(dealer_hand_box)
	for i in dealer_hand.cards.size():
		var face_down := dealer_hole_hidden and i == 0
		var node := _build_card_node(dealer_hand.cards[i], face_down)
		dealer_hand_box.add_child(node)
		if i >= prev_dealer_count:
			_animate_card_in(node, i - prev_dealer_count)
	_last_dealer_count = dealer_hand.cards.size()
	if dealer_hole_hidden and dealer_hand.count() > 0:
		dealer_value_label.text = "Dealer: ?"
	else:
		dealer_value_label.text = "Dealer: %d" % dealer_hand.value()

func _clear_box(box: HBoxContainer) -> void:
	for child in box.get_children():
		child.queue_free()

# Efeito de "distribuir": carta nasce pequena/transparente e cresce no lugar,
# com atraso crescente por índice pra parecer uma sequência de cartas caindo na mesa.
func _animate_card_in(node: Control, stagger_index: int) -> void:
	node.pivot_offset = CARD_SIZE / 2
	node.scale = Vector2(0.4, 0.4)
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(stagger_index * DEAL_STAGGER)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 1.0, 0.18)

var _card_texture_cache: Dictionary = {}

func _card_texture(sprite_name: String) -> Texture2D:
	if not _card_texture_cache.has(sprite_name):
		_card_texture_cache[sprite_name] = load("%s%s.png" % [CARDS_PATH, sprite_name])
	return _card_texture_cache[sprite_name]

func _build_card_node(card: Card, face_down: bool) -> Control:
	var rect := TextureRect.new()
	rect.custom_minimum_size = CARD_SIZE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = _card_texture("card_back" if face_down else card.sprite_name())
	return rect

# Representa a aposta como uma pilha de fichas (100/50/10) em vez de só número.
func _rebuild_bet_chips() -> void:
	if bet_chips_box == null:
		return
	for child in bet_chips_box.get_children():
		child.queue_free()
	var remaining := bet
	var count := 0
	for denom in CHIP_DENOMS:
		while remaining >= denom and count < 12:
			bet_chips_box.add_child(_build_chip(denom))
			remaining -= denom
			count += 1

func _build_chip(denom: int) -> Control:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_COLORS[denom]
	style.border_color = Color.WHITE
	style.set_border_width_all(2)
	style.set_corner_radius_all(CHIP_SIZE / 2)
	chip.add_theme_stylebox_override("panel", style)
	return chip

# ---- estatísticas ----

func _toggle_stats() -> void:
	if stats_overlay.visible:
		stats_overlay.visible = false
		return
	_refresh_stats_panel()
	stats_overlay.visible = true

func _refresh_stats_panel() -> void:
	var played: int = SaveSystem.get_value("blackjack_hands_played", 0)
	var won: int = SaveSystem.get_value("blackjack_hands_won", 0)
	var best: int = SaveSystem.get_value("blackjack_best_balance", STARTING_BALANCE)
	var rate := 0.0
	if played > 0:
		rate = (float(won) / float(played)) * 100.0
	stats_hands_label.text = "Mãos jogadas: %d" % played
	stats_wins_label.text = "Mãos vencidas: %d (%.0f%%)" % [won, rate]
	stats_best_label.text = "Melhor saldo: %d" % best

# ---- construção da UI ----

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color("0e3b23")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Barra superior: fichas + mensagem de status.
	var top_bar := HBoxContainer.new()
	vbox.add_child(top_bar)

	chips_label = Label.new()
	chips_label.text = "Fichas: %d" % balance
	chips_label.add_theme_font_size_override("font_size", 28)
	top_bar.add_child(chips_label)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	message_label = Label.new()
	message_label.text = "Faça sua aposta."
	message_label.add_theme_font_size_override("font_size", 24)
	top_bar.add_child(message_label)

	var stats_spacer := Control.new()
	stats_spacer.custom_minimum_size = Vector2(16, 0)
	top_bar.add_child(stats_spacer)

	var stats_button := Button.new()
	stats_button.text = "Estatísticas"
	stats_button.custom_minimum_size = Vector2(140, 40)
	stats_button.pressed.connect(_toggle_stats)
	top_bar.add_child(stats_button)

	# Mesa do dealer.
	var dealer_label := Label.new()
	dealer_label.text = "Dealer"
	dealer_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(dealer_label)

	dealer_value_label = Label.new()
	dealer_value_label.text = "Dealer: 0"
	dealer_value_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(dealer_value_label)

	var dealer_table := PanelContainer.new()
	vbox.add_child(dealer_table)
	dealer_hand_box = HBoxContainer.new()
	dealer_hand_box.add_theme_constant_override("separation", 12)
	dealer_hand_box.custom_minimum_size = Vector2(0, 128)
	dealer_table.add_child(dealer_hand_box)

	var table_spacer := Control.new()
	table_spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(table_spacer)

	# Mesa do jogador.
	var player_label := Label.new()
	player_label.text = "Você"
	player_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(player_label)

	player_value_label = Label.new()
	player_value_label.text = "Você: 0"
	player_value_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(player_value_label)

	var player_table := PanelContainer.new()
	vbox.add_child(player_table)
	player_hand_box = HBoxContainer.new()
	player_hand_box.add_theme_constant_override("separation", 12)
	player_hand_box.custom_minimum_size = Vector2(0, 128)
	player_table.add_child(player_hand_box)

	var controls_spacer := Control.new()
	controls_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(controls_spacer)

	# Controles de aposta.
	betting_controls = HBoxContainer.new()
	betting_controls.add_theme_constant_override("separation", 12)
	vbox.add_child(betting_controls)

	var bet_minus_button := Button.new()
	bet_minus_button.text = "-"
	bet_minus_button.custom_minimum_size = Vector2(48, 48)
	bet_minus_button.pressed.connect(func(): _dispatch("on_bet_minus"))
	betting_controls.add_child(bet_minus_button)

	bet_label = Label.new()
	bet_label.text = "Aposta: %d" % bet
	bet_label.custom_minimum_size = Vector2(180, 0)
	bet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bet_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bet_label.add_theme_font_size_override("font_size", 20)
	betting_controls.add_child(bet_label)

	var bet_plus_button := Button.new()
	bet_plus_button.text = "+"
	bet_plus_button.custom_minimum_size = Vector2(48, 48)
	bet_plus_button.pressed.connect(func(): _dispatch("on_bet_plus"))
	betting_controls.add_child(bet_plus_button)

	bet_chips_box = HBoxContainer.new()
	bet_chips_box.add_theme_constant_override("separation", 2)
	betting_controls.add_child(bet_chips_box)

	deal_button = Button.new()
	deal_button.text = "Apostar"
	deal_button.custom_minimum_size = Vector2(140, 48)
	deal_button.pressed.connect(func(): _dispatch("on_deal"))
	betting_controls.add_child(deal_button)

	# Controles de jogada.
	action_controls = HBoxContainer.new()
	action_controls.add_theme_constant_override("separation", 12)
	action_controls.visible = false
	vbox.add_child(action_controls)

	hit_button = Button.new()
	hit_button.text = "Pedir"
	hit_button.custom_minimum_size = Vector2(120, 48)
	hit_button.pressed.connect(func(): _dispatch("on_hit"))
	action_controls.add_child(hit_button)

	stand_button = Button.new()
	stand_button.text = "Parar"
	stand_button.custom_minimum_size = Vector2(120, 48)
	stand_button.pressed.connect(func(): _dispatch("on_stand"))
	action_controls.add_child(stand_button)

	double_button = Button.new()
	double_button.text = "Dobrar"
	double_button.custom_minimum_size = Vector2(120, 48)
	double_button.pressed.connect(func(): _dispatch("on_double"))
	action_controls.add_child(double_button)

	# Controles de resolução de rodada.
	resolve_controls = HBoxContainer.new()
	resolve_controls.visible = false
	vbox.add_child(resolve_controls)

	new_round_button = Button.new()
	new_round_button.text = "Nova rodada"
	new_round_button.custom_minimum_size = Vector2(160, 48)
	new_round_button.pressed.connect(func(): _dispatch("on_new_round"))
	resolve_controls.add_child(new_round_button)

	# Volume.
	var settings_row := HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 12)
	vbox.add_child(settings_row)

	var music_label := Label.new()
	music_label.text = "Música"
	settings_row.add_child(music_label)

	music_slider = HSlider.new()
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.custom_minimum_size = Vector2(160, 0)
	music_slider.value_changed.connect(_on_music_volume_changed)
	settings_row.add_child(music_slider)

	var sfx_label := Label.new()
	sfx_label.text = "SFX"
	settings_row.add_child(sfx_label)

	sfx_slider = HSlider.new()
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.custom_minimum_size = Vector2(160, 0)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	settings_row.add_child(sfx_slider)

	# Painel de estatísticas (overlay centralizado, escondido até clicar em "Estatísticas").
	stats_overlay = CenterContainer.new()
	stats_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	stats_overlay.visible = false
	add_child(stats_overlay)

	var stats_panel := PanelContainer.new()
	stats_panel.custom_minimum_size = Vector2(320, 240)
	stats_overlay.add_child(stats_panel)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 12)
	stats_panel.add_child(stats_vbox)

	var stats_title := Label.new()
	stats_title.text = "Estatísticas"
	stats_title.add_theme_font_size_override("font_size", 26)
	stats_vbox.add_child(stats_title)

	stats_hands_label = Label.new()
	stats_vbox.add_child(stats_hands_label)

	stats_wins_label = Label.new()
	stats_vbox.add_child(stats_wins_label)

	stats_best_label = Label.new()
	stats_vbox.add_child(stats_best_label)

	var stats_close := Button.new()
	stats_close.text = "Fechar"
	stats_close.custom_minimum_size = Vector2(120, 44)
	stats_close.pressed.connect(func(): stats_overlay.visible = false)
	stats_vbox.add_child(stats_close)

func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	SaveSystem.set_value("music_volume", value)
	SaveSystem.save_data()

func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	SaveSystem.set_value("sfx_volume", value)
	SaveSystem.save_data()
