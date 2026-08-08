class_name FireSim
extends RefCounted

# O autômato celular do incêndio: o jogo inteiro sai daqui.
#
# Nenhum sistema anterior deste repositório tem isto. O inimigo do roguelike
# reage ao jogador; o morador da colônia decide pelas próprias necessidades. Um
# incêndio não decide nada — ele é consequência mecânica do estado do vale, e é
# justamente por isso que dá pra jogar contra ele: se você entende as regras,
# você prevê.
#
# ---- as regras, em ordem ----
#
# 1. Célula em chamas joga CALOR nos 8 vizinhos, proporcional ao `output` do
#    terreno dela e à intensidade da chama.
# 2. Esse calor é dobrado ou anulado por VENTO (a favor espalha, contra quase
#    não passa) e por RELEVO (fogo sobe morro muito mais rápido do que desce —
#    a chama pré-aquece a encosta acima dela).
# 3. O mesmo calor SECA o vizinho. Terreno seco pega fogo mais fácil, o que
#    realimenta a propagação: um incêndio grande prepara o próprio caminho.
# 4. Célula acumula calor, perde calor pro ar, e pega fogo quando o acumulado
#    passa o limiar do terreno dela (mais alto se estiver molhada).
# 5. Queimar consome COMBUSTÍVEL. Sem combustível vira cinza — e cinza não
#    queima de novo. Esta regra é o jogo todo: aceiro e contra-fogo não são
#    "poderes", são as duas maneiras de gastar combustível antes do fogo chegar.
#
# ---- por que é determinístico ----
#
# Passo fixo (`TICK`), buffer duplo (todo o calor do tick é somado antes de
# qualquer ignição ser decidida) e nenhuma chamada de RNG durante a simulação —
# a variação por célula vem de `jitter`, sorteado uma vez na montagem a partir
# da semente da fase. Duas partidas da mesma fase com as mesmas ações dão
# exatamente o mesmo incêndio.
#
# Isso não é purismo: é o que permite o bot dos testes vencer as fases de forma
# reproduzível, e é o que faz o jogador poder aprender a fase em vez de torcer.
#
# O buffer duplo também evita um bug clássico de autômato: varrer a grade
# somando calor direto em `heat` faria o fogo andar mais rápido para a direita
# e para baixo (a célula já atualizada acende no mesmo passo), e ninguém
# entenderia por que o incêndio "prefere" um canto da tela.

enum { INTACT, BURNING, BURNT }

const TICK := 0.1                # passo fixo da simulação, em segundos

# --- constantes calibradas (ver _test_front_speed em tests/run_tests.gd) ---
# Uma frente de fogo em capim plano e sem vento tem que andar ~1 célula a cada
# 2 a 4 segundos: rápido o bastante pra assustar, lento o bastante pra dar
# tempo de cavar.
#
# O que faz esse ritmo NÃO é diminuir o calor emitido — é o calor DEMORAR a se
# dissipar (`COOL_RATE` baixo). A diferença importa. Com dissipação rápida, uma
# célula só acende se o que ela recebe por segundo vencer o que ela perde por
# segundo, e o incêndio inteiro passa a viver no fio da navalha: mexer 10% em
# qualquer constante faz o fogo ou morrer sozinho ou varrer o mapa. Com
# dissipação lenta, o calor ACUMULA, e o tempo até acender vira uma rampa
# suave — dá pra ter fogo lento e robusto ao mesmo tempo, que é o que um jogo
# precisa. Também é o que dá sentido a "o fogo está chegando": a célula à
# frente esquenta bem antes de pegar, e a previsão consegue avisar.
const SPREAD := 0.20             # quanto do calor emitido chega ao vizinho
const COOL_RATE := 0.15          # fração do calor perdida por segundo
const MOISTURE_RESIST := 2.6     # quanto a umidade encarece a ignição

# Secagem devagar: o calor que chega tira umidade, mas uma célula molhada tem
# que continuar molhada por dezenas de segundos com o fogo ao lado, senão o
# balde d'água não muda nada — foi exatamente o que a primeira calibração fez
# (capim encharcado propagava no mesmo tempo do capim seco, porque secava em
# pouco mais de um segundo).
const DRY_RATE := 0.15           # o calor recebido seca a célula
const EVAPORATE := 0.02          # água aplicada volta ao normal com o tempo
const RECOVER := 0.004           # terreno ressecado se recupera bem devagar

