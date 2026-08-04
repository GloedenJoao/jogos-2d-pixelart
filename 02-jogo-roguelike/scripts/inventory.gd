class_name Inventory
extends RefCounted

const POTION_HEAL := 5

var potions: int = 0
var gold: int = 0

func add_potion(amount: int = 1) -> void:
	potions += amount

func add_gold(amount: int) -> void:
	gold += amount

func use_potion(entity: Entity) -> bool:
	if potions <= 0 or entity.hp >= entity.max_hp:
		return false
	potions -= 1
	entity.heal(POTION_HEAL)
	return true
