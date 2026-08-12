class_name Buildings
extends RefCounted

# Prédios extratores da Fase 2, mais o Armazém e o pátio local da Fase 3.
#
# Cada extrator senta EM CIMA de uma célula de depósito do MapGen e puxa
# dali — não tem estoque próprio de MATÉRIA-PRIMA, isso é o `MapGen.deposit`
# (cavar demais já é a mesma pressão de recurso finito que a Fase 1
# desenhou). Mas a partir da Fase 3 a produção não vira estoque JOGÁVEL na
# hora: ela se acumula no PÁTIO do prédio (`Building.buffer`, com teto —
# `EXTRACTOR_BUFFER_CAP`) até um `Carrier` vir buscar e levar pro Armazém.
# `stock` agora é só o que já chegou lá, não o que já foi extraído — é essa
# distinção que dá ao transporte um motivo de existir em vez de ser
# decoração: um extrator com o pátio cheio PARA de extrair (nem desperdiça
# nem empilha infinito) até alguém vir buscar.
#
# Um prédio só produz com trabalhador de verdade PRESENTE e trabalhando
# (`Worker.State.WORKING`), não só "alocado" — só ter o `job_building`
# marcado significa "a caminho", e o trajeto custa tempo de produção de
# propósito (é o que o plano do projeto chama de "prédio longe do núcleo
# populacional custa tempo de trajeto"). Staffing é ligado/desligado, um
# trabalhador por prédio — o mecanismo de fração de vaga ocupada da Colônia
# (`staffing_ratios()`) só compensaria com múltiplas vagas por prédio.
#
# Fase 4 acrescenta PROCESSAMENTO (Serraria, Oficina de Pedra): consomem um
# recurso bruto do Armazém e devolvem processado, na mesma proporção 1:1.
# Diferença deliberada de arquitetura em relação ao extrator: processamento
# lê e escreve direto em `stock` (não tem pátio próprio nem depende de
# `Carrier`). O insumo JÁ passou pelo carregador pra virar estoque jogável —
# reexigir uma segunda perna de transporte só pra levar o resultado de volta
# pro mesmo Armazém não ensinaria nada de novo sobre logística, só repetiria
# a Fase 3 com nomes diferentes. Fica registrado como simplificação
# consciente, não descuido — se um dia o processamento sair do Armazém (uma
# oficina longe da vila, por exemplo), este é o lugar a revisitar.

enum Kind { LUMBERJACK, QUARRY, WAREHOUSE, SAWMILL, STONE_WORKSHOP }

const RESOURCE_OF := {
	Kind.LUMBERJACK: "madeira",
	Kind.QUARRY: "pedra",
}
const DEPOSIT_KIND_OF := {
	Kind.LUMBERJACK: MapGen.Kind.FOREST,
	Kind.QUARRY: MapGen.Kind.STONE,
}
# Unidades por segundo, trabalhador presente. Mesma ordem de grandeza do
# depósito máximo (map_gen.gd: 40-70) — um bosque sustenta minutos de corte
# contínuo, não segundos nem horas.
const PRODUCTION_PER_SECOND := {
	Kind.LUMBERJACK: 1.0,
	Kind.QUARRY: 0.8,
}
# Quanto cabe no pátio antes de precisar de um carregador. Baixo o bastante
# pra um único carregador conseguir dar conta de dois extratores sem deixar
# nenhum parado por muito tempo; alto o bastante pra não esvaziar o pátio
# num só ciclo de coleta (senão o carregador vira o gargalo o tempo todo).
const EXTRACTOR_BUFFER_CAP := 15.0

# Receita de processamento: `rate` unidades/segundo de `input` viram a MESMA
# quantidade de `output` (1:1 — sem perda nem multiplicação; balancear a
# proporção fica pra quando houver custo/receita de verdade pra comparar
# contra). Mais lento que a extração de propósito: processar é a etapa que
# "gasta tempo" da cadeia, senão nunca vale mais ter tábua do que madeira
# crua.
const PROCESS_RECIPES := {
	Kind.SAWMILL: {"input": "madeira", "output": "tábua", "rate": 0.6},
	Kind.STONE_WORKSHOP: {"input": "pedra", "output": "bloco", "rate": 0.5},
}

