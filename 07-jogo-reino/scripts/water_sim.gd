class_name WaterSim
extends RefCounted

# O autômato de água: a mecânica que o plano do Projeto 7 pede explicitamente
# ("precisa ser possível abrir rios") e que nenhum sistema anterior deste
# repositório cobre — o incêndio (Projeto 6, `fire_sim.gd`) propaga calor entre
# vizinhos, mas nunca precisa CONSERVAR nada; água precisa, senão cavar um
# canal criaria ou destruiria volume do nada e a "engenharia de terreno" que o
# jogo promete vira decoração.
#
# ---- o modelo ----
#
# Cada célula tem uma ALTURA de terreno (fixa, só muda quando o jogador cava)
# e um VOLUME de água por cima dela. A "superfície" da água é altura + volume,
# e é essa superfície que se equaliza entre vizinhos — exatamente como água de
# verdade em vasos comunicantes: duas células só param de trocar água quando as
# superfícies empatam, não quando os volumes empatam.
#
# ---- por que edge-based e com buffer duplo ----
#
# Cada aresta (par de vizinhos ortogonais) é processada UMA vez por tick e o
# fluxo decidido ali é escrito num buffer, não direto em `water` — se fosse
# direto, a ordem de varredura da grade viraria viés físico (água preferindo
# fluir para a direita/baixo porque a célula vizinha já foi atualizada nesta
# mesma passada), o mesmo bug que o comentário de fire_sim.gd documenta. Só
# depois que todas as arestas decidiram seu fluxo é que tudo é aplicado de
# uma vez, o que também é o que garante conservação: toda unidade que sai de
# uma célula está anotada para entrar exatamente em outra.
#
# ---- represa e comporta ----
#
# Uma célula "bloqueada" nunca guarda água e nunca repassa fluxo — é uma
# parede. Comporta é a mesma coisa com um estado que o jogador alterna
# (`set_blocked`), então dá pra represar e depois abrir para deixar a água
# passar de novo, sem precisar de um sistema separado.
#
# ---- cavar canal ----
#
# Não existe função "cavar" aqui: cavar É `set_height` baixando o valor de uma
# célula. A física não precisa saber que houve escavação — ela só responde à
# nova diferença de altura no próximo tick, do mesmo jeito que responde a
# qualquer relevo natural do mapa.

const TICK := 0.1                # passo fixo da simulação, em segundos

# --- constantes calibradas (ver tests/calibrate.gd) ---
# FLOW_RATE é a fração da diferença de superfície que efetivamente atravessa a
# aresta em cada tick (o resto fica pra equalizar nos ticks seguintes). Baixo
# demais e "abrir um canal" não parece fazer nada por segundos; alto demais e
# a água pula de um lado pro outro em vez de escoar (chega a oscilar, porque a
# metade que sobra pode inverter quem está mais alto). 0.5 é o teto teórico
# seguro de uma única troca sem overshoot (ver `_tick`); calibrate.gd mede o
# tempo de acomodação resultante e é isso, não o número em si, que valida a
# escolha.
const FLOW_RATE := 0.5
# Abaixo disto o fluxo pára: sem este piso, diferenças de superfície na casa
# de 1e-6 continuariam "fluindo" para sempre (nunca zeram de verdade em ponto
# flutuante), o que impediria qualquer teste de "a água parou de se mexer".
const MIN_FLOW := 0.001
# Abaixo disto uma célula é tratada como seca pra fins de iteração (pular
# células sem água nem vizinho com água economiza a maior parte da grade em
# mapas onde a água ainda não chegou).
const MIN_WATER := 0.0005

var cols := 0
var rows := 0

var height := PackedFloat32Array()   # altura do terreno, fixa até o jogador cavar
var water := PackedFloat32Array()    # volume de água sobre a célula
var blocked := PackedByteArray()     # represa/comporta fechada: parede pra água

var elapsed := 0.0
var ticks := 0

var _accumulator := 0.0
var _edges: Array = []               # [idx_a, idx_b] únicos, uma vez por par

# ---- montagem ----

func setup(map_cols: int, map_rows: int, heights: PackedFloat32Array) -> void:
	cols = map_cols
	rows = map_rows
	var n := cols * rows

	height = heights.duplicate()
	water = PackedFloat32Array()
	water.resize(n)
	blocked = PackedByteArray()
	blocked.resize(n)

	_build_edges()
	elapsed = 0.0
	ticks = 0
	_accumulator = 0.0

