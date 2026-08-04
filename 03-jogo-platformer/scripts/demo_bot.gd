class_name DemoBot
extends RefCounted

# Piloto automático do andarilho: segura "direita" e decide quando pular, pular
# de novo no ar ou dar dash, lendo o mapa. Serve pra três coisas:
#   - teste: cada era precisa ser terminável por ele (regressão de level design)
#   - captura visual: gera screenshots de gameplay de verdade
#   - modo demo (tecla B na fase), pra ver o jogo se jogando sozinho

const LOOKAHEAD_HAZARD := 3    # tiles à frente que ele checa por espinho
const LOOKAHEAD_ENEMY := 44.0  # px à frente que ele checa por inimigo

var _prev_jump := false
var _prev_dash := false

func reset() -> void:
	_prev_jump = false
	_prev_dash = false

func step(game) -> void:
	var player = game.player
	var cell: Vector2i = game._cell_of(player.global_position)
	var want_jump := false
	var want_dash := false

	if player.is_on_floor():
		want_jump = _needs_jump(game, cell)
	elif player.velocity.y < 0.0 and _prev_jump:
		want_jump = true # segura o botão enquanto sobe, pra pular alto
	elif player.velocity.y > 0.0 and _over_gap(game, cell):
		# caindo num buraco: gasta o pulo duplo e, se ainda faltar chão, o dash
		if player.air_jumps_left > 0:
			want_jump = true
		elif player.abilities.get("dash", false) and player.dash_cooldown_left <= 0.0:
			want_dash = true

	var jump_out := false
	if player.velocity.y < 0.0 and _prev_jump:
		jump_out = true
	elif want_jump and not _prev_jump:
		jump_out = true
	var dash_out: bool = want_dash and not _prev_dash

	_prev_jump = jump_out
	_prev_dash = dash_out
	player.set_input(1.0, jump_out, dash_out)

func _over_gap(game, cell: Vector2i) -> bool:
	for y in range(cell.y + 1, game.level.height):
		if game.level.is_solid(Vector2i(cell.x, y)):
			return false
	return true

func _needs_jump(game, cell: Vector2i) -> bool:
	var level: LevelData = game.level
	# Parede à frente ou beirada do chão.
	if level.is_solid(cell + Vector2i(1, 0)):
		return true
	if cell.x + 1 < level.width - 1 and not level.is_solid(cell + Vector2i(1, 1)):
		return true
	# Espinho no caminho: pula cedo, pra cair depois dele e não em cima.
	for spike in level.spikes:
		if spike.y == cell.y and spike.x > cell.x and spike.x - cell.x <= LOOKAHEAD_HAZARD:
			return true
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var dx: float = enemy.global_position.x - game.player.global_position.x
		if dx > 0.0 and dx < LOOKAHEAD_ENEMY:
			return true
	return false
