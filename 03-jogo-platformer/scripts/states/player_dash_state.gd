class_name PlayerDashState
extends State

var player: Player

# Dash: ignora gravidade por um instante e atravessa vãos que o pulo não alcança.
func physics_update(delta: float) -> void:
	player.dash_time_left -= delta
	player.velocity = Vector2(Player.DASH_SPEED * player.dash_dir, 0.0)
	player.move_and_slide()

	if player.dash_time_left <= 0.0 or player.is_on_wall():
		player.dash_time_left = 0.0
		player.velocity.x = player.RUN_SPEED * player.dash_dir
		if player.is_on_floor():
			state_machine.transition_to("Run" if not is_zero_approx(player.input_dir) else "Idle")
		else:
			state_machine.transition_to("Fall")
