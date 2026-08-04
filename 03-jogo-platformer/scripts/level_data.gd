class_name LevelData
extends RefCounted

# Uma fase é escrita como mapa ASCII (ver scripts/levels.gd) e traduzida aqui pra
# dados: sólidos, spawn, saída, gemas, espinhos, checkpoints e inimigos.
# Manter o mapa em texto deixa a fase fácil de editar e de testar sem abrir o editor.

const SOLID := "#"
const EMPTY := "."
const SPAWN := "P"
const EXIT := "E"
const GEM := "G"
const SPIKE := "^"
const CHECKPOINT := "F"
const ENEMY := "M"

var width: int = 0
var height: int = 0
var solids: Dictionary = {} # Vector2i -> true
var spawn: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO
var gems: Array[Vector2i] = []
var spikes: Array[Vector2i] = []
var checkpoints: Array[Vector2i] = []
var enemies: Array[Vector2i] = []

static func parse(rows: Array) -> LevelData:
	var data := LevelData.new()
	data.height = rows.size()
	for y in rows.size():
		var row: String = rows[y]
		data.width = maxi(data.width, row.length())
		for x in row.length():
			var cell := Vector2i(x, y)
			match row[x]:
				SOLID:
					data.solids[cell] = true
				SPAWN:
					data.spawn = cell
				EXIT:
					data.exit_cell = cell
				GEM:
					data.gems.append(cell)
				SPIKE:
					data.spikes.append(cell)
				CHECKPOINT:
					data.checkpoints.append(cell)
				ENEMY:
					data.enemies.append(cell)
	return data

func is_solid(cell: Vector2i) -> bool:
	return solids.has(cell)

func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height

# Colunas onde não existe chão nenhum (buracos): usado pelos testes e pela IA de
# demonstração pra saber onde precisa pular.
func gap_columns() -> Array[int]:
	var out: Array[int] = []
	for x in width:
		var has_floor := false
		for y in height:
			if is_solid(Vector2i(x, y)):
				has_floor = true
				break
		if not has_floor:
			out.append(x)
	return out
