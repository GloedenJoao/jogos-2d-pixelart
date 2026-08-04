class_name PlayerRunState
extends State

var player: Player

func physics_update(delta: float) -> void:
	if player.try_jump():
		state_machine.transition_to("Jump")
		return
	if player.can_dash():
		player.start_dash()
		state_machine.transition_to("Dash")
		return

	player.apply_horizontal(delta)
	player.apply_gravity(delta)
	player.move_and_slide()

	if not player.is_on_floor():
		state_machine.transition_to("Fall")
	elif is_zero_approx(player.input_dir) and absf(player.velocity.x) < 8.0:
		state_machine.transition_to("Idle")
