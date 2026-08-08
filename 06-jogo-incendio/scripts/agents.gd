class_name Agents
extends RefCounted

# As duas populações do vale, e por que são duas.
#
# **Brigadistas** obedecem. Você não cava: você põe uma ordem no mapa e alguém
# caminha até lá. Isso é o que impede o jogo de virar pintura de células —
# entre a decisão e o efeito existe uma travessia, e a travessia pode falhar
# (o fogo fecha o caminho, o alvo deixa de fazer sentido, o calor obriga a
# recuar). Errar o lugar custa o tempo da ida, e é isso que faz "onde eu clico"
# ser uma decisão em vez de um clique.
#
# **Moradores** não obedecem. Eles reagem ao campo de perigo por conta própria:
# ficam em casa até perceberem o fogo, correm para o abrigo alcançável mais
# perto, e entram em pânico quando não há nenhum. Você não os comanda — você
# muda o mapa em que eles decidem. Abrir um caminho seguro é uma ordem
# indireta, e é a forma mais bonita de controle que este jogo tem.
#
# É a mesma IA reativa do Projeto 5 com a entrada trocada: lá o morador olhava
# pra dentro (fome, sono, convívio); aqui ele olha pra fora, pro campo. O
# comportamento que sai é irreconhecível — o que era rotina virou fuga.

const CREW_SPEED := 78.0          # px/s (~2,4 células por segundo)
const CIVIL_SPEED := 62.0
const PANIC_SPEED := 88.0

# Acima disto o brigadista larga a ordem e recua. Ele não morre: perder gente
# por uma ordem mal dada seria punição sem aviso, e o custo real já é o tempo
# perdido na ida e na volta.
const RETREAT_DANGER := 0.5
const RESUME_DANGER := 0.22

# O morador só foge do que ele percebe. Ficar em casa enquanto o vale queima do
# outro lado não é burrice da IA — é o relógio do jogador: chega uma hora em
# que evacuar deixa de ser opcional.
const AWARE_DANGER := 0.10
const AWARE_RADIUS := 7           # células até um foco visível

const PANIC_TIME := 3.0
const LETHAL_TIME := 2.2          # segundos dentro do fogo até se perder
const CALM_RADIUS := 1.6          # células: brigadista por perto tira do pânico

class Person extends RefCounted:
	var pos := Vector2.ZERO
	var look: Dictionary = {}
	var facing := Vector2.DOWN
	var route: Array = []
	var route_version := -1
	var walk := 0.0               # fase do passo, pra cena animar
	var moving := false
	var state := "idle"

	func cell() -> Vector2i:
		return Layout.cell_of(pos)

class Firefighter extends Person:
	var order := -1               # índice em `orders`, ou -1
	var work_left := 0.0
	var busy_cell := Vector2i(-1, -1)

class Civilian extends RefCounted:
	var pos := Vector2.ZERO
	var look: Dictionary = {}
	var facing := Vector2.DOWN
	var route: Array = []
	var route_version := -1
	var walk := 0.0
	var moving := false
	var state := "calm"           # calm · fleeing · panic · safe · lost
	var aware := false
	var panic_left := 0.0
	var exposure := 0.0
	var target := Vector2i(-1, -1)

	func cell() -> Vector2i:
		return Layout.cell_of(pos)

class Order extends RefCounted:
	var tool_id := 0
	var cell := Vector2i.ZERO
	var taken_by := -1
	# Segundos que esta ordem passou sem ninguém conseguir pegá-la. Existe
	# porque uma célula pode ficar inalcançável (o fogo fecha o caminho) e a
	# ordem então vira zumbi: o brigadista mais próximo tenta, não acha rota,
	# larga, e tenta de novo no frame seguinte, parado, pra sempre. Passando do
	# limite a Mission cancela e devolve o recurso — o que também avisa o
	# jogador de que aquele lugar não dá mais.
	var waiting := 0.0

var crew: Array = []              # Firefighter
var civilians: Array = []         # Civilian
var orders: Array = []            # Order
var shelters: Array = []          # Vector2i