const WIND_GAIN := 1.7           # a favor do vento espalha até 2,7×
# Contra o vento o fogo quase para, mas não para de vez: 0,32 dá uma
# propagação de dezenas de segundos por célula. "Quase parado" é uma decisão
# do jogador (dá pra ignorar aquele lado por enquanto); "parado" seria uma
# regra invisível que resolve a fase sozinha.
const WIND_MIN := 0.40
const SLOPE_UP := 0.55           # por unidade de subida
const SLOPE_DOWN := 0.30         # por unidade de descida
const SLOPE_MIN := 0.25
const SLOPE_MAX := 2.5

# Chama fraca no fim do combustível: uma célula quase apagada não pode espalhar
# como uma recém-acesa, senão a borda de trás do incêndio empurra tanto quanto
# a frente e o fogo vira uma mancha que cresce igual pra todo lado.
const EMBER_FRACTION := 0.35
const EMBER_MIN := 0.30

const DOUSE_MOISTURE := 0.85     # umidade que um balde d'água deixa na célula
const JITTER_RANGE := 0.16       # variação do limiar de ignição por célula

# --- faíscas ---
#
# Sem isto o jogo tem uma resposta certa e só uma: uma linha de aceiro de uma
# célula de largura, em qualquer lugar, barra o incêndio pra sempre — o calor
# só alcança vizinhos imediatos, e terra batida nunca vira chama que reemita.
# Fase resolvida, jogo acabado.
#
# Com vento forte, então, a chama joga brasa longe: um pulso de calor a duas ou
# quatro células na direção do vento, por cima do que houver no caminho. É o
# que obriga a decidir entre aceiro largo, aceiro somado a molhar o outro lado,
# ou aceitar o salto e conter o foco novo depois.
#
# A brasa deposita CALOR, não fogo: ela acende capim seco quase na hora e não
# acende casa nenhuma sozinha. Assim a mecânica entra no mesmo modelo do resto
# em vez de virar um dado paralelo que ignora umidade e terreno.
const EMBER_WIND_MIN := 0.45     # abaixo disso o vento não carrega brasa
const EMBER_CHANCE := 0.0016     # por célula em chamas, por passo
const EMBER_MIN_RANGE := 2
const EMBER_MAX_RANGE := 4
const EMBER_HEAT := 0.62         # pulso depositado onde a brasa cai
const EMBER_SPREAD_ANGLE := 0.5  # a brasa desvia até ~29° da direção do vento

# Onde caiu a última brasa de cada passo, pra cena poder desenhar o risco de
# faísca voando. Só visual — a simulação não lê isto.
var embers: Array = []

var cols := 0
var rows := 0

var kind := PackedInt32Array()
var state := PackedInt32Array()
var fuel := PackedFloat32Array()
var moisture := PackedFloat32Array()
var heat := PackedFloat32Array()
var height := PackedFloat32Array()
var jitter := PackedFloat32Array()

# Vento: uma direção base que oscila devagar. A oscilação existe pra que a fase
# não seja resolvível decorando um único ângulo — o jogador precisa olhar a
# bússola de vez em quando —, mas é uma função do tempo decorrido, não sorteio,
# então continua determinística.
var wind_angle := 0.0
var wind_force := 0.0
var wind_swing := 0.0            # amplitude da oscilação, em radianos
var wind_period := 24.0

var elapsed := 0.0
var ticks := 0

# Contadores que a camada de jogo lê pra decidir vitória e derrota.
var houses_lost := 0
var cells_burnt := 0

var _accumulator := 0.0
var _neighbors: Array = []       # por índice: Array de [vizinho, peso_base, subida]

# ---- montagem ----

func setup(map_cols: int, map_rows: int, kinds: PackedInt32Array, heights: PackedFloat32Array, seed_value: int) -> void:
	cols = map_cols
	rows = map_rows
	var n := cols * rows

	kind = kinds.duplicate()
	height = heights.duplicate()
	state = PackedInt32Array()
	state.resize(n)
	fuel = PackedFloat32Array()
	fuel.resize(n)
	moisture = PackedFloat32Array()
	moisture.resize(n)
	heat = PackedFloat32Array()
	heat.resize(n)
	jitter = PackedFloat32Array()
	jitter.resize(n)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for idx in n:
		state[idx] = INTACT
		fuel[idx] = Terrain.fuel_of(kind[idx])
		moisture[idx] = Terrain.moisture_of(kind[idx])
		heat[idx] = 0.0
		jitter[idx] = 1.0 + rng.randf_range(-JITTER_RANGE, JITTER_RANGE)

	_build_neighbors()
	elapsed = 0.0
	ticks = 0
	houses_lost = 0
	cells_burnt = 0
	_accumulator = 0.0

