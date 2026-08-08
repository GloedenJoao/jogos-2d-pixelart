class_name ContainmentBot
extends RefCounted

# Um bombeiro automático. Existe pelo mesmo motivo que o `DemoBot` do Projeto 3:
# **level design precisa de regressão.** Uma fase que ficou impossível (ou
# trivial) depois de mexer numa constante do fogo é um bug que nenhum teste de
# unidade pega, porque cada peça continua correta sozinha.
#
# A estratégia é a mais simples que funciona, e de propósito: cercar de terra
# batida o que precisa ser salvo, começando pelo que o fogo alcança primeiro
# (segundo a previsão da própria FireSim), e jogar água no que já pegou.
#
# Ele NÃO é um jogador bom. Não usa contra-fogo, não lê o vento, não escolhe
# gargalo — cava anel em volta de casa, e só. É exatamente o que se quer de uma
# referência: se o bot burro passa, a fase é justa; se o bot burro passa com
# folga em TODAS as fases, o jogo está fácil demais e a suíte avisa (é o que o
# teste de folga cobra). E o que ele deixa na mesa é a margem onde um jogador
# humano tem o que fazer.
#
# De quebra, é o modo demonstração do jogo: tecla B durante a partida.

const REPLAN := 1.2               # segundos entre replanejamentos
const MAX_ACTIVE := 6             # ordens em aberto ao mesmo tempo
const RING := 1                   # anel de proteção ao redor de cada casa

# Não se manda cavar onde o fogo chega antes do brigadista. Sem este corte, o
# bot enfileirava ordens na célula mais ameaçada de todas — que é justamente a
# que vai pegar fogo primeiro —, o brigadista chegava atrasado, a ordem era
# cancelada e ele recomeçava. Metade das ordens morria assim, e o vale queimava
# enquanto a turma corria atrás do próprio rabo.
const MIN_ETA := 6.0

# Água é escassa e some com o tempo: só vale gastar preventivamente quando a
# chama está mesmo em cima (abaixo disto, cavar não termina a tempo). Com um
# limiar frouxo o bot torrava o balde todo nos primeiros vinte segundos e
# chegava seco na hora que importava — foi o que fez a fase "Brasas" regredir.
const URGENT_ETA := 4.0
const URGENT_PER_CYCLE := 2

var mission: Mission = null
var _clock := 999.0

func setup(target: Mission) -> void:
	mission = target
	_clock = 999.0

func update(delta: float) -> void:
	if mission == null or mission.phase != Mission.PLAYING:
		return
	_clock += delta
	if _clock < REPLAN:
		return
	_clock = 0.0
	_plan()

func _plan() -> void:
	var agents := mission.agents
	if agents.pending_orders() >= MAX_ACTIVE:
		return

	var sim := mission.sim
	var forecast := sim.forecast()

	# Uma casa por vez, e a mais ameaçada primeiro.
	#
	# A versão anterior juntava as células de TODAS as casas num monte só,
	# ordenava por urgência e mandava as seis mais urgentes. Parece razoável e
	# perde a fase: as seis mais urgentes ficam espalhadas por três casas, o
	# incêndio chega, e nenhum dos três cercos está fechado. Um cerco com um
	# buraco não segura nada — o fogo entra pelo buraco. Meia defesa em três
	# casas vale exatamente zero casa; defesa inteira numa vale uma.
	var houses: Array = []
	for y in sim.rows:
		for x in sim.cols:
			var idx := sim.index_of(x, y)
			if sim.kind[idx] != Terrain.HOUSE or sim.state[idx] == FireSim.BURNT:
				continue
			var ring: Array = []
			var threat := FireSim.FORECAST_INF
			for dy in range(-RING, RING + 1):
				for dx in range(-RING, RING + 1):
					if dx == 0 and dy == 0:
						continue
					var cell := Vector2i(x + dx, y + dy)
					if not sim.inside(cell.x, cell.y):
						continue
					var nidx := sim.index_of(cell.x, cell.y)
					var eta: float = forecast[nidx]
					threat = minf(threat, eta)
					if sim.state[nidx] == FireSim.BURNING:
						ring.append([-1.0, cell])                   # apagar primeiro
					elif eta >= FireSim.FORECAST_INF:
						continue                                    # já é barreira
					else:
						ring.append([eta, cell])
			if ring.is_empty():
				continue                                            # casa já cercada
			ring.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			houses.append([threat, ring])

	houses.sort_custom(func(a, b): return float(a[0]) < float(b[0]))

	var poured := 0
	for house in houses:
		if agents.pending_orders() >= MAX_ACTIVE:
			break
		for entry in house[1]:
			if agents.pending_orders() >= MAX_ACTIVE:
				break
			var eta: float = float(entry[0])
			var cell: Vector2i = entry[1]
			if eta < 0.0:                                           # está pegando fogo
				if mission.water_left > 0:
					mission.order(Tools.WATER, cell)
			elif eta >= MIN_ETA and Tools.can_target(Tools.DIG, sim, cell):
				mission.order(Tools.DIG, cell)
			elif eta <= URGENT_ETA and mission.water_left > 0 and poured < URGENT_PER_CYCLE:
				if mission.order(Tools.WATER, cell):
					poured += 1
