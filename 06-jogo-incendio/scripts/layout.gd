class_name Layout
extends RefCounted

# A geometria da tela, num lugar só — mesma disciplina do Projeto 5: se a cena
# tivesse a própria tabela de posições e a simulação outra, dava pra um
# brigadista "cavar" três células ao lado de onde o jogador clicou sem nenhum
# teste falhar.
#
# ---- por que esta tela não parece com a dos jogos anteriores ----
#
# O Projeto 5 pôs o HUD numa tira no topo porque o que importava lá eram
# pessoas andando pelo chão, e qualquer coisa flutuando embaixo escondia gente.
# Aqui o que importa é uma FRENTE que avança pelo mapa: o jogador precisa de
# ferramentas sempre à mão e de uma leitura do vale inteiro mesmo enquanto olha
# um canto dele. Daí:
#
#   * **Barra vertical à esquerda.** Ferramenta é escolha constante, não menu.
#     Vertical porque sobra altura e falta largura: o vale é deitado.
#   * **Minimapa.** O mapa é maior que a tela de propósito (o incêndio precisa
#     de espaço pra ter forma), e um jogo em que você precisa passear a câmera
#     pra descobrir que perdeu uma casa seria um jogo sobre panorâmica.
#   * **Bússola grande.** O vento é a informação mais cara do jogo. Num canto
#     discreto, ninguém olha; e quem não olha o vento não entende por que
#     perdeu.

const TILE := 16
const SCALE := 2
const CELL := TILE * SCALE          # 32 px por célula do vale

# Barra de ferramentas: coluna à esquerda, ocupando a altura toda.
const BAR_WIDTH := 188
# Faixa de status no topo da área de mundo: bússola, objetivo, relógio.
const TOP_HEIGHT := 76

const VIEWPORT := Vector2(1280, 720)

static func world_origin() -> Vector2:
	return Vector2(BAR_WIDTH, TOP_HEIGHT)

# Área visível do vale, em pixels de tela.
static func viewport_rect() -> Rect2:
	return Rect2(world_origin(), VIEWPORT - Vector2(BAR_WIDTH, TOP_HEIGHT))

static func world_size(cols: int, rows: int) -> Vector2:
	return Vector2(cols, rows) * CELL

static func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL

static func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

static func cell_of(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / CELL), floori(world_position.y / CELL))

# Quanto a câmera pode andar sem mostrar o lado de fora do vale. Mapa menor que
# a área visível trava no zero (e a cena centraliza), senão o vale "escorrega"
# quando o jogador arrasta.
static func camera_limit(cols: int, rows: int) -> Vector2:
	var visible := viewport_rect().size
	var total := world_size(cols, rows)
	return Vector2(maxf(0.0, total.x - visible.x), maxf(0.0, total.y - visible.y))

# ---- minimapa ----
#
# Fica no pé da barra de ferramentas. Escala inteira sempre que couber: pixel
# art reduzida por fator quebrado vira papa, e o minimapa é justamente onde
# cada célula precisa ser um quadradinho nítido.

const MINIMAP_MARGIN := 12
const MINIMAP_MAX := Vector2(BAR_WIDTH - 24, 190)

static func minimap_scale(cols: int, rows: int) -> int:
	var fit := MINIMAP_MAX / Vector2(cols, rows)
	return maxi(2, int(floor(minf(fit.x, fit.y))))

static func minimap_size(cols: int, rows: int) -> Vector2:
	return Vector2(cols, rows) * float(minimap_scale(cols, rows))

static func minimap_origin(cols: int, rows: int) -> Vector2:
	var size := minimap_size(cols, rows)
	return Vector2(
		(BAR_WIDTH - size.x) * 0.5,
		VIEWPORT.y - MINIMAP_MARGIN - size.y
	)