# A vizinhança de cada célula é fixa (a grade não muda de forma durante a
# partida), e o peso geométrico e a subida também. Calcular isso uma vez tira
# oito `normalized()` e oito comparações de altura de dentro do laço quente.
func _build_neighbors() -> void:
	_neighbors.clear()
	_neighbors.resize(cols * rows)
	for y in rows:
		for x in cols:
			var idx := y * cols + x
			var list: Array = []
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
						continue
					var nidx := ny * cols + nx
					var offset := Vector2(dx, dy)
					var base: float = 1.0 if (dx == 0 or dy == 0) else 0.7071
					var rise: float = height[nidx] - height[idx]
					var slope: float = 1.0 + (SLOPE_UP * rise if rise > 0.0 else SLOPE_DOWN * rise)
					list.append([nidx, base * clampf(slope, SLOPE_MIN, SLOPE_MAX), offset.normalized()])
			_neighbors[idx] = list

func set_wind(angle: float, force: float, swing: float = 0.0, period: float = 24.0) -> void:
	wind_angle = angle
	wind_force = force
	wind_swing = swing
	wind_period = maxf(1.0, period)

# O vento AGORA: vetor cuja direção aponta pra onde ele sopra e cujo módulo é a
# força. Função pura do tempo decorrido — mesma partida, mesmo vento.
func current_wind() -> Vector2:
	var angle := wind_angle + sin(elapsed * TAU / wind_period) * wind_swing
	var force := wind_force * (1.0 + 0.18 * sin(elapsed * TAU / (wind_period * 0.37)))
	return Vector2.from_angle(angle) * maxf(0.0, force)

func index_of(x: int, y: int) -> int:
	return y * cols + x

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows

# ---- o passo ----

# Avança em passos fixos. Devolve quantos passos rodaram: quem desenha usa isso
# pra saber se vale redesenhar a camada de fogo.
func advance(delta: float) -> int:
	_accumulator += delta
	var count := 0
	# Teto de passos por chamada: se a máquina engasgar (ou um teste pedir um
	# delta enorme), a simulação atrasa em vez de travar o jogo tentando
	# recuperar centenas de passos num frame só.
	while _accumulator >= TICK and count < 12:
		_accumulator -= TICK
		_tick()
		count += 1
	return count

func _tick() -> void:
	var n := cols * rows
	var incoming := PackedFloat32Array()
	incoming.resize(n)

	var wind := current_wind()
	var wind_strength := wind.length()
	embers.clear()

	for idx in n:
		if state[idx] != BURNING:
			continue
		var full := Terrain.fuel_of(kind[idx])
		var intensity := 1.0
		if full > 0.0:
			intensity = clampf(fuel[idx] / (full * EMBER_FRACTION), EMBER_MIN, 1.0)
		var emitted: float = Terrain.output_of(kind[idx]) * intensity * SPREAD * TICK
		for entry in _neighbors[idx]:
			var nidx: int = entry[0]
			if state[nidx] == BURNT:
				continue
			var direction: Vector2 = entry[2]
			var wind_factor: float = clampf(1.0 + WIND_GAIN * direction.dot(wind), WIND_MIN, 1.0 + WIND_GAIN)
			incoming[nidx] += emitted * float(entry[1]) * wind_factor

		if wind_strength >= EMBER_WIND_MIN and intensity > 0.5:
			var roll := _noise(idx, ticks)
			if roll < EMBER_CHANCE * wind_strength:
				_throw_ember(idx, wind, incoming)

	for idx in n:
		var received: float = incoming[idx]
		heat[idx] = maxf(0.0, heat[idx] * (1.0 - COOL_RATE * TICK)) + received

		var natural: float = Terrain.moisture_of(kind[idx])
		if received > 0.0:
			moisture[idx] = maxf(0.0, moisture[idx] - DRY_RATE * received)
		elif moisture[idx] > natural:
			moisture[idx] = maxf(natural, moisture[idx] - EVAPORATE * TICK)
		elif moisture[idx] < natural:
			moisture[idx] = minf(natural, moisture[idx] + RECOVER * TICK)

		if state[idx] == BURNING:
			fuel[idx] = maxf(0.0, fuel[idx] - Terrain.burn_rate_of(kind[idx]) * TICK)
			if fuel[idx] <= 0.0:
				state[idx] = BURNT
				cells_burnt += 1
				if kind[idx] == Terrain.HOUSE:
					houses_lost += 1
		elif state[idx] == INTACT and fuel[idx] > 0.0:
			if heat[idx] >= ignition_threshold(idx):
				state[idx] = BURNING

	elapsed += TICK
	ticks += 1

