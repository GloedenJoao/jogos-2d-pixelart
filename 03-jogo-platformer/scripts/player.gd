class_name Player
extends CharacterBody2D

# Andarilho: física de plataforma (gravidade, coyote time, buffer de pulo, pulo
# variável, pulo duplo e dash) + máquina de estados de animação usando o
# StateMachine do framework (Idle / Run / Jump / Fall / Dash).

const TILE := 18.0

const RUN_SPEED := 130.0
const GROUND_ACCEL := 900.0
const AIR_ACCEL := 700.0
const FRICTION := 1400.0

const GRAVITY := 900.0
const MAX_FALL := 420.0
const JUMP_VELOCITY := -330.0
const JUMP_CUT := 0.45          # soltar o botão cedo corta o pulo
const COYOTE_TIME := 0.12       # pular logo depois de sair da borda
const JUMP_BUFFER := 0.12       # apertar pulo um pouco antes de tocar o chão

const DASH_SPEED := 320.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 0.6
const STOMP_BOUNCE := -240.0

const SPRITE_SIZE := 24
const IDLE_FRAME := Vector2i(0, 1)
const WALK_FRAME := Vector2i(1, 1)
const WALK_FRAME_TIME := 0.11

var abilities: Dictionary = {"double_jump": false, "dash": false}

var facing := 1
var air_jumps_left := 0
var coyote := 0.0
var jump_buffer := 0.0
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_dir := 1
var can_control := true

# Entrada: normalmente lida do InputMap, mas testes e a demo automática podem
# assumir o controle com set_input().
var use_override := false
var input_dir := 0.0
var jump_held := false
var jump_just_pressed := false
var dash_just_pressed := false
var _override := {"dir": 0.0, "jump": false, "dash": false}
var _jump_was_held := false
var _dash_was_held := false

var state_machine: StateMachine
var sprite: Sprite2D
var _walk_clock := 0.0

func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 16)
	shape.shape = rect
	add_child(shape)

	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/platformer/tilemap-characters_packed.png")
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	set_frame(IDLE_FRAME)

	_build_state_machine()

func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	for entry in [
		["Idle", PlayerIdleState.new()],
		["Run", PlayerRunState.new()],
		["Jump", PlayerJumpState.new()],
		["Fall", PlayerFallState.new()],
		["Dash", PlayerDashState.new()],
	]:
		var state: State = entry[1]
		state.name = entry[0]
		state.set("player", self)
		state_machine.add_child(state)
	add_child(state_machine)

func _physics_process(delta: float) -> void:
	# Roda antes dos estados (nós-pai processam antes dos filhos), então quando o
	# estado atual age a entrada e os timers já estão atualizados.
	_read_input()
	_tick_timers(delta)
	_animate(delta)

# ---- entrada ----

func set_input(dir: float, jump: bool, dash: bool = false) -> void:
	use_override = true
	_override = {"dir": dir, "jump": jump, "dash": dash}

func clear_input_override() -> void:
	use_override = false
	_override = {"dir": 0.0, "jump": false, "dash": false}

func _read_input() -> void:
	var jump_now: bool
	var dash_now: bool
	if use_override:
		input_dir = float(_override.dir)
		jump_now = bool(_override.jump)
		dash_now = bool(_override.dash)
	else:
		input_dir = Input.get_axis("move_left", "move_right")
		jump_now = Input.is_action_pressed("jump")
		dash_now = Input.is_action_pressed("dash")

	if not can_control:
		input_dir = 0.0
		jump_now = false
		dash_now = false

	jump_just_pressed = jump_now and not _jump_was_held
	dash_just_pressed = dash_now and not _dash_was_held
	jump_held = jump_now
	_jump_was_held = jump_now
	_dash_was_held = dash_now

func _tick_timers(delta: float) -> void:
	if is_on_floor():
		coyote = COYOTE_TIME
		air_jumps_left = 1 if abilities.get("double_jump", false) else 0
	else:
		coyote = maxf(0.0, coyote - delta)

	if jump_just_pressed:
		jump_buffer = JUMP_BUFFER
	else:
		jump_buffer = maxf(0.0, jump_buffer - delta)

	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)

# ---- movimento (usado pelos estados) ----

func apply_horizontal(delta: float) -> void:
	if is_zero_approx(input_dir):
		var slow := FRICTION if is_on_floor() else AIR_ACCEL
		velocity.x = move_toward(velocity.x, 0.0, slow * delta)
		return
	facing = 1 if input_dir > 0.0 else -1
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, input_dir * RUN_SPEED, accel * delta)

func apply_gravity(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

# Pulo do chão (com coyote time) ou pulo duplo, se destravado.
func try_jump() -> bool:
	if jump_buffer <= 0.0:
		return false
	if coyote > 0.0:
		jump_buffer = 0.0
		coyote = 0.0
		velocity.y = JUMP_VELOCITY
		return true
	if air_jumps_left > 0:
		jump_buffer = 0.0
		air_jumps_left -= 1
		velocity.y = JUMP_VELOCITY
		return true
	return false

func cut_jump() -> void:
	if velocity.y < 0.0 and not jump_held:
		velocity.y *= JUMP_CUT

func can_dash() -> bool:
	return bool(abilities.get("dash", false)) and dash_cooldown_left <= 0.0 and dash_just_pressed

func start_dash() -> void:
	dash_dir = facing
	dash_time_left = DASH_TIME
	dash_cooldown_left = DASH_COOLDOWN
	velocity = Vector2(DASH_SPEED * dash_dir, 0.0)

func bounce() -> void:
	velocity.y = STOMP_BOUNCE

func reset_motion() -> void:
	velocity = Vector2.ZERO
	dash_time_left = 0.0
	dash_cooldown_left = 0.0
	jump_buffer = 0.0
	coyote = 0.0
	if state_machine:
		state_machine.transition_to("Idle")

func state_name() -> String:
	return state_machine.current_state.name if state_machine and state_machine.current_state else ""

# ---- visual ----

func set_frame(coord: Vector2i) -> void:
	sprite.region_rect = Rect2(coord.x * SPRITE_SIZE, coord.y * SPRITE_SIZE, SPRITE_SIZE, SPRITE_SIZE)

func _animate(delta: float) -> void:
	sprite.flip_h = facing < 0
	sprite.modulate = Color(0.7, 0.9, 1.0) if dash_time_left > 0.0 else Color(1, 1, 1)
	if not is_on_floor():
		set_frame(WALK_FRAME)
		return
	if absf(velocity.x) < 8.0:
		_walk_clock = 0.0
		set_frame(IDLE_FRAME)
		return
	_walk_clock += delta
	set_frame(WALK_FRAME if fmod(_walk_clock, WALK_FRAME_TIME * 2.0) < WALK_FRAME_TIME else IDLE_FRAME)
