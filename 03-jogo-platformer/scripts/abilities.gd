class_name Abilities
extends RefCounted

# Mecânicas de movimento destravadas por era. São cumulativas: quem chegou na
# Indústria continua com o pulo duplo da Vila.

const LABELS := {
	"double_jump": "Pulo duplo",
	"dash": "Dash",
}

const HINTS := {
	"double_jump": "Aperte pulo de novo no ar pra dar o segundo salto.",
	"dash": "Shift ou J dispara um dash na direção em que você olha.",
}

static func for_era(era_index: int) -> Dictionary:
	var out := {"double_jump": false, "dash": false}
	for i in range(era_index + 1):
		var ability: String = Levels.era(i).ability
		if ability != "":
			out[ability] = true
	return out

static func unlocked_in(era_index: int) -> String:
	return Levels.era(era_index).ability

static func label(ability: String) -> String:
	return LABELS.get(ability, "")

static func hint(ability: String) -> String:
	return HINTS.get(ability, "")

static func summary(era_index: int) -> String:
	var names: Array[String] = []
	var unlocked := for_era(era_index)
	for key in ["double_jump", "dash"]:
		if unlocked.get(key, false):
			names.append(LABELS[key])
	if names.is_empty():
		return "Movimento: andar e pular"
	return "Movimento: andar, pular, " + ", ".join(names).to_lower()
