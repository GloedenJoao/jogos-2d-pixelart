class_name Fog
extends RefCounted

# Nevoeiro de guerra: duas grades por célula, não uma.
#
# `explored` é permanente — uma vez visto, o jogador guarda a MEMÓRIA daquele
# pedaço de mapa (relevo, se tinha floresta ali), mesmo que nada esteja
# olhando pra lá agora. `visible` é recalculada do zero a cada chamada de
# `update_visibility` — é "o que uma fonte de visão alcança NESTE instante".
#
# A distinção importa assim que existir uma fonte de visão que se move (um
# trabalhador saindo, uma construção destruída): a área que ela deixou de
# cobrir tem que escurecer (sair de `visible`) sem apagar o que já foi
# aprendido sobre o terreno (continuar em `explored`). Sem separar os dois
# estados, "esqueci o que vi" e "nunca vi" ficariam indistinguíveis.

var cols := 0
var rows := 0

var explored := PackedByteArray()
var visible := PackedByteArray()

func setup(map_cols: int, map_rows: int) -> void:
	cols = map_cols
	rows = map_rows
	var n := cols * rows
	explored = PackedByteArray()
	explored.resize(n)
	visible = PackedByteArray()
	visible.resize(n)

func index_of(x: int, y: int) -> int:
	return y * cols + x

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows

# `sources` é um Array de Vector3(x, y, raio). Recalcula `visible` inteiro a
# partir de zero (uma fonte que sumiu não deixa resto) e funde o resultado em
# `explored`, que só cresce.
func update_visibility(sources: Array) -> void:
	visible.fill(0)
	for source in sources:
		var cx: int = int(source.x)
		var cy: int = int(source.y)
		var radius: float = source.z
		reveal(cx, cy, radius)

# Revela um círculo (distância euclidiana, não losango nem quadrado — um raio
# 5 tem que parecer redondo, senão a fronteira do que se vê entrega a forma
# da grade em vez da forma da visão).
func reveal(cx: int, cy: int, radius: float) -> void:
	var r := int(ceil(radius))
	var r2 := radius * radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dy * dy) > r2:
				continue
			var x := cx + dx
			var y := cy + dy
			if not inside(x, y):
				continue
			var idx := index_of(x, y)
			visible[idx] = 1
			explored[idx] = 1

func is_explored(x: int, y: int) -> bool:
	return explored[index_of(x, y)] == 1 if inside(x, y) else false

func is_visible(x: int, y: int) -> bool:
	return visible[index_of(x, y)] == 1 if inside(x, y) else false

func explored_count() -> int:
	var total := 0
	for v in explored:
		total += v
	return total
