class_name Buildings
extends RefCounted

# Prédios extratores da Fase 2: cada um senta EM CIMA de uma célula de
# depósito do MapGen e puxa dali, não tem estoque próprio de matéria-prima —
# o "estoque" é o próprio `MapGen.deposit`. Isso é proposital: cavar demais
# aqui já é a mesma pressão de recurso finito que a Fase 1 desenhou, sem
# precisar duplicar contabilidade em dois lugares.
#
# Um prédio só produz com trabalhador de verdade PRESENTE e trabalhando
# (`Worker.State.WORKING`), não só "alocado" — só ter o `job_building`
# marcado significa "a caminho", e o trajeto custa tempo de produção de
# propósito (é o que o plano do projeto chama de "prédio longe do núcleo
# populacional custa tempo de trajeto"). Com um trabalhador só (Fase 2), não
# existe fração de vaga ocupada como em `Population.staffing_ratios()` da
# Colônia — é ligado ou desligado, então não precisa desse mecanismo ainda.

enum Kind { LUMBERJACK, QUARRY }

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

class Building:
	var kind: int
	var cell: Vector2i
	var worker_id := -1   # -1 = sem ninguém alocado

	func _init(k: int, c: Vector2i) -> void:
		kind = k
		cell = c

var list: Array[Building] = []
var stock: Dictionary = {"madeira": 0.0, "pedra": 0.0}

func place(kind: int, cell: Vector2i) -> int:
	list.append(Building.new(kind, cell))
	return list.size() - 1

func assign(building_id: int, worker: Worker) -> void:
	list[building_id].worker_id = worker.id
	worker.job_building = building_id

# Só extrai (e só rende madeira/pedra) pra quem está de fato WORKING agora —
# ver o comentário no topo do arquivo sobre por que "alocado" não basta.
func advance(delta: float, map: MapGen, workers: Workers) -> void:
	for building in list:
		if building.worker_id == -1:
			continue
		var w := _worker_by_id(workers, building.worker_id)
		if w == null or w.state != Worker.State.WORKING:
			continue
		var resource: String = RESOURCE_OF[building.kind]
		var rate: float = PRODUCTION_PER_SECOND[building.kind]
		var extracted: float = map.extract(building.cell.x, building.cell.y, rate * delta)
		stock[resource] = stock.get(resource, 0.0) + extracted

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