func ignition_threshold(idx: int) -> float:
	return Terrain.ignition_of(kind[idx]) * jitter[idx] * (1.0 + MOISTURE_RESIST * moisture[idx])

# Sorteio determinístico. Um RandomNumberGenerator aqui destruiria a promessa
# do arquivo: o número de chamadas por passo dependeria de quantas células
# estão em chamas, então salvar/carregar, ou rodar num quadro mais lento,
# mudaria toda a sequência seguinte. Um hash de (célula, passo) devolve sempre
# o mesmo valor pra mesma partida, sem guardar estado nenhum.
func _noise(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ 0x27d4eb2d
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 1000000) / 1000000.0

func _throw_ember(idx: int, wind: Vector2, incoming: PackedFloat32Array) -> void:
	var x := idx % cols
	var y := idx / cols
	var spin := (_noise(idx, ticks * 31 + 7) - 0.5) * 2.0 * EMBER_SPREAD_ANGLE
	var direction := wind.normalized().rotated(spin)
	var span := EMBER_MIN_RANGE + int(_noise(idx, ticks * 17 + 3) * float(EMBER_MAX_RANGE - EMBER_MIN_RANGE + 1))
	span = clampi(span, EMBER_MIN_RANGE, EMBER_MAX_RANGE)
	var target := Vector2i(x + roundi(direction.x * span), y + roundi(direction.y * span))
	if not inside(target.x, target.y):
		return
	var tidx := index_of(target.x, target.y)
	if state[tidx] != INTACT or fuel[tidx] <= 0.0:
		return
	incoming[tidx] += EMBER_HEAT
	embers.append([Vector2i(x, y), target])

# ---- interferência do jogador (e do incêndio inicial) ----

func ignite(x: int, y: int) -> bool:
	if not inside(x, y):
		return false
	var idx := index_of(x, y)
	if state[idx] != INTACT or fuel[idx] <= 0.0:
		return false
	state[idx] = BURNING
	heat[idx] = maxf(heat[idx], ignition_threshold(idx))
	return true

# Molhar. Numa célula em chamas isto APAGA — é a fantasia do balde d'água, e é
# o que dá à água um papel que o aceiro não tem: desfazer, não só prevenir.
# Em compensação ela não gasta combustível, então uma casa salva a balde
# continua sendo uma casa cercada de mato pronto pra queimar de novo.
func douse(x: int, y: int) -> bool:
	if not inside(x, y):
		return false
	var idx := index_of(x, y)
	if state[idx] == BURNT:
		return false
	if state[idx] == BURNING:
		state[idx] = INTACT
	heat[idx] = 0.0
	moisture[idx] = maxf(moisture[idx], DOUSE_MOISTURE)
	return true

# Cavar aceiro: tira o combustível e o terreno vira terra batida. Não funciona
# no que já está pegando fogo — quem cava está de pé ali.
func strip(x: int, y: int) -> bool:
	if not inside(x, y):
		return false
	var idx := index_of(x, y)
	if state[idx] == BURNING or not Terrain.can_dig(kind[idx]):
		return false
	kind[idx] = Terrain.DIRT
	fuel[idx] = 0.0
	state[idx] = INTACT
	heat[idx] = 0.0
	moisture[idx] = Terrain.moisture_of(Terrain.DIRT)
	# A subida pros vizinhos não mudou, mas o terreno sim: nada a reconstruir
	# na vizinhança, que só depende de geometria e altura.
	return true

# ---- leitura do estado ----

func state_at(x: int, y: int) -> int:
	return state[index_of(x, y)] if inside(x, y) else BURNT

func kind_at(x: int, y: int) -> int:
	return kind[index_of(x, y)] if inside(x, y) else Terrain.ROCK

func heat_at(x: int, y: int) -> float:
	return heat[index_of(x, y)] if inside(x, y) else 0.0

func burning_count() -> int:
	var total := 0
	for idx in state.size():
		if state[idx] == BURNING:
			total += 1
	return total

func is_out() -> bool:
	return burning_count() == 0

func houses_standing() -> int:
	var total := 0
	for idx in kind.size():
		if kind[idx] == Terrain.HOUSE and state[idx] != BURNT:
			total += 1
	return total

func houses_total() -> int:
	var total := 0
	for idx in kind.size():
		if kind[idx] == Terrain.HOUSE:
			total += 1
	return total

# Quão perigoso é ESTAR nesta célula agora. É o que os moradores fogem e o que
# encarece o caminho dos brigadistas.
func danger_at(x: int, y: int) -> float:
	if not inside(x, y):
		return 1.0
	var idx := index_of(x, y)
	if state[idx] == BURNING:
		return 1.0
	return clampf(heat[idx] / 0.9, 0.0, 0.95)

