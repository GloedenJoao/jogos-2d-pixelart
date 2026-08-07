class_name Population
extends RefCounted

# Simulação agent-based dos moradores da colônia: sem dependência de cena
# (mesmo padrão de Economy/Buildings), testável headless. A cena só lê
# `villagers` pra desenhar bonecos que espelham posição, direção e estado.
#
# Um "work site" por TIPO de construção (não por unidade): o jogo já trata
# construções como contagem (`Economy.owned[id] = quantidade`), sem identidade
# individual por cópia, então a vaga de trabalho segue a mesma simplificação —
# um posto de trabalho por tipo, com `capacity = jobs_of(id) * quantidade`.
#
# ---- o que mudou no V2 ----
#
# 1. **Rota em vez de reta.** `_send_to` pede um caminho ao Pathfinder; o
#    morador segue pontos e contorna as casas em vez de atravessá-las.
# 2. **Mais o que fazer.** Trabalhar/comer/descansar viraram sete ações:
#    entram conversar, passear, carregar a produção até o celeiro, levantar uma
#    construção recém-comprada e comemorar. Foi o que tirou a colônia da cara
#    de linha de montagem.
# 3. **Lugares com função.** Come-se na fogueira, descansa-se na sombra,
#    entrega-se no celeiro — não mais "tudo no meio da praça".
# 4. **Ninguém empilha.** Separação local afasta quem ficou no mesmo pixel.
#
# Nota de equilíbrio: carregar, construir e comemorar CONTINUAM contando como
# vaga ocupada em `staffing_ratios()`. São gente fazendo o trabalho da colônia,
# e o V2 é sobre como os moradores se comportam, não sobre rebalancear a
# economia do V1. A única ação que de fato tira alguém do posto é conversar —
# curta, rara, e ela devolve humor, que já multiplica a produção.

const SPAWN_JITTER := 52.0

const IDLE_BUFFER := 3           # gente ociosa "de sobra" além das vagas de trabalho
const POPULATION_CAP := 120      # teto absoluto
const GROWTH_INTERVAL := 8.0     # segundos entre chances de nascer gente nova
const GROWTH_FOOD_COST := 20.0   # comida consumida quando nasce um morador
const GROWTH_FOOD_RESERVE := 30.0 # não nasce ninguém se isso baixar o estoque disso

# Needs + decisão de IA rodam neste intervalo, não todo frame — é a parte
# pesada (percorrer todos os villagers pontuando ações). Movimento continua
# todo frame (é só soma de vetor, barato mesmo com 100+).
const DECISION_INTERVAL := 0.5

const HUNGER_DECAY := 1.0 / 90.0
const ENERGY_DECAY_WORKING := 1.0 / 140.0
const ENERGY_DECAY_IDLE := 1.0 / 260.0
const SOCIAL_DECAY := 1.0 / 240.0           # carência de convívio é lenta
const MOOD_DRIFT_RATE := 1.0 / 30.0

const IDLE_WANDER_CHANCE := 0.35  # chance, por avaliação, de um ocioso passear

const HUNGER_EAT_THRESHOLD := 0.35
const ENERGY_REST_THRESHOLD := 0.30
const SOCIAL_TALK_THRESHOLD := 0.35
const FOOD_PER_EAT_SECOND := 0.6

# Carregar a produção: depois de tanto tempo no posto, o trabalhador leva o que
# rendeu até o celeiro e volta. É a "interação visual ao completar tarefa".
const HAUL_AFTER := 14.0
const HAUL_MOOD_BONUS := 0.06

const CHAT_RADIUS := 260.0        # até onde alguém procura companhia
const SOCIAL_MOOD_BONUS := 0.18

# Separação local: ninguém ocupa o mesmo pixel que outro.
const SEPARATION_RADIUS := 19.0
const SEPARATION_STRENGTH := 6.0

var villagers: Array = []   # Array[Villager]
var work_sites: Array = []  # Array[Dictionary] {"building_id","position","capacity","workers": Array[int]}
var rng := RandomNumberGenerator.new()
var pathfinder := Pathfinder.new()

