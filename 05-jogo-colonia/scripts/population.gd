class_name Population
extends RefCounted

# Simulação agent-based dos moradores da colônia: sem dependência de cena
# (mesmo padrão de Economy/Buildings), testável headless. A cena só lê
# `villagers` pra desenhar sprites que espelham a posição/estado — ver
# README ("Fase 0 — decisão de arquitetura") pro raciocínio completo.
#
# Um "work site" por TIPO de construção (não por unidade): o jogo já trata
# construções como contagem (`Economy.owned[id] = quantidade`), sem identidade
# individual por cópia, então a vaga de trabalho segue a mesma simplificação —
# um posto de trabalho por tipo, com `capacity = jobs_of(id) * quantidade`.

const PLAZA_POSITION := Vector2(650.0, 695.0) # onde todo mundo come/descansa
const SPAWN_JITTER := 36.0

# Grade dos postos de trabalho: fica dentro da faixa de chão que NÃO fica
# atrás do painel de "Construções" da UI (que cobre x ⪆ 735 na tela de
# 1280×720) — senão quem trabalha nas construções das eras tardias (a lista
# tem 15 tipos) ficaria invisível atrás do painel. Por isso é uma grade que
# quebra linha, não uma fileira única esticando pra direita.
const SITE_ORIGIN := Vector2(40.0, 468.0)
const SITE_COLS := 8
const SITE_SPACING_X := 82.0
const SITE_SPACING_Y := 24.0

const IDLE_BUFFER := 3           # gente ociosa "de sobra" além das vagas de trabalho
const POPULATION_CAP := 120      # teto absoluto (30-100+ pedido pelo João, com folga)
const GROWTH_INTERVAL := 8.0     # segundos entre chances de nascer gente nova
const GROWTH_FOOD_COST := 20.0   # comida consumida quando nasce um morador
const GROWTH_FOOD_RESERVE := 30.0 # não nasce ninguém se isso baixar o estoque disso

# Fase 6 (escala): needs + decisão de IA rodam neste intervalo, não todo
# frame — é a parte pesada (percorrer todos os villagers pontuando ações).
# Movimento continua todo frame (é só soma de vetor, barato mesmo com 100+).
const DECISION_INTERVAL := 0.5

const HUNGER_DECAY := 1.0 / 90.0            # fica com fome em ~90s
const ENERGY_DECAY_WORKING := 1.0 / 140.0
const ENERGY_DECAY_IDLE := 1.0 / 260.0
const MOOD_DRIFT_RATE := 1.0 / 30.0

const HUNGER_EAT_THRESHOLD := 0.35
const ENERGY_REST_THRESHOLD := 0.30
const FOOD_PER_EAT_SECOND := 0.6

var villagers: Array = []   # Array[Villager]
var work_sites: Array = []  # Array[Dictionary] {"building_id","position","capacity","workers": Array[int]}
var rng := RandomNumberGenerator.new()

var _next_id := 1
var _growth_clock := 0.0
var _decision_clock := 0.0
var _by_id: Dictionary = {} # cache id -> Villager, reconstruído a cada tick

func get_villager(id: int) -> Villager:
	return _by_id.get(id)

func employed_count() -> int:
	var total := 0
	for v in villagers:
		if v.has_job():
			total += 1
	return total

func count_in_state(state: String) -> int:
	var total := 0
	for v in villagers:
		if v.state == state:
			total += 1
	return total

func average_mood() -> float:
	if villagers.is_empty():
		return 0.0
	var total := 0.0
	for v in villagers:
		total += v.mood
	return total / villagers.size()

func population_target() -> int:
	var total_jobs := 0
	for site in work_sites:
		total_jobs += int(site.capacity)
	return mini(POPULATION_CAP, total_jobs + IDLE_BUFFER)

# ---- spawn ----