# ---- previsão ----
#
# O overlay de risco não pinta o calor atual: calor atual é quase invisível a
# olho nu e não responde à pergunta que o jogador realmente faz, que é "em
# quanto tempo o fogo chega ALI".
#
# Então isto roda um Dijkstra a partir de tudo que está queimando, onde o custo
# de entrar numa célula é uma ESTIMATIVA do tempo até ela pegar fogo, dadas as
# condições de agora (terreno, umidade, vento e relevo). Não é a simulação
# rodada adiante — é barato e aproximado de propósito, porque precisa caber
# num frame e porque um jogo que te entrega a resposta exata do futuro não tem
# decisão nenhuma.
#
# Célula que não queima recebe INF, e é exatamente por isso que a previsão
# ensina a jogar: cavar um aceiro faz o mapa de tempo ATRÁS dele saltar para
# "nunca", e você vê o seu plano funcionar antes de o fogo chegar.

const FORECAST_INF := 1e9
const COST_EPSILON := 0.01

# O fogo não chega numa célula vindo de UM vizinho — chega como frente, e uma
# célula na linha de avanço recebe calor de três ao mesmo tempo (a ortogonal e
# as duas diagonais). Sem este ganho a previsão modelava um foco solitário e
# dizia "60 segundos" onde o incêndio levava 19: um aviso que erra por três
# vezes é pior que nenhum, porque o jogador confia nele.
const FORECAST_FRONT_GAIN := 2.2

func forecast() -> PackedFloat32Array:
	var n := cols * rows
	var time := PackedFloat32Array()
	time.resize(n)
	for idx in n:
		time[idx] = FORECAST_INF

	var wind := current_wind()
	var frontier: Array = []
	for idx in n:
		if state[idx] == BURNING:
			time[idx] = 0.0
			frontier.append(idx)

	# Fila de prioridade pobre: um vetor mantido ordenado por inserção binária.
	# Com ~1.500 células e uma fronteira pequena isso é mais rápido do que
	# parece, e evita trazer uma estrutura de heap só pra este uso.
	var queue: Array = []
	for idx in frontier:
		queue.append([0.0, idx])

	while not queue.is_empty():
		var top: Array = queue.pop_front()
		var cost: float = top[0]
		var idx: int = top[1]
		# A tolerância não é frescura. `time` é float32 e os custos são
		# calculados em float64: gravar 22.123456789 e ler 22.123455 de volta
		# faz `cost > time[idx]` disparar por um milionésimo de segundo, a
		# célula é descartada como "já visitada por um caminho melhor", e o
		# Dijkstra morre depois de dois níveis. Foi o que aconteceu — a
		# previsão dizia "o fogo nunca chega" para o vale quase inteiro, o que
		# é a mentira mais perigosa que este jogo pode contar.
		if cost > time[idx] + COST_EPSILON:
			continue
		for entry in _neighbors[idx]:
			var nidx: int = entry[0]
			if state[nidx] == BURNT or fuel[nidx] <= 0.0:
				continue
			var direction: Vector2 = entry[2]
			var wind_factor: float = clampf(1.0 + WIND_GAIN * direction.dot(wind), WIND_MIN, 1.0 + WIND_GAIN)
			var push: float = Terrain.output_of(kind[idx]) * SPREAD * float(entry[1]) * wind_factor * FORECAST_FRONT_GAIN
			if push <= 0.001:
				continue
			# Tempo até acender, resolvido em vez de estimado: uma célula que
			# recebe `push` por segundo e perde COOL_RATE do que tem tende a
			# `push / COOL_RATE`, subindo como 1 - e^(-COOL_RATE·t). Se esse
			# teto não passa do limiar, o fogo NÃO chega ali — e é essa
			# distinção (e não um número grande) que faz o overlay pintar de
			# "seguro" o outro lado de um aceiro.
			var ceiling: float = push / COOL_RATE
			var threshold: float = ignition_threshold(nidx)
			if ceiling <= threshold * 1.02:
				continue
			var step: float = -log(1.0 - threshold / ceiling) / COOL_RATE
			var next_cost: float = cost + step
			if next_cost < time[nidx]:
				time[nidx] = next_cost
				_queue_insert(queue, next_cost, nidx)

	return time

func _queue_insert(queue: Array, cost: float, idx: int) -> void:
	var low := 0
	var high := queue.size()
	while low < high:
		var mid := (low + high) / 2
		if float(queue[mid][0]) < cost:
			low = mid + 1
		else:
			high = mid
	queue.insert(low, [cost, idx])