# Fila de acontecimentos pra cena mostrar (entrega no celeiro, conversa
# começando, obra terminada). A cena drena a cada frame. É uma fila em vez de
# signal porque assim o teste headless lê o que aconteceu sem conectar nada.
var events: Array = []

var _next_id := 1
var _growth_clock := 0.0
var _decision_clock := 0.0
var _by_id: Dictionary = {} # cache id -> Villager, reconstruído a cada tick
var _last_cell: Dictionary = {} # id -> Vector2i, pra só marcar trilha ao trocar de célula

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

func count_carrying() -> int:
	var total := 0
	for v in villagers:
		if v.carrying != "":
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

func drain_events() -> Array:
	var out := events
	events = []
	return out

# ---- spawn ----

func spawn_villager(at: Vector2 = Valley.plaza_center()) -> Villager:
	var jitter := Vector2(rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	var v := Villager.new(_next_id, Villager.random_name(rng), at + jitter)
	v.look = VillagerArt.random_look(rng)
	# Fase própria: sem isso a colônia inteira pisca e respira em uníssono.
	v.anim_phase = rng.randf_range(0.0, 10.0)
	v.social = rng.randf_range(0.7, 1.0)
	_next_id += 1
	villagers.append(v)
	_by_id[v.id] = v
	return v

func ensure_minimum(count: int) -> void:
	while villagers.size() < count and villagers.size() < POPULATION_CAP:
		spawn_villager()

# ---- vagas de trabalho ----

func sync_work_sites(economy: Economy) -> void:
	var new_sites: Array = []
	var built: Array = []
	for building in Buildings.ALL:
		var id: String = building.id
		var count := economy.count_of(id)
		if count <= 0:
			continue
		built.append(id)
		# O posto de trabalho fica na porta da construção de verdade (Valley),
		# não numa fileira genérica: é isso que faz o morador andar até a casa
		# certa e ficar visivelmente trabalhando NELA.
		var capacity: int = Buildings.jobs_of(id) * count
		new_sites.append({"building_id": id, "position": Valley.worker_spot(id), "capacity": capacity, "workers": []})

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
	# A malha de navegação muda junto: casa nova é obstáculo novo.
	pathfinder.rebuild(built)
	_reconcile_job_assignments()

func _reconcile_job_assignments() -> void:
	var employed_ids := {}
	for site in work_sites:
		for vid in site.workers:
			employed_ids[vid] = true
	for v in villagers:
		if v.job_id != "" and not employed_ids.has(v.id):
			v.job_id = ""
			v.carrying = ""
			v.errand = false
			if v.state == Villager.STATE_WORKING or (v.state == Villager.STATE_WALKING and v.pending_action == "work"):
				v.state = Villager.STATE_IDLE
				v.pending_action = ""
				v.clear_path()

func _find_site(building_id: String):
	for site in work_sites:
		if site.building_id == building_id:
			return site
	return null

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

# Estados que contam como "essa pessoa está tocando o trabalho dela". Ver a
# nota de equilíbrio no topo: carregar/construir/comemorar continuam contando.
static func counts_as_staffed(v: Villager) -> bool:
	if v.state == Villager.STATE_WORKING or v.state == Villager.STATE_BUILDING \
			or v.state == Villager.STATE_CELEBRATING:
		return true
	# `errand` cobre a ida COM carga e a volta sem ela. Contar só a ida seria
	# uma pegadinha: metade do trajeto de trabalho apareceria como abandono do
	# posto e a produção cairia sem que nada na regra do jogo tivesse mudado.
	return v.carrying != "" or v.errand

# Fração (0..1) das vagas de cada construção realmente ocupadas, ponderada pelo
# humor médio de quem está lá — é isto que Economy.production_per_second()
# usa em vez do total comprado.
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
			if v != null and counts_as_staffed(v):
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

	for v in villagers:
		v.anim_phase += delta

	_move_all(delta)
	_separate(delta)
	pathfinder.decay(delta)

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

# Segue a rota ponto a ponto. Sem rota (destino colado, ou o A* não achou
# caminho) cai na linha reta de antes — é melhor o morador andar torto que
# congelar no lugar.
func _move_all(delta: float) -> void:
	for v in villagers:
		if v.state != Villager.STATE_WALKING:
			v.velocity = Vector2.ZERO
			continue

		var remaining: float = v.speed * delta
		var moved := false
		while remaining > 0.0:
			var goal: Vector2 = v.path[v.path_index] if v.has_path() else v.target_position
			var to_goal: Vector2 = goal - v.position
			var dist: float = to_goal.length()
			if dist <= 0.001:
				if v.has_path():
					v.path_index += 1
					continue
				break
			v.face_towards(to_goal)
			v.velocity = to_goal / dist * v.speed
			moved = true
			if dist <= remaining:
				v.position = goal
				remaining -= dist
				if v.has_path():
					v.path_index += 1
					if not v.has_path():
						break
				else:
					break
			else:
				v.position += to_goal / dist * remaining
				remaining = 0.0

		if moved:
			_mark_trail(v)
		# Detecta a chegada no mesmo passo em que ela acontece (não no próximo
		# tick): senão quem chega exatamente no alvo fica um frame "andando"
		# sem destino, um atraso bobo de reagir ao próprio movimento.
		if not v.has_path() and not v.is_moving():
			_arrive(v)

# Só conta pisada ao TROCAR de célula: contar todo frame faria a primeira
# caminhada abrir uma estrada e ninguém mais sairia dela.
func _mark_trail(v: Villager) -> void:
	var cell := Pathfinder.cell_of(v.position)
	if _last_cell.get(v.id, Vector2i(-999, -999)) == cell:
		return
	_last_cell[v.id] = cell
	pathfinder.register_step(v.position)

# Empurrão suave entre quem está perto demais. Agrupado por célula do vale, de
# modo que só se comparam vizinhos de verdade — comparar todo mundo com todo
# mundo seria 120² por frame.
func _separate(delta: float) -> void:
	# Teto no passo: o empurrão é proporcional ao delta, e o jogo às vezes
	# avança em passos grandes (progresso offline, testes que simulam 5s de uma
	# vez). Sem teto, um passo de 5s multiplica o empurrão por 60 e arremessa a
	# colônia inteira pra longe do trabalho — que foi exatamente o que o teste
	# de "alguém chega a trabalhar de verdade" pegou.
	var step: float = minf(delta, 0.1)
	var buckets := {}
	for v in villagers:
		if v.state == Villager.STATE_WORKING or v.state == Villager.STATE_RESTING:
			continue # turma no posto e gente deitada têm lugar marcado
		var cell := Pathfinder.cell_of(v.position)
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(v)

	for cell in buckets:
		var group: Array = buckets[cell]
		if group.size() < 2:
			continue
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a: Villager = group[i]
				var b: Villager = group[j]
				var away: Vector2 = b.position - a.position
				var dist: float = away.length()
				if dist > SEPARATION_RADIUS:
					continue
				if dist < 0.01:
					# Exatamente sobrepostos: desempata com o id, senão os dois
					# calculam o mesmo empurrão nulo pra sempre.
					away = Vector2(1.0 if a.id < b.id else -1.0, 0.0)
					dist = 0.01
				var push: Vector2 = away / dist * (SEPARATION_RADIUS - dist) * 0.5 * SEPARATION_STRENGTH * step
				a.position -= push
				b.position += push

func _arrive(v: Villager) -> void:
	v.clear_path()
	match v.pending_action:
		"work":
			v.state = Villager.STATE_WORKING
			v.action_timer = 0.0        # conta há quanto tempo está no posto
			v.errand = false            # chegou: a viagem de trabalho acabou
			v.facing = Villager.DIR_NORTH  # de costas: encara a construção
		"eat":
			v.state = Villager.STATE_EATING
			v.action_timer = Villager.EAT_DURATION
			v.face_point(Valley.hearth())
		"rest":
			v.state = Villager.STATE_RESTING
			v.action_timer = Villager.REST_DURATION
			v.facing = Villager.DIR_SOUTH
		"chat":
			var partner: Villager = get_villager(v.partner_id)
			if partner == null:
				v.state = Villager.STATE_IDLE
				v.partner_id = 0
			else:
				v.state = Villager.STATE_SOCIALIZING
				v.action_timer = Villager.SOCIAL_DURATION
				v.face_point(partner.position)
		"deliver":
			var resource := v.carrying
			v.carrying = ""
			v.state = Villager.STATE_IDLE
			v.mood = clampf(v.mood + HAUL_MOOD_BONUS, 0.0, 1.0)
			events.append({"type": "entrega", "villager": v.id, "resource": resource, "position": v.position})
		"build":
			v.state = Villager.STATE_BUILDING
			v.action_timer = Villager.BUILD_DURATION
			v.facing = Villager.DIR_NORTH
		_:
			v.state = Villager.STATE_IDLE
	v.pending_action = ""

func _send_to(v: Villager, target: Vector2, action: String) -> void:
	if v.position.distance_squared_to(target) <= 9.0:
		v.pending_action = action
		v.clear_path()
		v.target_position = target
		_arrive(v)
		return
	v.set_path(pathfinder.find_path(v.position, target))
	v.state = Villager.STATE_WALKING
	v.pending_action = action

# ---- necessidades e decisão ----

func _update_needs_and_decisions(step: float, economy: Economy) -> void:
	for v in villagers:
		v.hunger = clampf(v.hunger - HUNGER_DECAY * step, 0.0, 1.0)
		var energy_decay: float = ENERGY_DECAY_WORKING if v.state == Villager.STATE_WORKING else ENERGY_DECAY_IDLE
		v.energy = clampf(v.energy - energy_decay * step, 0.0, 1.0)
		if v.state != Villager.STATE_SOCIALIZING:
			v.social = clampf(v.social - SOCIAL_DECAY * step, 0.0, 1.0)
		# Conviver entra no humor junto com fome e energia: uma colônia bem
		# alimentada e sem ninguém pra conversar não é uma colônia feliz.
		var mood_target: float = clampf(0.25 + 0.35 * v.hunger + 0.25 * v.energy + 0.15 * v.social, 0.0, 1.0)
		v.mood = move_toward(v.mood, mood_target, MOOD_DRIFT_RATE * step)

		match v.state:
			Villager.STATE_EATING:
				_tick_eating(v, step, economy)
			Villager.STATE_RESTING:
				v.action_timer -= step
				v.energy = clampf(v.energy + step / Villager.REST_DURATION, 0.0, 1.0)
				if v.action_timer <= 0.0:
					v.state = Villager.STATE_IDLE
			Villager.STATE_SOCIALIZING:
				_tick_socializing(v, step)
			Villager.STATE_CELEBRATING, Villager.STATE_BUILDING:
				v.action_timer -= step
				if v.action_timer <= 0.0:
					v.state = Villager.STATE_IDLE
			Villager.STATE_WORKING:
				v.action_timer += step
				_maybe_start_haul(v)
			Villager.STATE_WALKING:
				pass # já decidiu, só falta chegar
			_:
				_decide_action(v)

func _tick_eating(v: Villager, step: float, economy: Economy) -> void:
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

func _tick_socializing(v: Villager, step: float) -> void:
	var partner: Villager = get_villager(v.partner_id)
	# Se o outro sumiu (foi comer, foi trabalhar, morreu de velho), não faz
	# sentido continuar falando sozinho.
	if partner == null or partner.state != Villager.STATE_SOCIALIZING:
		v.state = Villager.STATE_IDLE
		v.partner_id = 0
		return
	v.action_timer -= step
	v.social = clampf(v.social + step / Villager.SOCIAL_DURATION, 0.0, 1.0)
	v.mood = clampf(v.mood + SOCIAL_MOOD_BONUS * step / Villager.SOCIAL_DURATION, 0.0, 1.0)
	if v.action_timer <= 0.0:
		v.state = Villager.STATE_IDLE
		v.partner_id = 0

# Quem está no posto há bastante tempo pega a produção e leva pro celeiro.
func _maybe_start_haul(v: Villager) -> void:
	if v.action_timer < HAUL_AFTER or v.carrying != "" or not v.has_job():
		return
	var building := Buildings.find(v.job_id)
	if building.is_empty() or building.produces.is_empty():
		return
	v.action_timer = 0.0
	v.carrying = String(building.produces.keys()[0])
	v.errand = true
	_send_to(v, Valley.granary() + Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(-8.0, 14.0)), "deliver")
	events.append({"type": "carga", "villager": v.id, "resource": v.carrying})

