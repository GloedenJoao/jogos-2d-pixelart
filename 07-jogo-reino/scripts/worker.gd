class_name Worker
extends RefCounted

# Um trabalhador: dado puro, sem lógica de movimento (isso fica em
# `Workers.advance`, mesma separação de `Villager`/`Population` na Colônia
# V2 — o dado não sabe andar, só guarda onde está e pra onde vai).

enum State { IDLE, WALKING, WORKING }

const SPEED := 90.0   # px/s, mesmo valor da Colônia V2 (villager.gd)

var id := -1
var position := Vector2.ZERO
var path := PackedVector2Array()
var path_index := 0
var state: int = State.IDLE
var job_building := -1   # índice em Buildings.list, -1 = sem posto

func has_path() -> bool:
	return path_index < path.size()

func next_waypoint() -> Vector2:
	return path[path_index] if has_path() else position

func set_path(new_path: PackedVector2Array) -> void:
	path = new_path
	path_index = 0
	state = State.WALKING

func clear_path() -> void:
	path = PackedVector2Array()
	path_index = 0
