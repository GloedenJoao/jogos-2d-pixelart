extends Control

const MIN_BET := 10
const BET_STEP := 10
const STARTING_BALANCE := 500
const CARD_SIZE := Vector2(80, 112)

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
	_clear_box(player_hand_box)
	for card in player_hand.cards:
		player_hand_box.add_child(_build_card_node(card, false))
	player_value_label.text = "Você: %d" % player_hand.value()

	_clear_box(dealer_hand_box)
	for i in dealer_hand.cards.size():
		var face_down := dealer_hole_hidden and i == 0
		dealer_hand_box.add_child(_build_card_node(dealer_hand.cards[i], face_down))
	if dealer_hole_hidden and dealer_hand.count() > 0:
		dealer_value_label.text = "Dealer: ?"
	else:
		dealer_value_label.text = "Dealer: %d" % dealer_hand.value()

func _clear_box(box: HBoxContainer) -> void:
	for child in box.get_children():
		child.queue_free()

func _build_card_node(card: Card, face_down: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE

	var style := StyleBoxFlat.new()
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(2)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 22)

	if face_down:
		style.bg_color = UITheme.COLOR_ACCENT
		style.border_color = UITheme.COLOR_ACCENT_HOVER
		label.text = "?"
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	else:
		style.bg_color = Color.WHITE
		style.border_color = Color("222222")
		label.text = card.label()
		label.add_theme_color_override("font_color", Color("c0392b") if card.is_red() else Color("111111"))

	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(label)
	return panel

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

	# Mesa do dealer.
	var dealer_label := Label.new()
	dealer_label.text = "Dealer"
	dealer_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(dealer_label)

	dealer_value_label = Label.new()
	dealer_value_label.text = "Dealer: 0"
	dealer_value_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(dealer_value_label)

	dealer_hand_box = HBoxContainer.new()
	dealer_hand_box.add_theme_constant_override("separation", 12)
	dealer_hand_box.custom_minimum_size = Vector2(0, 128)
	vbox.add_child(dealer_hand_box)

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

	player_hand_box = HBoxContainer.new()
	player_hand_box.add_theme_constant_override("separation", 12)
	player_hand_box.custom_minimum_size = Vector2(0, 128)
	vbox.add_child(player_hand_box)

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

func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	SaveSystem.set_value("music_volume", value)
	SaveSystem.save_data()

func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	SaveSystem.set_value("sfx_volume", value)
	SaveSystem.save_data()