# Utility AI: cada ação candidata recebe uma pontuação de urgência; a maior
# vence. "Trabalhar" tem uma urgência-base moderada (só perde pra necessidades
# realmente baixas), então gente empregada com as necessidades em dia volta ao
# posto sozinha — e quem está mal larga o trabalho pra se resolver.
func _decide_action(v: Villager) -> void:
	var want_eat: float = (1.0 - v.hunger) * 1.3 if v.hunger < HUNGER_EAT_THRESHOLD else 0.0
	var want_rest: float = (1.0 - v.energy) * 1.25 if v.energy < ENERGY_REST_THRESHOLD else 0.0
	var want_chat: float = (1.0 - v.social) * 0.8 if v.social < SOCIAL_TALK_THRESHOLD else 0.0
	var want_work: float = 0.55 if v.has_job() else 0.0
	var want_idle: float = 0.1

	var best: String = "idle"
	var best_score: float = want_idle
	if want_eat > best_score:
		best = "eat"; best_score = want_eat
	if want_rest > best_score:
		best = "rest"; best_score = want_rest
	if want_chat > best_score:
		best = "chat"; best_score = want_chat
	if want_work > best_score:
		best = "work"; best_score = want_work

	# Escolher qualquer coisa que não seja voltar ao posto encerra a viagem de
	# trabalho: quem largou a carga e resolveu ir comer não pode continuar
	# contando como vaga ocupada até mudar de ideia.
	if best != "work":
		v.errand = false

	match best:
		"eat":
			# Come-se na fogueira comunal, em roda — não espalhado pela praça.
			_send_to(v, Valley.hearth_spot(rng), "eat")
		"rest":
			# Descansa-se na sombra da borda do vale, longe do burburinho.
			_send_to(v, Valley.shade_spot(rng), "rest")
		"chat":
			_try_start_chat(v)
		"work":
			var site = _find_site(v.job_id)
			if site != null:
				_send_to(v, site.position + Valley.work_slot_offset(site.workers.find(v.id)), "work")
		_:
			# Quem não tem nada pra fazer não fica plantado feito estátua: de vez
			# em quando dá uma volta pelo vale. Sem isto, colônia com folga de
			# gente vira um monte de sprites imóveis e a tela parece congelada.
			if rng.randf() < IDLE_WANDER_CHANCE:
				_send_to(v, Valley.stroll_spot(rng), "idle")

