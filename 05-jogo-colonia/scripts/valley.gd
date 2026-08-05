class_name Valley
extends RefCounted

# A geometria do vale, num lugar só. A cena usa isto pra DESENHAR (chão, lotes,
# praça) e a Population usa pra DECIDIR pra onde os moradores andam — se cada um
# tivesse a própria tabela de posições, dava pra um morador "trabalhar" a três
# tiles da construção dele sem nenhum teste falhar.
#
# Coordenadas em pixels são relativas ao nó do mundo (que fica logo abaixo da
# tira de HUD), não à tela.

const TILE := 16
const SCALE := 3
const CELL := TILE * SCALE      # 48 px por célula
const COLS := 27
const ROWS := 13

# Última fileira que recebe decoração (a de baixo fica de respiro).
const DECOR_MAX_ROW := 11

# A praça central: onde todo mundo come, descansa e se junta sem ter o que fazer.
const PLAZA_RECT := Rect2i(10, 4, 6, 4)

# Um lote por TIPO de construção, na mesma ordem de Buildings.ALL. Dispostos em
# anel ao redor da praça: o miolo fica livre pros moradores, e nenhum lote cai
# atrás da gaveta de construções (que só existe enquanto está aberta).
#
# A ORDEM salta de um canto pro outro de propósito. Buildings.ALL vem agrupado
# por era, então uma lista em ordem de leitura colocaria as seis primeiras
# construções (eras 0 e 1) todas na fileira de cima e deixaria dois terços do
# vale vazios durante metade da partida.
const PLOT_CELLS := [
	Vector2i(2, 1), Vector2i(2, 8), Vector2i(9, 8),       # era 0: noroeste, oeste, sul
	Vector2i(22, 1), Vector2i(23, 8), Vector2i(17, 8),    # era 1: nordeste, leste, sudeste
	Vector2i(6, 1), Vector2i(2, 5), Vector2i(5, 8),       # era 2
	Vector2i(18, 1), Vector2i(23, 5), Vector2i(20, 8),    # era 3
	Vector2i(10, 1), Vector2i(14, 1), Vector2i(13, 8),    # era 4
]

static func plaza_center() -> Vector2:
	return (Vector2(PLAZA_RECT.position) + Vector2(PLAZA_RECT.size) * 0.5) * CELL

# Célula (canto superior esquerdo) do lote 2×2 de uma construção.
static func plot_cell(building_id: String) -> Vector2i:
	for i in Buildings.ALL.size():
		if Buildings.ALL[i].id == building_id:
			return PLOT_CELLS[i]
	return Vector2i.ZERO

static func plot_origin(building_id: String) -> Vector2:
	return Vector2(plot_cell(building_id)) * CELL

# Onde a turma que trabalha nessa construção se posiciona: um pouco ABAIXO do
# lote, senão os sprites de 48px cobrem a casa em vez de ficar na frente dela.
static func worker_spot(building_id: String) -> Vector2:
	return plot_origin(building_id) + Vector2(CELL, CELL * 2 + 44)

# Lugar de cada trabalhador dentro da turma. Deslocamento por SLOT (a posição
# da pessoa na lista de contratados), não aleatório: assim uma construção com
# 8 vagas mostra 8 pessoas enfileiradas na porta em vez de um amontoado de
# sprites no mesmo pixel, e dá pra bater o olho e contar quem está lá.
# Turma larga e rasa (7 por fileira, no máximo 4 fileiras): uma construção com
# 24 vagas vira uma faixa de gente na frente da porta, não uma coluna que desce
# até sair da tela. Passando de 28 pessoas no mesmo posto, as fileiras
# REEMPILHAM deslocadas alguns pixels — vira multidão densa, que é a leitura
# certa pra "essa fábrica emprega meia colônia", e continua cabendo na tela.
const CREW_PER_ROW := 7
const CREW_MAX_ROWS := 4
const CREW_STEP_X := 25.0
const CREW_STEP_Y := 16.0

static func work_slot_offset(slot: int) -> Vector2:
	if slot < 0:
		return Vector2.ZERO
	var col: int = slot % CREW_PER_ROW
	var band: int = slot / CREW_PER_ROW
	var row: int = band % CREW_MAX_ROWS
	var wrap: int = band / CREW_MAX_ROWS
	var jitter_x: float = float((wrap * 13) % 21) - 10.0
	var jitter_y: float = float((wrap * 7) % 9)
	return Vector2(
		(col - (CREW_PER_ROW - 1) * 0.5) * CREW_STEP_X + jitter_x,
		row * CREW_STEP_Y + jitter_y
	)

# Meia largura ocupada por uma turma cheia, pro teste de "cabe na tela".
static func crew_half_width() -> float:
	return (CREW_PER_ROW - 1) * 0.5 * CREW_STEP_X + 10.0

static func crew_depth() -> float:
	return (CREW_MAX_ROWS - 1) * CREW_STEP_Y + 8.0

# Ponto qualquer dentro da praça, pra quem está comendo, descansando ou só
# passeando — a praça é grande, então tem espaço pra todo mundo sem pilha.
static func plaza_spot(rng: RandomNumberGenerator) -> Vector2:
	var half := Vector2(PLAZA_RECT.size) * CELL * 0.42
	return plaza_center() + Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
