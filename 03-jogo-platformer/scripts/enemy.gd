class_name Enemy
extends CharacterBody2D

# Inimigo de patrulha: anda numa direção, dá meia-volta quando bate na parede ou
# quando o chão acaba. Não persegue o jogador — o desafio é de plataforma, não
# de combate. Pode ser derrotado pisando em cima.

const SPEED := 34.0
const GRAVITY := 900.0
const MAX_FALL := 400.0
const SPRITE_SIZE := 24
const FRAME_TIME := 0.25

const PATROL_HALF_WIDTH := 3.0 * 18.0 # 3 tiles pra cada lado do posto

var level: LevelData
var frames: Array[Vector2i] = [Vector2i(6, 2), Vector2i(7, 2)]
var dir := -1
var alive := true
var patrol_center := 0.0

var sprite: Sprite2D
var _clock := 0.0

func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 14)
	shape.shape = rect
	add_child(shape)

	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/platformer/tilemap-characters_packed.png")
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_set_frame(0)

func _physics_process(delta: float) -> void:
	if not alive:
		return

	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	velocity.x = SPEED * dir
	move_and_slide()

	# Dá meia-volta na parede, na beirada do chão ou no limite da área de patrulha
	# (cada inimigo guarda um posto, não persegue o jogador pelo mapa inteiro).
	if is_on_wall():
		dir = -dir
	elif is_on_floor() and not _ground_ahead():
		dir = -dir
	elif absf(global_position.x - patrol_center) > PATROL_HALF_WIDTH:
		dir = 1 if global_position.x < patrol_center else -1

	_clock += delta
	_set_frame(0 if fmod(_clock, FRAME_TIME * 2.0) < FRAME_TIME else 1)
	sprite.flip_h = dir > 0

func _ground_ahead() -> bool:
	if level == null:
		return true
	var ahead := Vector2(global_position.x + dir * 9.0, global_position.y + 12.0)
	var cell := Vector2i(floori(ahead.x / Player.TILE), floori(ahead.y / Player.TILE))
	return level.is_solid(cell)

func _set_frame(index: int) -> void:
	var coord: Vector2i = frames[clampi(index, 0, frames.size() - 1)]
	sprite.region_rect = Rect2(coord.x * SPRITE_SIZE, coord.y * SPRITE_SIZE, SPRITE_SIZE, SPRITE_SIZE)

func defeat() -> void:
	alive = false
	visible = false
	set_physics_process(false)