# Procura alguém por perto que também possa parar pra conversar. Os dois se
# encontram no meio do caminho, um de frente pro outro.
func _try_start_chat(v: Villager) -> void:
	var partner: Villager = null
	var best_distance := CHAT_RADIUS
	for other in villagers:
		if other.id == v.id or other.partner_id != 0:
			continue
		if other.state != Villager.STATE_IDLE and other.state != Villager.STATE_WORKING:
			continue
		if other.state == Villager.STATE_WORKING and other.social > SOCIAL_TALK_THRESHOLD:
			continue # quem está bem de convívio não larga o posto pra fofocar
		var distance: float = v.position.distance_to(other.position)
		if distance < best_distance:
			best_distance = distance
			partner = other
	if partner == null:
		# Sem ninguém por perto: dá uma volta, que é como se acha companhia.
		_send_to(v, Valley.stroll_spot(rng), "idle")
		return

	var meeting := Valley.meeting_point(v.position, partner.position)
	v.partner_id = partner.id
	partner.partner_id = v.id
	_send_to(v, meeting + Valley.chat_offset(0), "chat")
	_send_to(partner, meeting + Valley.chat_offset(1), "chat")
	events.append({"type": "conversa", "villager": v.id, "partner": partner.id, "position": meeting})

# ---- gatilhos vindos da cena ----

