class_name MapGen
extends RefCounted

# O mapa físico da Fase 1: relevo (alimenta o `WaterSim` da Fase 0 sem
# nenhuma adaptação — a mesma altura que decide pra onde a água escoa decide
# onde nascem as colinas de minério) e depósitos de recursos finitos no chão.
#
# Sem dependência de cena, mesmo padrão de `water_sim.gd`: dá pra gerar e
# testar o mapa inteiro headless, e só depois a cena decide como desenhar
# cada `Kind`.
#
# ---- por que dois ruídos, não um ----
#
# Um ruído só faz floresta, pedra e colina nascerem colados ao relevo (grama
# baixa, floresta na encosta, pedra mais alta, sempre nessa ordem) — mapa
# previsível demais pra valer a pena explorar. Um segundo ruído independente
# ("cobertura") decide ONDE cresce floresta/afloramento de pedra dentro da
# faixa de altura que já permite aquele tipo, então dois mapas com o mesmo
# relevo geral têm depósitos em lugares diferentes.

enum Kind { GRASS, FOREST, STONE, HILLS }

const HEIGHT_SCALE := 6.0        # mesma ordem de grandeza usada nos testes do WaterSim

# Colina (minério) é a faixa mais alta do relevo — motiva "os melhores veios
# ficam longe", consistente com o plano (docs/plano-projeto7-reino.md).
const HILLS_HEIGHT := 3.8
# Floresta não nasce no ponto mais baixo nem no mais alto: baixo demais e
# "bosque na beira do rio" vira a norma (bom demais); alto demais e compete
# com colina pelo mesmo terreno.
const FOREST_MIN_HEIGHT := 0.8
const FOREST_MAX_HEIGHT := 3.8
# Limiares medidos, não chutados (ver tests/run_tests.gd _test_coverage_is_reasonable
# e o histograma de altura/cobertura usado pra calibrar isto): a soma de
# ruídos fractais concentra a altura perto da média (a maioria das células
# cai entre 2 e 4 de 0–6), e o ruído de cobertura é aproximadamente uniforme
# em [0,1]. Um limiar de cobertura baixo (perto de 0,5) combinado com uma
# faixa de altura larga faz quase todo o mapa virar depósito; a primeira
# tentativa (0,30/0,62) deu mapas com 90%+ de floresta.
const FOREST_COVER_THRESHOLD := 0.60
# Afloramento de pedra é mais raro que floresta — pedra é insumo de
# infraestrutura, não deveria ser o recurso mais comum do mapa.
const STONE_COVER_THRESHOLD := 0.68

const FOREST_DEPOSIT_MAX := 40.0
const STONE_DEPOSIT_MAX := 70.0
const HILLS_DEPOSIT_MAX := 70.0
# Bem devagar: um lenhador plantado ao lado de uma floresta não pode viver de
# regeneração sozinha, senão "madeira acaba" deixa de ser uma pressão real do
# jogo. Isto é só o suficiente pra recompensar NÃO raspar um bosque até zero.
const FOREST_REGEN_PER_SECOND := 0.08

var cols := 0
var rows := 0

var kind := PackedInt32Array()
var height := PackedFloat32Array()
var deposit := PackedFloat32Array()   # quanto resta no depósito; 0 fora de depósito

# ---- geração ----

func generate(map_cols: int, map_rows: int, seed_value: int) -> void:
	cols = map_cols
	rows = map_rows
	var n := cols * rows

	var elevation := FastNoiseLite.new()
	elevation.seed = seed_value
	elevation.frequency = 0.035
	elevation.fractal_octaves = 4

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 1
	detail.frequency = 0.12

	var forest_cover := FastNoiseLite.new()
	forest_cover.seed = seed_value + 2
	forest_cover.frequency = 0.08

	var stone_cover := FastNoiseLite.new()
	stone_cover.seed = seed_value + 3
	stone_cover.frequency = 0.10

	kind = PackedInt32Array()
	kind.resize(n)
	height = PackedFloat32Array()
	height.resize(n)
	deposit = PackedFloat32Array()
	deposit.resize(n)

	for y in rows:
		for x in cols:
			var idx := index_of(x, y)
			var raw: float = elevation.get_noise_2d(x, y) * 0.8 + detail.get_noise_2d(x, y) * 0.2
			var h: float = (raw + 1.0) * 0.5 * HEIGHT_SCALE
			height[idx] = h

			if h >= HILLS_HEIGHT:
				kind[idx] = Kind.HILLS
				deposit[idx] = HILLS_DEPOSIT_MAX
			elif h >= FOREST_MIN_HEIGHT and h <= FOREST_MAX_HEIGHT and _cover(forest_cover, x, y) > FOREST_COVER_THRESHOLD:
				kind[idx] = Kind.FOREST
				deposit[idx] = FOREST_DEPOSIT_MAX
			elif _cover(stone_cover, x, y) > STONE_COVER_THRESHOLD:
				kind[idx] = Kind.STONE
				deposit[idx] = STONE_DEPOSIT_MAX
			else:
				kind[idx] = Kind.GRASS
				deposit[idx] = 0.0

func _cover(noise: FastNoiseLite, x: int, y: int) -> float:
	return (noise.get_noise_2d(x, y) + 1.0) * 0.5

func index_of(x: int, y: int) -> int:
	return y * cols + x

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows

# ---- extração e regeneração ----

# Devolve quanto foi realmente extraído (pode ser menos do que `amount` se o
# depósito estava quase seco). Esvaziar reverte a célula pra GRASS — o
# depósito não é só "número chegou a zero", é o chão mudando de aparência.
func extract(x: int, y: int, amount: float) -> float:
	if not inside(x, y) or amount <= 0.0:
		return 0.0
	var idx := index_of(x, y)
	if deposit[idx] <= 0.0:
		return 0.0
	var taken: float = minf(amount, deposit[idx])
	deposit[idx] -= taken
	if deposit[idx] <= 0.0:
		deposit[idx] = 0.0
		kind[idx] = Kind.GRASS
	return taken

func advance(delta: float) -> void:
	for idx in kind.size():
		if kind[idx] == Kind.FOREST and deposit[idx] > 0.0 and deposit[idx] < FOREST_DEPOSIT_MAX:
			deposit[idx] = minf(FOREST_DEPOSIT_MAX, deposit[idx] + FOREST_REGEN_PER_SECOND * delta)

# ---- leitura ----

func kind_at(x: int, y: int) -> int:
	return kind[index_of(x, y)] if inside(x, y) else Kind.GRASS

func height_at(x: int, y: int) -> float:
	return height[index_of(x, y)] if inside(x, y) else 0.0

func deposit_at(x: int, y: int) -> float:
	return deposit[index_of(x, y)] if inside(x, y) else 0.0

static func resource_name(k: int) -> String:
	match k:
		Kind.FOREST:
			return "madeira"
		Kind.STONE:
			return "pedra"
		Kind.HILLS:
			return "minério"
		_:
			return ""

func coverage() -> Dictionary:
	var counts := {Kind.GRASS: 0, Kind.FOREST: 0, Kind.STONE: 0, Kind.HILLS: 0}
	for k in kind:
		counts[k] += 1
	var total: float = maxf(1.0, float(kind.size()))
	var result := {}
	for k in counts:
		result[k] = float(counts[k]) / total
	return result
