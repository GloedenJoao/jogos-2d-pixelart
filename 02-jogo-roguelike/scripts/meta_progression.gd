class_name MetaProgression
extends RefCounted

# Meta-progressão entre corridas: o ouro que sobra vira upgrades permanentes,
# comprados no "acampamento" entre uma descida e outra.
#
# Toda a lógica é pura (opera sobre dicionários), pra ser testável sem cena:
#   state = {"gold": int, "levels": {"vitalidade": 2, ...}}

const UPGRADES := [
	{
		"key": "vitalidade",
		"label": "Vitalidade",
		"desc": "+4 HP máximo",
		"base_cost": 20,
		"cost_step": 15,
		"max_level": 5,
		"amount": 4,
	},
	{
		"key": "forca",
		"label": "Força",
		"desc": "+1 de ataque",
		"base_cost": 30,
		"cost_step": 25,
		"max_level": 4,
		"amount": 1,
	},
	{
		"key": "suprimentos",
		"label": "Suprimentos",
		"desc": "+1 poção inicial",
		"base_cost": 25,
		"cost_step": 20,
		"max_level": 3,
		"amount": 1,
	},
	{
		"key": "sorte",
		"label": "Sorte",
		"desc": "+15% de ouro coletado",
		"base_cost": 40,
		"cost_step": 30,
		"max_level": 3,
		"amount": 15,
	},
]

static func find(key: String) -> Dictionary:
	for upgrade in UPGRADES:
		if upgrade.key == key:
			return upgrade
	return {}

static func get_level(levels: Dictionary, key: String) -> int:
	return int(levels.get(key, 0))

static func is_maxed(levels: Dictionary, key: String) -> bool:
	var upgrade := find(key)
	if upgrade.is_empty():
		return true
	return get_level(levels, key) >= int(upgrade.max_level)

# Custo do PRÓXIMO nível. Retorna -1 quando já está no máximo.
static func cost_for(levels: Dictionary, key: String) -> int:
	var upgrade := find(key)
	if upgrade.is_empty() or is_maxed(levels, key):
		return -1
	return int(upgrade.base_cost) + int(upgrade.cost_step) * get_level(levels, key)

static func can_afford(state: Dictionary, key: String) -> bool:
	var cost := cost_for(state.get("levels", {}), key)
	return cost >= 0 and int(state.get("gold", 0)) >= cost

# Retorna um novo estado; não muta o recebido.
static func purchase(state: Dictionary, key: String) -> Dictionary:
	var levels: Dictionary = (state.get("levels", {}) as Dictionary).duplicate()
	var gold: int = int(state.get("gold", 0))
	var cost := cost_for(levels, key)
	if cost < 0:
		return {"ok": false, "reason": "maxed", "gold": gold, "levels": levels}
	if gold < cost:
		return {"ok": false, "reason": "sem_ouro", "gold": gold, "levels": levels}
	levels[key] = get_level(levels, key) + 1
	return {"ok": true, "reason": "", "gold": gold - cost, "levels": levels}

# ---- efeitos dos upgrades numa corrida ----

static func bonus(levels: Dictionary, key: String) -> int:
	var upgrade := find(key)
	if upgrade.is_empty():
		return 0
	return get_level(levels, key) * int(upgrade.amount)

static func max_hp_for(levels: Dictionary, base_hp: int) -> int:
	return base_hp + bonus(levels, "vitalidade")

static func attack_for(levels: Dictionary, base_attack: int) -> int:
	return base_attack + bonus(levels, "forca")

static func starting_potions(levels: Dictionary) -> int:
	return bonus(levels, "suprimentos")

static func gold_multiplier(levels: Dictionary) -> float:
	return 1.0 + bonus(levels, "sorte") / 100.0

static func apply_gold_bonus(levels: Dictionary, amount: int) -> int:
	return int(round(amount * gold_multiplier(levels)))
