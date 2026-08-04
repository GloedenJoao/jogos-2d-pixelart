class_name Entity
extends RefCounted

var display_name: String
var grid_pos: Vector2i
var max_hp: int
var hp: int
var attack: int

func _init(p_name: String, p_pos: Vector2i, p_max_hp: int, p_attack: int) -> void:
	display_name = p_name
	grid_pos = p_pos
	max_hp = p_max_hp
	hp = p_max_hp
	attack = p_attack

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)

func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
