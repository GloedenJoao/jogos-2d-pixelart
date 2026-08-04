class_name PlayerJumpState
extends State

var player: Player

# Subindo: o pulo é variável (soltar o botão cedo corta a subida) e o pulo duplo,
# quando destravado, pode ser usado aqui.
func physics_update(delta: float) -> void:
	player.cut_jump()

	if player.try_jump():
		pass # pulo duplo: continua no mesmo estado, só renova a velocidade
	elif player.can_dash():
		player.start_dash()
		state_machine.transition_to("Dash")
		return

	player.apply_horizontal(delta)
	player.apply_gravity(delta)
	player.move_and_slide()

	if player.is_on_floor():
		state_machine.transition_to("Run" if not is_zero_approx(player.input_dir) else "Idle")
	elif player.velocity.y >= 0.0:
		state_machine.transition_to("Fall")