var safe_count := 0
var lost_count := 0

# Só pra diagnóstico e telemetria de balanceamento: quantas ordens foram
# emitidas, quantas chegaram a ser executadas e quantas morreram no caminho
# (alvo que pegou fogo antes, rota que fechou). A diferença entre a primeira e
# a segunda é a medida honesta de quanto o vale está atrapalhando o jogador.
var orders_given := 0
var orders_done := 0
var orders_lost := 0

var _sim: FireSim = null
var _nav: Nav = null
var _rng := RandomNumberGenerator.new()

func setup(sim: FireSim, nav: Nav, parsed: Levels.Parsed, seed_value: int) -> void:
	_sim = sim
	_nav = nav
	_rng.seed = seed_value
	crew.clear()
	civilians.clear()
	orders.clear()
	shelters = parsed.shelters.duplicate()
	safe_count = 0
	lost_count = 0

	for cell in parsed.crew:
		var person := Firefighter.new()
		person.pos = Layout.cell_center(cell)
		person.look = PersonArt.crew_look(_rng)
		crew.append(person)

	for cell in parsed.civilians:
		var civil := Civilian.new()
		civil.pos = Layout.cell_center(cell)
		civil.look = PersonArt.civilian_look(_rng)
		civilians.append(civil)

# ---- ordens ----

# Devolve false quando a ordem não faz sentido (célula inválida pra ferramenta,
# recurso esgotado, ou já existe ordem igual ali). A cena usa isso pra recusar
# o clique com um aviso em vez de fingir que aceitou.
func give_order(tool_id: int, cell: Vector2i) -> bool:
	if not Tools.can_target(tool_id, _sim, cell):
		return false
	for existing in orders:
		if existing.cell == cell:
			return false
	var order := Order.new()
	order.tool_id = tool_id
	order.cell = cell
	orders.append(order)
	orders_given += 1
	return true

func cancel_order_at(cell: Vector2i) -> bool:
	for i in orders.size():
		if orders[i].cell == cell:
			_drop_order(i)
			return true
	return false

func _drop_order(index: int) -> void:
	var order: Order = orders[index]
	if order.taken_by >= 0 and order.taken_by < crew.size():
		var person: Firefighter = crew[order.taken_by]
		person.order = -1
		person.route.clear()
		person.state = "idle"
	orders.remove_at(index)
	# Os índices guardados pelos brigadistas se referem a posições da lista.
	for person in crew:
		if person.order > index:
			person.order -= 1

func pending_orders() -> int:
	return orders.size()

# ---- passo ----

func update(delta: float) -> void:
	_nav.tick(delta)
	_assign_orders()
	for i in crew.size():
		_update_firefighter(crew[i], i, delta)
	for civil in civilians:
		_update_civilian(civil, delta)

# Cada ordem livre vai pro brigadista ocioso que chega mais rápido — medido em
# tamanho de rota, não em distância reta. Num vale cortado pelo fogo, o mais
# perto em linha reta costuma ser o que teria de dar a volta no incêndio.
func _assign_orders() -> void:
	for i in orders.size():
		var order: Order = orders[i]
		if order.taken_by >= 0 and order.taken_by < crew.size() and crew[order.taken_by].order == i:
			continue
		var best := -1
		var best_cost := 1e9
		for c in crew.size():
			var person: Firefighter = crew[c]
			if person.order >= 0 or person.state == "retreating":
				continue
			var route := _nav.path(person.cell(), order.cell)
			if route.is_empty() and person.cell() != order.cell:
				continue
			var cost := float(route.size())
			if cost < best_cost:
				best_cost = cost
				best = c
		if best >= 0:
			order.taken_by = best
			var chosen: Firefighter = crew[best]
			chosen.order = i
			chosen.route.clear()
			chosen.state = "moving"
		else:
			order.taken_by = -1