# Construção recém-comprada: um grupo larga o que está fazendo e vai levantar a
# obra. Puramente visual (não atrasa produção) — é o "algo aconteceu ali" que
# faltava quando o jogador clicava em Construir e nada se mexia no vale.
func start_construction(building_id: String, crew: int = 4) -> int:
	var spot := Valley.worker_spot(building_id)
	var sent := 0
	var candidates: Array = []
	for v in villagers:
		if v.state == Villager.STATE_EATING or v.state == Villager.STATE_RESTING \
				or v.state == Villager.STATE_SOCIALIZING or v.carrying != "":
			continue
		candidates.append(v)
	candidates.sort_custom(func(a: Villager, b: Villager) -> bool:
		return a.position.distance_squared_to(spot) < b.position.distance_squared_to(spot))
	for v in candidates:
		if sent >= crew:
			break
		_send_to(v, spot + Valley.work_slot_offset(sent), "build")
		sent += 1
	if sent > 0:
		events.append({"type": "obra", "building": building_id, "crew": sent, "position": spot})
	return sent

# Virada de era: a colônia comemora. Também só visual.
func celebrate(count: int = 12) -> int:
	var cheered := 0
	for v in villagers:
		if cheered >= count:
			break
		if v.state == Villager.STATE_EATING or v.state == Villager.STATE_RESTING:
			continue
		v.clear_path()
		v.pending_action = ""
		v.state = Villager.STATE_CELEBRATING
		v.action_timer = Villager.CELEBRATE_DURATION
		v.mood = clampf(v.mood + 0.15, 0.0, 1.0)
		cheered += 1
	if cheered > 0:
		events.append({"type": "festa", "crew": cheered})
	return cheered

