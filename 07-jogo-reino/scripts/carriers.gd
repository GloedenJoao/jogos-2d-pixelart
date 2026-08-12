class_name Carriers
extends RefCounted

# Move o(s) carregador(es) num ciclo: escolhe o prédio com mais produção
# parada no pátio, anda até lá, pega, leva pro Armazém, entrega, decide de
# novo. Mesma técnica de avanço por posição contínua de `Workers`, mas o
# ciclo de decisão (pra onde ir, pegar, entregar) é coisa de carregador, não
# de trabalhador de posto — por isso é uma classe separada, não uma extensão
# de `Worker`/`Workers`.
#
# Escolhe sempre o pátio MAIS CHEIO, não o mais próximo nem por turno fixo:
# assim, com um carregador só servindo dois extratores, quem está prestes a
# travar por falta de espaço no pátio é atendido primeiro — o gargalo nunca
# fica escondido atrás de "não era a vez dele".

const MIN_PICKUP := 1.0   # abaixo disso não compensa a viagem

var list: Array[Carrier] = []
var _next_id := 0

func spawn(position: Vector2) -> Carrier:
	var c := Carrier.new()
	c.id = _next_id
	_next_id += 1
	c.position = position
	list.append(c)
	return c

func advance(delta: float, pathfinder: Pathfinder, buildings: Buildings) -> void:
	var warehouse := buildings.warehouse_id()
	if warehouse == -1:
		return
	for c in list:
		if c.state == Carrier.State.IDLE:
			_start_trip(c, pathfinder, buildings)
			continue
		if not _move(c, delta, pathfinder):
			continue
		if c.state == Carrier.State.TO_SOURCE:
			_pick_up(c, pathfinder, buildings, warehouse)
		else:
			_drop_off(c, buildings)

func _start_trip(c: Carrier, pathfinder: Pathfinder, buildings: Buildings) -> void:
	var best := -1
	var best_amount := 0.0
	for i in buildings.list.size():
		var amount: float = buildings.list[i].buffer
		if amount > best_amount:
			best_amount = amount
			best = i
	if best == -1 or best_amount < MIN_PICKUP:
		return   # nada que valha a viagem ainda — tenta de novo no próximo tick
	c.source_building = best
	c.state = Carrier.State.TO_SOURCE
	_send(c, _approach_point(buildings.list[best].cell, pathfinder), pathfinder)

func _pick_up(c: Carrier, pathfinder: Pathfinder, buildings: Buildings, warehouse: int) -> void:
	var building := buildings.list[c.source_building]
	var taken := buildings.collect(c.source_building, Carrier.CAPACITY)
	if taken <= 0.0:
		# alguém já esvaziou o pátio entre a decisão e a chegada — sem
		# carga, volta a decidir em vez de fingir uma entrega vazia.
		c.state = Carrier.State.IDLE
		return
	c.resource = Buildings.RESOURCE_OF[building.kind]
	c.carrying = taken
	c.state = Carrier.State.TO_WAREHOUSE
	_send(c, _approach_point(buildings.list[warehouse].cell, pathfinder), pathfinder)

func _drop_off(c: Carrier, buildings: Buildings) -> void:
	buildings.deliver(c.resource, c.carrying)
	c.carrying = 0.0
	c.resource = ""
	c.source_building = -1
	c.state = Carrier.State.IDLE

func _send(c: Carrier, target: Vector2, pathfinder: Pathfinder) -> void:
	if c.position.distance_squared_to(target) <= 9.0:
		c.position = target
		c.clear_path()
		return
	c.set_path(pathfinder.find_path(c.position, target))

# Um passo à frente da célula do prédio, nunca a célula do prédio em si —
# ela é sólida no pathfinder (ver main.gd _place_starting_buildings), e
# `Pathfinder.find_path` substitui o último ponto do caminho pelo destino
# EXATO pedido, sem checar solidez. Pedir a célula sólida diretamente faria
# o carregador terminar a viagem visualmente em cima do prédio.
func _approach_point(cell: Vector2i, pathfinder: Pathfinder) -> Vector2:
	var approach := cell + Vector2i(0, 1)
	if not _inside(approach, pathfinder) or pathfinder.is_solid(approach):
		approach = cell + Vector2i(0, -1)
	if not _inside(approach, pathfinder) or pathfinder.is_solid(approach):
		approach = pathfinder.nearest_free(cell)
	return pathfinder.center_of(approach)

func _inside(cell: Vector2i, pathfinder: Pathfinder) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < pathfinder.cols and cell.y < pathfinder.rows

# Devolve true assim que o caminho acaba de esgotar neste tick (é o sinal
# pra `advance` decidir o que fazer na chegada).
func _move(c: Carrier, delta: float, pathfinder: Pathfinder) -> bool:
	var remaining: float = Carrier.SPEED * delta
	while remaining > 0.0 and c.has_path():
		var goal: Vector2 = c.next_waypoint()
		var to_goal: Vector2 = goal - c.position
		var dist: float = to_goal.length()
		if dist <= 0.0001:
			c.path_index += 1
			continue
		if dist <= remaining:
			c.position = goal
			pathfinder.register_step(c.position)
			c.path_index += 1
			remaining -= dist
		else:
			c.position += to_goal / dist * remaining
			remaining = 0.0
	return not c.has_path()