# Ordens que ninguém consegue alcançar há tempo demais. Quem cancela é a
# Mission, que é quem sabe devolver água e contra-fogo ao orçamento.
const ORDER_TIMEOUT := 7.0

func stale_orders(delta: float) -> Array:
	var stale: Array = []
	for order in orders:
		if order.taken_by < 0:
			order.waiting += delta
			if order.waiting >= ORDER_TIMEOUT:
				stale.append(order.cell)
		else:
			order.waiting = 0.0
	return stale

func _update_firefighter(person: Firefighter, index: int, delta: float) -> void:
	var here := person.cell()
	var danger := _sim.danger_at(here.x, here.y)

	# Recuo tem prioridade sobre qualquer ordem: ninguém cava dentro do fogo.
	if danger >= RETREAT_DANGER and person.state != "retreating":
		if person.order >= 0:
			var order: Order = orders[person.order]
			order.taken_by = -1
			person.order = -1
		person.state = "retreating"
		person.route = _nav.path(here, _nav.safest_nearby(here))
		person.route_version = _nav.version

	match person.state:
		"retreating":
			if _advance(person, CREW_SPEED, delta) or danger <= RESUME_DANGER:
				if danger <= RESUME_DANGER:
					person.state = "idle"
					person.route.clear()
				else:
					person.route = _nav.path(person.cell(), _nav.safest_nearby(person.cell()))
					person.route_version = _nav.version
		"moving":
			if person.order < 0 or person.order >= orders.size():
				person.state = "idle"
				return
			var order: Order = orders[person.order]
			# O mundo mudou durante a caminhada? Alvo que deixou de fazer
			# sentido (a célula já pegou fogo, por exemplo) é ordem cancelada,
			# não brigadista parado em cima dela esperando.
			if not Tools.can_target(order.tool_id, _sim, order.cell):
				orders_lost += 1
				_drop_order(person.order)
				person.state = "idle"
				return
			if person.route.is_empty() or person.route_version != _nav.version:
				person.route = _nav.path(person.cell(), order.cell)
				person.route_version = _nav.version
				if person.route.is_empty() and person.cell() != order.cell:
					# Sem rota agora; solta a ordem pra outro tentar e espera.
					order.taken_by = -1
					person.order = -1
					person.state = "idle"
					return
			var arrived := _advance(person, CREW_SPEED, delta)
			if arrived and person.cell().distance_to(Vector2(order.cell)) < 1.5:
				person.state = "working"
				person.work_left = Tools.seconds_of(order.tool_id)
				person.busy_cell = order.cell
				person.facing = (Layout.cell_center(order.cell) - person.pos).normalized()
				if person.facing == Vector2.ZERO:
					person.facing = Vector2.DOWN
		"working":
			if person.order < 0 or person.order >= orders.size():
				person.state = "idle"
				return
			person.work_left -= delta
			if person.work_left <= 0.0:
				var order: Order = orders[person.order]
				Tools.apply(order.tool_id, _sim, order.cell)
				orders_done += 1
				_drop_order(person.order)
				person.state = "idle"
				person.busy_cell = Vector2i(-1, -1)
				# O terreno mudou embaixo dos pés: o mapa de custo precisa
				# saber disso agora, não daqui a meio segundo.
				_nav.rebuild()
		_:
			person.moving = false

# ---- moradores ----

