class_name Economy
extends RefCounted

# Toda a matemática do jogo, sem nenhuma dependência de cena: estoque de
# recursos, produção por segundo, custo crescente das construções, avanço de era
# e progresso offline. Assim dá pra testar o jogo inteiro headless.

const RESOURCES := ["comida", "materiais", "conhecimento"]
const OFFLINE_CAP_SECONDS := 8.0 * 3600.0

var resources: Dictionary = {"comida": 0.0, "materiais": 0.0, "conhecimento": 0.0}
var owned: Dictionary = {}   # id -> quantidade
var era_index := 0
var clicks := 0
var elapsed := 0.0           # segundos jogados nesta civilização

func amount(resource: String) -> float:
	return float(resources.get(resource, 0.0))

func add(resource: String, value: float) -> void:
	resources[resource] = amount(resource) + value

func count_of(id: String) -> int:
	return int(owned.get(id, 0))

# ---- clique manual ----

func click_yield() -> float:
	return Eras.click_power(era_index)

func gather(resource: String) -> bool:
	if not Eras.era(era_index).click_resources.has(resource):
		return false
	add(resource, click_yield())
	clicks += 1
	return true

# ---- produção automática ----

func production_per_second() -> Dictionary:
	var out := {"comida": 0.0, "materiais": 0.0, "conhecimento": 0.0}
	for id in owned:
		var building := Buildings.find(id)
		if building.is_empty():
			continue
		for resource in building.produces:
			out[resource] += float(building.produces[resource]) * count_of(id)
	return out

func tick(delta: float) -> Dictionary:
	var gained := {}
	var rate := production_per_second()
	for resource in rate:
		var value: float = rate[resource] * delta
		if value > 0.0:
			add(resource, value)
		gained[resource] = value
	elapsed += delta
	return gained

# ---- compras ----

# O custo sobe geometricamente a cada cópia comprada (padrão de jogo idle).
func cost_of(id: String) -> Dictionary:
	var building := Buildings.find(id)
	if building.is_empty():
		return {}
	var multiplier: float = pow(Buildings.COST_GROWTH, count_of(id))
	var out := {}
	for resource in building.cost:
		out[resource] = ceilf(float(building.cost[resource]) * multiplier)
	return out

func can_afford(costs: Dictionary) -> bool:
	for resource in costs:
		if amount(resource) < float(costs[resource]):
			return false
	return true

func is_unlocked(id: String) -> bool:
	var building := Buildings.find(id)
	return not building.is_empty() and int(building.era) <= era_index

func can_buy(id: String) -> bool:
	return is_unlocked(id) and can_afford(cost_of(id))

func buy(id: String) -> bool:
	return buy_n(id, 1)

# Custo de comprar `n` cópias de uma vez, já com o crescimento geométrico
# aplicado a partir da quantidade atual (soma de progressão geométrica).
func cost_of_n(id: String, n: int) -> Dictionary:
	var building := Buildings.find(id)
	if building.is_empty() or n <= 0:
		return {}
	var r: float = Buildings.COST_GROWTH
	var series: float = pow(r, count_of(id)) * (pow(r, n) - 1.0) / (r - 1.0)
	var out := {}
	for resource in building.cost:
		out[resource] = ceilf(float(building.cost[resource]) * series)
	return out

func can_buy_n(id: String, n: int) -> bool:
	return is_unlocked(id) and n > 0 and can_afford(cost_of_n(id, n))

func buy_n(id: String, n: int) -> bool:
	if not can_buy_n(id, n):
		return false
	var costs := cost_of_n(id, n)
	for resource in costs:
		add(resource, -float(costs[resource]))
	owned[id] = count_of(id) + n
	return true

# Quantas cópias dá pra comprar de uma vez com o estoque atual (pro botão "xMáx").
func max_affordable(id: String, cap: int = 999) -> int:
	if not is_unlocked(id):
		return 0
	var lo := 0
	var hi := cap
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if can_afford(cost_of_n(id, mid)):
			lo = mid
		else:
			hi = mid - 1
	return lo

func total_buildings() -> int:
	var total := 0
	for id in owned:
		total += count_of(id)
	return total

# ---- eras ----

func can_advance() -> bool:
	if Eras.is_last(era_index):
		return false
	return can_afford(Eras.requirement(era_index))

# Avançar consome o requisito: a civilização investe tudo na virada de era.
func advance() -> bool:
	if not can_advance():
		return false
	var requirement := Eras.requirement(era_index)
	for resource in requirement:
		add(resource, -float(requirement[resource]))
	era_index += 1
	return true

func era_progress() -> float:
	var requirement := Eras.requirement(era_index)
	if requirement.is_empty():
		return 1.0
	var worst := 1.0
	for resource in requirement:
		var needed := float(requirement[resource])
		if needed <= 0.0:
			continue
		worst = minf(worst, amount(resource) / needed)
	return clampf(worst, 0.0, 1.0)

# ---- progresso offline ----

# Tempo fora do jogo rende produção (com teto), pra quem fecha e volta depois.
func apply_offline(seconds: float) -> Dictionary:
	var capped := clampf(seconds, 0.0, OFFLINE_CAP_SECONDS)
	if capped <= 0.0:
		return {"seconds": 0.0, "gained": {}}
	var gained := tick(capped)
	return {"seconds": capped, "gained": gained}

# ---- persistência ----

func to_dict() -> Dictionary:
	return {
		"resources": resources.duplicate(),
		"owned": owned.duplicate(),
		"era_index": era_index,
		"clicks": clicks,
		"elapsed": elapsed,
	}

func from_dict(data: Dictionary) -> void:
	var saved_resources = data.get("resources", {})
	for resource in RESOURCES:
		resources[resource] = float(saved_resources.get(resource, 0.0)) if saved_resources is Dictionary else 0.0
	owned = {}
	var saved_owned = data.get("owned", {})
	if saved_owned is Dictionary:
		for id in saved_owned:
			var count := int(saved_owned[id])
			if count > 0 and not Buildings.find(id).is_empty():
				owned[id] = count
	era_index = clampi(int(data.get("era_index", 0)), 0, Eras.count() - 1)
	clicks = int(data.get("clicks", 0))
	elapsed = float(data.get("elapsed", 0.0))

static func from_save(data: Dictionary) -> Economy:
	var economy := Economy.new()
	economy.from_dict(data)
	return economy

# ---- formatação (usada pela UI e pelos testes de HUD) ----

static func format_amount(value: float) -> String:
	if value >= 1000000.0:
		return "%.1fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	if value >= 100.0:
		return "%d" % int(value)
	return "%.1f" % value

static func format_rate(value: float) -> String:
	return "%s/s" % format_amount(value)
