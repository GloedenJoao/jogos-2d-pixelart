class_name Workers
extends RefCounted

# Move os trabalhadores ao longo do caminho que o Pathfinder devolveu.
# Avanço por posição contínua (não célula a célula) — mesma técnica de
# `Population._move_all` na Colônia V2: o caminho é uma polilinha em pixels,
# o trabalhador desliza linearmente entre os pontos, e pode consumir vários
# pontos no mesmo frame se `speed * delta` for maior que a distância entre
# eles (senão frame lento = trabalhador lento).

var list: Array[Worker] = []
var _next_id := 0

func spawn(position: Vector2) -> Worker:
	var w := Worker.new()
	w.id = _next_id
	_next_id += 1
	w.position = position
	list.append(w)
	return w

# Manda um trabalhador andar até `target`. `job_building` já deve estar
# marcado em `w` antes de chamar isto (é `Buildings.assign` quem decide isso)
# — é só o que faz o trabalhador virar WORKING em vez de IDLE ao chegar.
func send_to(w: Worker, target: Vector2, pathfinder: Pathfinder) -> void:
	if w.position.distance_squared_to(target) <= 9.0:
		w.position = target
		w.state = Worker.State.WORKING if w.job_building != -1 else Worker.State.IDLE
		return
	w.set_path(pathfinder.find_path(w.position, target))

func advance(delta: float, pathfinder: Pathfinder) -> void:
	for w in list:
		if w.state != Worker.State.WALKING:
			continue
		var remaining: float = Worker.SPEED * delta
		while remaining > 0.0 and w.has_path():
			var goal: Vector2 = w.next_waypoint()
			var to_goal: Vector2 = goal - w.position
			var dist: float = to_goal.length()
			if dist <= 0.0001:
				w.path_index += 1
				continue
			if dist <= remaining:
				w.position = goal
				pathfinder.register_step(w.position)
				w.path_index += 1
				remaining -= dist
			else:
				w.position += to_goal / dist * remaining
				remaining = 0.0
		if not w.has_path():
			w.clear_path()
			w.state = Worker.State.WORKING if w.job_building != -1 else Worker.State.IDLE