func _update_civilian(civil: Civilian, delta: float) -> void:
	if civil.state == "safe" or civil.state == "lost":
		civil.moving = false
		return

	var here := civil.cell()
	var danger := _sim.danger_at(here.x, here.y)

	# Estar dentro do fogo tem conta-gotas, não morte instantânea: dá tempo de
	# atravessar uma célula acesa correndo, que é o que uma pessoa faria.
	if _sim.state_at(here.x, here.y) == FireSim.BURNING:
		civil.exposure += delta
		if civil.exposure >= LETHAL_TIME:
			civil.state = "lost"
			lost_count += 1
			return
	else:
		civil.exposure = maxf(0.0, civil.exposure - delta * 0.6)

	if not civil.aware:
		if danger >= AWARE_DANGER or _fire_within(here, AWARE_RADIUS):
			civil.aware = true
			civil.state = "fleeing"
		else:
			civil.moving = false
			return

	if civil.state == "panic":
		civil.panic_left -= delta
		if _crew_near(civil.pos) or civil.panic_left <= 0.0:
			civil.state = "fleeing"
			civil.route.clear()
		else:
			_stumble(civil, delta)
			return

	# Chegou num abrigo?
	for shelter in shelters:
		if here == shelter:
			civil.state = "safe"
			civil.moving = false
			safe_count += 1
			return

	if civil.route.is_empty() or civil.route_version != _nav.version:
		civil.target = _nav.flee_target(here, shelters)
		civil.route = _nav.path(here, civil.target)
		civil.route_version = _nav.version
		if civil.route.is_empty() and here != civil.target:
			civil.state = "panic"
			civil.panic_left = PANIC_TIME
			return

	_advance_civilian(civil, CIVIL_SPEED, delta)

# Pânico não é andar em círculo: é andar pra longe do calor, sem plano. A
# diferença aparece na tela — a pessoa se move, só que pra lugar nenhum bom.
func _stumble(civil: Civilian, delta: float) -> void:
	var here := civil.cell()
	var away := Vector2.ZERO
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var probe := here + Vector2i(dx, dy)
			away -= Vector2(dx, dy) * _sim.danger_at(probe.x, probe.y)
	if away == Vector2.ZERO:
		away = Vector2.from_angle(_rng.randf_range(0.0, TAU))
	away = away.normalized()
	var step := civil.pos + away * PANIC_SPEED * delta
	if not _nav.is_blocked(Layout.cell_of(step)):
		civil.pos = step
		civil.facing = away
		civil.moving = true
		civil.walk += delta * 9.0

func _fire_within(cell: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var probe := cell + Vector2i(dx, dy)
			if _sim.inside(probe.x, probe.y) and _sim.state_at(probe.x, probe.y) == FireSim.BURNING:
				return true
	return false

func _crew_near(position: Vector2) -> bool:
	for person in crew:
		if person.pos.distance_to(position) <= CALM_RADIUS * Layout.CELL:
			return true
	return false

# ---- caminhada ----

# Devolve true quando a rota acabou. Anda em direção ao centro da próxima
# célula da rota; consumir a célula só quando chega perto do centro evita o
# agente cortar diagonal por cima de uma quina de casa.
func _advance(person: Person, speed: float, delta: float) -> bool:
	if person.route.is_empty():
		person.moving = false
		return true
	var target: Vector2 = Layout.cell_center(person.route[0])
	var to_target := target - person.pos
	var step := speed * delta
	if to_target.length() <= step:
		person.pos = target
		person.route.pop_front()
		person.moving = not person.route.is_empty()
		person.walk += 0.4
		return person.route.is_empty()
	person.pos += to_target.normalized() * step
	person.facing = to_target.normalized()
	person.moving = true
	person.walk += delta * 7.0
	return false

func _advance_civilian(civil: Civilian, speed: float, delta: float) -> bool:
	if civil.route.is_empty():
		civil.moving = false
		return true
	var target: Vector2 = Layout.cell_center(civil.route[0])
	var to_target := target - civil.pos
	var step := speed * delta
	if to_target.length() <= step:
		civil.pos = target
		civil.route.pop_front()
		civil.moving = not civil.route.is_empty()
		return civil.route.is_empty()
	civil.pos += to_target.normalized() * step
	civil.facing = to_target.normalized()
	civil.moving = true
	civil.walk += delta * 7.0
	return false

# ---- leitura ----

func civilians_total() -> int:
	return civilians.size()

func all_civilians_resolved() -> bool:
	for civil in civilians:
		if civil.state != "safe" and civil.state != "lost":
			return false
	return true

func fear_of(civil: Civilian) -> float:
	var here := civil.cell()
	return _sim.danger_at(here.x, here.y)
