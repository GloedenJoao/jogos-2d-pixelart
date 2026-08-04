class_name PlayerFallState
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

	if player.is_on_floor():
		state_machine.transition_to("Run" if not is_zero_approx(player.input_dir) else "Idle")