func spawn_villager(at: Vector2 = PLAZA_POSITION) -> Villager:
	var jitter := Vector2(rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	var v := Villager.new(_next_id, Villager.random_name(rng), at + jitter)
	_next_id += 1
	villagers.append(v)
	_by_id[v.id] = v
	return v

func ensure_minimum(count: int) -> void:
	while villagers.size() < count and villagers.size() < POPULATION_CAP:
		spawn_villager()

# ---- Fase 3: vagas de trabalho ----

func sync_work_sites(economy: Economy) -> void:
	var new_sites: Array = []
	var index := 0
	for building in Buildings.ALL:
		var id: String = building.id
		var count := economy.count_of(id)
		var col := index % SITE_COLS
		var row := index / SITE_COLS
		var pos := SITE_ORIGIN + Vector2(col * SITE_SPACING_X, row * SITE_SPACING_Y)
		index += 1
		if count <= 0:
			continue
		var capacity: int = Buildings.jobs_of(id) * count
		new_sites.append({"building_id": id, "position": pos, "capacity": capacity, "workers": []})

	# Preserva quem já estava alocado num site que continua existindo, até o
	# limite da nova capacidade (que só cresce nesse jogo — não há venda).
	for site in new_sites:
		for old in work_sites:
			if old.building_id != site.building_id:
				continue
			for vid in old.workers:
				if site.workers.size() < site.capacity:
					site.workers.append(vid)

	work_sites = new_sites
	_reconcile_job_assignments()

func _reconcile_job_assignments() -> void:
	var employed_ids := {}
	for site in work_sites:
		for vid in site.workers:
			employed_ids[vid] = true
	for v in villagers:
		if v.job_id != "" and not employed_ids.has(v.id):
			v.job_id = ""
			if v.state == Villager.STATE_WORKING or (v.state == Villager.STATE_WALKING and v.pending_action == "work"):
				v.state = Villager.STATE_IDLE
				v.pending_action = ""

func _find_site(building_id: String):
	for site in work_sites:
		if site.building_id == building_id:
			return site
	return null

# Vários moradores mandados pro mesmo posto/praça (um só ponto por TIPO de
# construção, ver cabeçalho) iriam parar exatamente no mesmo pixel — este
# deslocamento pseudo-aleatório (mas estável por id) espalha um pouco pra dar
# sensação de gente de verdade, sem precisar de posições únicas por morador.
func _crowd_offset(id: int, spread: float) -> Vector2:
	var h: int = (id * 2654435761) % 100000
	var angle: float = float(h % 360) * PI / 180.0
	var radius: float = spread * float((h / 360) % 100) / 100.0
	return Vector2(cos(angle), sin(angle)) * radius

func assign_jobs() -> void:
	for site in work_sites:
		if site.workers.size() >= site.capacity:
			continue
		for v in villagers:
			if site.workers.size() >= site.capacity:
				break
			if v.has_job():
				continue
			site.workers.append(v.id)
			v.job_id = site.building_id

# Fração (0..1) das vagas de cada construção realmente ocupadas por alguém
# TRABALHANDO agora, ponderada pelo humor médio de quem está lá — é isto que
# Economy.production_per_second(staffing) usa em vez do total comprado.
func staffing_ratios() -> Dictionary:
	var out := {}
	for site in work_sites:
		var capacity: int = site.capacity
		if capacity <= 0:
			continue
		var working := 0
		var mood_sum := 0.0
		for vid in site.workers:
			var v: Villager = get_villager(vid)
			if v != null and v.state == Villager.STATE_WORKING:
				working += 1
				mood_sum += v.mood
		if working <= 0:
			out[site.building_id] = 0.0
			continue
		var avg_mood: float = mood_sum / working
		# Humor baixo penaliza a produção sem zerá-la; humor alto dá um bônus leve.
		var mood_factor: float = clampf(0.6 + 0.5 * avg_mood, 0.6, 1.1)
		out[site.building_id] = clampf((float(working) / float(capacity)) * mood_factor, 0.0, 1.0)
	return out

# ---- ciclo principal ----

func tick(delta: float, economy: Economy) -> void:
	_by_id.clear()
	for v in villagers:
		_by_id[v.id] = v

	_move_all(delta)

	_growth_clock += delta
	if _growth_clock >= GROWTH_INTERVAL:
		_growth_clock = 0.0
		_maybe_grow(economy)

	_decision_clock += delta
	if _decision_clock >= DECISION_INTERVAL:
		var step: float = _decision_clock
		_decision_clock = 0.0
		assign_jobs()
		_update_needs_and_decisions(step, economy)

# Fase 2: cada villager anda em linha reta até target_position. O terreno da
# vila é pequeno e sem obstáculos, então isto é suficiente pra ter movimento
# de verdade sem precisar de NavigationAgent2D (que exigiria montar um
# NavigationRegion2D dependente de cena, quebrando o padrão "lógica testável
# sem cena" que o resto do projeto segue).
func _move_all(delta: float) -> void:
	for v in villagers:
		if not v.is_moving():
			continue
		var to_target: Vector2 = v.target_position - v.position
		var dist: float = to_target.length()
		var step: float = v.speed * delta
		if step >= dist:
			v.position = v.target_position
		else:
			v.position += to_target.normalized() * step
		# Detecta a chegada no mesmo passo que ela acontece (não no próximo
		# tick): senão quem chega exatamente no alvo fica um frame "andando"
		# sem destino, um atraso bobo de reagir ao próprio movimento.
		if not v.is_moving() and v.state == Villager.STATE_WALKING:
			_arrive(v)

func _arrive(v: Villager) -> void:
	match v.pending_action:
		"work":
			v.state = Villager.STATE_WORKING
		"eat":
			v.state = Villager.STATE_EATING
			v.action_timer = Villager.EAT_DURATION
		"rest":
			v.state = Villager.STATE_RESTING
			v.action_timer = Villager.REST_DURATION
		_:
			v.state = Villager.STATE_IDLE
	v.pending_action = ""

func _send_to(v: Villager, target: Vector2, action: String) -> void:
	if v.position.distance_squared_to(target) <= 4.0:
		v.pending_action = action
		_arrive(v)
		return
	v.target_position = target
	v.state = Villager.STATE_WALKING
	v.pending_action = action

# Fase 4 (needs) + Fase 5 (IA de decisão por utilidade). `step` é o tempo
# acumulado desde a última avaliação (~DECISION_INTERVAL), não o delta do
# frame — ver a nota de escala em `tick()`.
func _update_needs_and_decisions(step: float, economy: Economy) -> void:
	for v in villagers:
		v.hunger = clampf(v.hunger - HUNGER_DECAY * step, 0.0, 1.0)
		var energy_decay: float = ENERGY_DECAY_WORKING if v.state == Villager.STATE_WORKING else ENERGY_DECAY_IDLE
		v.energy = clampf(v.energy - energy_decay * step, 0.0, 1.0)
		var mood_target: float = clampf(0.3 + 0.4 * v.hunger + 0.3 * v.energy, 0.0, 1.0)
		v.mood = move_toward(v.mood, mood_target, MOOD_DRIFT_RATE * step)

		match v.state:
			Villager.STATE_EATING:
				v.action_timer -= step
				var wanted: float = FOOD_PER_EAT_SECOND * step
				var available: float = economy.amount("comida")
				var consumed: float = minf(wanted, available)
				if consumed > 0.0:
					economy.add("comida", -consumed)
				if wanted > 0.0:
					v.hunger = clampf(v.hunger + (consumed / wanted) * step / Villager.EAT_DURATION, 0.0, 1.0)
				if v.action_timer <= 0.0:
					v.state = Villager.STATE_IDLE
			Villager.STATE_RESTING:
				v.action_timer -= step
				v.energy = clampf(v.energy + step / Villager.REST_DURATION, 0.0, 1.0)
				if v.action_timer <= 0.0:
					v.state = Villager.STATE_IDLE
			Villager.STATE_WALKING:
				pass # já decidiu, só falta chegar
			_:
				_decide_action(v)

# Utility AI: cada ação candidata recebe uma pontuação de urgência; a maior
# vence. "Trabalhar" tem uma urgência-base moderada (só perde pra necessidades
# realmente baixas), então gente empregada com fome/energia ok volta ao posto
# sozinha — e quem está com fome/cansaço crítico larga o trabalho pra resolver.
func _decide_action(v: Villager) -> void:
	var want_eat: float = (1.0 - v.hunger) if v.hunger < HUNGER_EAT_THRESHOLD else 0.0
	var want_rest: float = (1.0 - v.energy) * 1.1 if v.energy < ENERGY_REST_THRESHOLD else 0.0
	var want_work: float = 0.55 if v.has_job() else 0.0
	var want_idle: float = 0.1

	var best: String = "idle"
	var best_score: float = want_idle
	if want_eat > best_score:
		best = "eat"; best_score = want_eat
	if want_rest > best_score:
		best = "rest"; best_score = want_rest
	if want_work > best_score:
		best = "work"; best_score = want_work

	match best:
		"eat":
			if v.state != Villager.STATE_EATING:
				_send_to(v, PLAZA_POSITION + _crowd_offset(v.id, 28.0), "eat")
		"rest":
			if v.state != Villager.STATE_RESTING:
				_send_to(v, PLAZA_POSITION + _crowd_offset(v.id, 28.0), "rest")
		"work":
			var site = _find_site(v.job_id)
			if site != null and v.state != Villager.STATE_WORKING:
				_send_to(v, site.position + _crowd_offset(v.id, 16.0), "work")
		_:
			if v.state == Villager.STATE_WORKING:
				v.state = Villager.STATE_IDLE

# ---- crescimento populacional ----

func _maybe_grow(economy: Economy) -> void:
	if villagers.size() >= population_target():
		return
	if economy.amount("comida") < GROWTH_FOOD_COST + GROWTH_FOOD_RESERVE:
		return
	economy.add("comida", -GROWTH_FOOD_COST)
	spawn_villager()

# Chamado quando o jogo reabre depois de tempo offline: não anima ninguém
# andando (seria caro e invisível), só deixa a população descansada e permite
# crescer, proporcional ao mesmo teto de tempo do progresso econômico offline.
func apply_offline_catchup(offline_seconds: float, economy: Economy) -> void:
	for v in villagers:
		v.hunger = 1.0
		v.energy = 1.0
		v.state = Villager.STATE_IDLE
		v.pending_action = ""
	var capped: float = minf(offline_seconds, Economy.OFFLINE_CAP_SECONDS)
	var attempts: int = int(capped / GROWTH_INTERVAL)
	for _i in mini(attempts, POPULATION_CAP):
		_maybe_grow(economy)
	sync_work_sites(economy)
	assign_jobs()

# ---- persistência ----

func to_dict() -> Dictionary:
	var arr: Array = []
	for v in villagers:
		arr.append(v.to_dict())
	return {"villagers": arr, "next_id": _next_id}

func from_dict(data: Dictionary, economy: Economy) -> void:
	villagers.clear()
	_by_id.clear()
	var saved = data.get("villagers", [])
	if saved is Array:
		for item in saved:
			if item is Dictionary:
				var v := Villager.from_dict(item)
				villagers.append(v)
				_by_id[v.id] = v
	_next_id = int(data.get("next_id", villagers.size() + 1))
	sync_work_sites(economy)