class Building:
	var kind: int
	var cell: Vector2i
	var worker_id := -1   # -1 = sem ninguém alocado
	var buffer := 0.0     # produção acumulada no pátio, esperando um carregador

	func _init(k: int, c: Vector2i) -> void:
		kind = k
		cell = c

var list: Array[Building] = []
var stock: Dictionary = {"madeira": 0.0, "pedra": 0.0, "tábua": 0.0, "bloco": 0.0}

func place(kind: int, cell: Vector2i) -> int:
	list.append(Building.new(kind, cell))
	return list.size() - 1

func assign(building_id: int, worker: Worker) -> void:
	list[building_id].worker_id = worker.id
	worker.job_building = building_id

func warehouse_id() -> int:
	for i in list.size():
		if list[i].kind == Kind.WAREHOUSE:
			return i
	return -1

# Só extrai/processa pra quem está de fato WORKING agora — ver o comentário
# no topo do arquivo sobre por que "alocado" não basta.
func advance(delta: float, map: MapGen, workers: Workers) -> void:
	for building in list:
		var is_extractor: bool = RESOURCE_OF.has(building.kind)
		var is_processor: bool = PROCESS_RECIPES.has(building.kind)
		if (not is_extractor and not is_processor) or building.worker_id == -1:
			continue
		var w := _worker_by_id(workers, building.worker_id)
		if w == null or w.state != Worker.State.WORKING:
			continue
		if is_extractor:
			_advance_extractor(building, delta, map)
		else:
			_advance_processor(building, delta)

# O teto do pátio (`EXTRACTOR_BUFFER_CAP`) throttla a extração: sem espaço no
# pátio, o trabalhador continua WORKING mas nada sai do depósito — não é
# desperdiçado, só espera.
func _advance_extractor(building: Building, delta: float, map: MapGen) -> void:
	var room: float = EXTRACTOR_BUFFER_CAP - building.buffer
	if room <= 0.0:
		return
	var rate: float = PRODUCTION_PER_SECOND[building.kind]
	var extracted: float = map.extract(building.cell.x, building.cell.y, minf(rate * delta, room))
	building.buffer += extracted

# Throttlado pelo estoque de insumo disponível — sem madeira no Armazém, a
# Serraria fica com o trabalhador WORKING mas não produz tábua nenhuma. Não é
# um caso especial: é a mesma lógica "só rende o que existe" do extrator
# (lá o limite é o pátio; aqui é o estoque bruto).
func _advance_processor(building: Building, delta: float) -> void:
	var recipe: Dictionary = PROCESS_RECIPES[building.kind]
	var input: String = recipe["input"]
	var output: String = recipe["output"]
	var rate: float = recipe["rate"]
	var available: float = stock.get(input, 0.0)
	var used: float = minf(rate * delta, available)
	if used <= 0.0:
		return
	stock[input] = available - used
	stock[output] = stock.get(output, 0.0) + used

# Um carregador tirando do pátio de um prédio — nunca mais do que existe lá.
func collect(building_id: int, amount: float) -> float:
	var building := list[building_id]
	var taken: float = minf(amount, building.buffer)
	building.buffer -= taken
	return taken

# Um carregador descarregando no Armazém: isto é o que vira estoque
# jogável de verdade.
func deliver(resource: String, amount: float) -> void:
	if amount <= 0.0:
		return
	stock[resource] = stock.get(resource, 0.0) + amount

func _worker_by_id(workers: Workers, worker_id: int) -> Worker:
	for w in workers.list:
		if w.id == worker_id:
			return w
	return null

# Busca em anéis crescentes a célula de depósito mais próxima do tipo certo
# pro prédio (madeira precisa de FOREST, pedra precisa de STONE). Devolve
# Vector2i(-1,-1) se não achar nada dentro do raio — mapa gerado sem aquele
# recurso perto da vila é possível (semente ruim), e quem chama decide o que
# fazer (não constrói aquele prédio desta vez).
static func nearest_deposit_cell(map: MapGen, deposit_kind: int, from: Vector2i, max_radius: int) -> Vector2i:
	if map.kind_at(from.x, from.y) == deposit_kind:
		return from
	for radius in range(1, max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var probe := from + Vector2i(dx, dy)
				if map.inside(probe.x, probe.y) and map.kind_at(probe.x, probe.y) == deposit_kind:
					return probe
	return Vector2i(-1, -1)