# ---- crescimento populacional ----

func _maybe_grow(economy: Economy) -> void:
	if villagers.size() >= population_target():
		return
	if economy.amount("comida") < GROWTH_FOOD_COST + GROWTH_FOOD_RESERVE:
		return
	economy.add("comida", -GROWTH_FOOD_COST)
	var born := spawn_villager()
	events.append({"type": "nascimento", "villager": born.id, "position": born.position})

# Chamado quando o jogo reabre depois de tempo offline: não anima ninguém
# andando (seria caro e invisível), só deixa a população descansada e permite
# crescer, proporcional ao mesmo teto de tempo do progresso econômico offline.
func apply_offline_catchup(offline_seconds: float, economy: Economy) -> void:
	for v in villagers:
		v.hunger = 1.0
		v.energy = 1.0
		v.social = 1.0
		v.state = Villager.STATE_IDLE
		v.pending_action = ""
		v.carrying = ""
		v.errand = false
		v.partner_id = 0
		v.clear_path()
	var capped: float = minf(offline_seconds, Economy.OFFLINE_CAP_SECONDS)
	var attempts: int = int(capped / GROWTH_INTERVAL)
	for _i in mini(attempts, POPULATION_CAP):
		_maybe_grow(economy)
	sync_work_sites(economy)
	assign_jobs()
	events.clear()

# ---- persistência ----

func to_dict() -> Dictionary:
	var arr: Array = []
	for v in villagers:
		arr.append(v.to_dict())
	return {"villagers": arr, "next_id": _next_id, "trails": pathfinder.to_dict()}

func from_dict(data: Dictionary, economy: Economy) -> void:
	villagers.clear()
	_by_id.clear()
	_last_cell.clear()
	var saved = data.get("villagers", [])
	if saved is Array:
		for item in saved:
			if item is Dictionary:
				var v := Villager.from_dict(item)
				if v.look.is_empty():
					v.look = VillagerArt.random_look(rng)
				v.anim_phase = rng.randf_range(0.0, 10.0)
				villagers.append(v)
				_by_id[v.id] = v
	_next_id = int(data.get("next_id", villagers.size() + 1))
	var trails = data.get("trails", {})
	if trails is Dictionary:
		pathfinder.from_dict(trails)
	sync_work_sites(economy)