# Só as arestas para a direita e para baixo: isso cobre cada par de vizinhos
# ortogonais exatamente uma vez (a aresta esquerda de B é a aresta direita de
# A), sem precisar de um Set para deduplicar.
func _build_edges() -> void:
	_edges.clear()
	for y in rows:
		for x in cols:
			var idx := index_of(x, y)
			if x + 1 < cols:
				_edges.append(PackedInt32Array([idx, index_of(x + 1, y)]))
			if y + 1 < rows:
				_edges.append(PackedInt32Array([idx, index_of(x, y + 1)]))

func index_of(x: int, y: int) -> int:
	return y * cols + x

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows

# ---- o passo ----

func advance(delta: float) -> int:
	_accumulator += delta
	var count := 0
	while _accumulator >= TICK and count < 12:
		_accumulator -= TICK
		_tick()
		count += 1
	return count

func _tick() -> void:
	var n := cols * rows
	var net := PackedFloat32Array()
	net.resize(n)

	for edge in _edges:
		var a: int = edge[0]
		var b: int = edge[1]
		if blocked[a] or blocked[b]:
			continue
		var surface_a: float = height[a] + water[a]
		var surface_b: float = height[b] + water[b]
		var diff: float = surface_a - surface_b
		if absf(diff) < MIN_FLOW:
			continue
		# Metade da diferença é o teto que NÃO estoura a igualdade num só
		# tick (mover mais do que isso faria quem mandava mais virar quem
		# manda menos, e o próximo tick devolveria o fluxo — oscilação sem
		# fim). FLOW_RATE morde uma fração desse teto, então mesmo no valor
		# máximo (0.5) o resultado é "chegam exatamente à igualdade", nunca
		# ultrapassam.
		var cap: float = diff * 0.5
		var flow: float = cap * FLOW_RATE
		if diff > 0.0:
			flow = minf(flow, water[a])
		else:
			flow = maxf(flow, -water[b])
		net[a] -= flow
		net[b] += flow

	for idx in n:
		if net[idx] == 0.0:
			continue
		water[idx] = maxf(0.0, water[idx] + net[idx])

	elapsed += TICK
	ticks += 1

# ---- interferência do jogador ----

func add_water(x: int, y: int, amount: float) -> void:
	if not inside(x, y) or amount <= 0.0:
		return
	var idx := index_of(x, y)
	if blocked[idx]:
		return
	water[idx] += amount

# Cavar canal: baixa o terreno. Não mexe na água que já está ali — se a célula
# ficar mais funda que a superfície ao redor, o próprio `_tick` puxa água pra
# ela no passo seguinte, sem precisar de um caso especial aqui.
func set_height(x: int, y: int, new_height: float) -> void:
	if not inside(x, y):
		return
	height[index_of(x, y)] = new_height

func set_blocked(x: int, y: int, is_blocked: bool) -> void:
	if not inside(x, y):
		return
	var idx := index_of(x, y)
	blocked[idx] = 1 if is_blocked else 0
	if is_blocked:
		water[idx] = 0.0

# ---- leitura do estado ----

func water_at(x: int, y: int) -> float:
	return water[index_of(x, y)] if inside(x, y) else 0.0

func height_at(x: int, y: int) -> float:
	return height[index_of(x, y)] if inside(x, y) else 0.0

func surface_at(x: int, y: int) -> float:
	if not inside(x, y):
		return 0.0
	var idx := index_of(x, y)
	return height[idx] + water[idx]

func is_blocked(x: int, y: int) -> bool:
	return blocked[index_of(x, y)] == 1 if inside(x, y) else true

func total_water() -> float:
	var total := 0.0
	for v in water:
		total += v
	return total

# Maior diferença de superfície entre vizinhos que ainda têm água dos dois
# lados — usado pelos testes/calibração pra saber quando uma bacia "acomodou".
func max_surface_gap() -> float:
	var worst := 0.0
	for edge in _edges:
		var a: int = edge[0]
		var b: int = edge[1]
		if blocked[a] or blocked[b]:
			continue
		if water[a] <= MIN_WATER and water[b] <= MIN_WATER:
			continue
		var gap: float = absf((height[a] + water[a]) - (height[b] + water[b]))
		worst = maxf(worst, gap)
	return worst
