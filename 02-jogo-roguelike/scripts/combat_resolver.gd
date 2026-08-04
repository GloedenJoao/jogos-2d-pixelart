class_name CombatResolver
extends RefCounted

static func resolve_attack(attacker: Entity, defender: Entity) -> Dictionary:
	var damage: int = maxi(1, attacker.attack)
	defender.take_damage(damage)
	return {
		"damage": damage,
		"defender_died": not defender.is_alive(),
	}
