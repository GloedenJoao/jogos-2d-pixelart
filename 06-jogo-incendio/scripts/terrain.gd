class_name Terrain
extends RefCounted

# O que existe no chão do vale, e como cada coisa se comporta diante do fogo.
#
# Este arquivo é a única fonte de verdade sobre matéria queimável. `FireSim` não
# sabe o que é uma árvore — ela só lê `fuel`, `ignition`, `output` e `burn_rate`
# da tabela abaixo. Trocar o equilíbrio do jogo é mexer aqui, não na física.
#
# As quatro grandezas, e por que são quatro:
#
#   * `fuel`      quanto tempo a célula queima antes de virar cinza. É o que dá
#                 sentido ao contra-fogo: combustível gasto não volta.
#   * `ignition`  quanto calor ela aguenta antes de pegar. Casa resiste mais que
#                 capim — é por isso que uma casa cercada de mato morre e uma
#                 cercada de terra não.
#   * `output`    quanto calor ela joga nos vizinhos enquanto queima. Árvore é o
#                 grande propagador do jogo; lavoura queima rápido mas fraco.
#   * `burn_rate` velocidade com que consome o próprio combustível.
#
# Separar `output` de `fuel` é o que cria as duas ameaças distintas: a lavoura é
# um rastilho (acaba rápido, espalha pouco) e a mata é uma fornalha (demora e
# joga fogo longe). Com um número só, todo terreno seria o mesmo terreno.

enum {
	GRASS,     # capim: o tapete do vale, pega fogo fácil e passa adiante
	BRUSH,     # mato seco: o pior vizinho que uma casa pode ter
	TREE,      # mata: queima muito tempo e irradia longe
	HOUSE,     # o que você está tentando salvar
	FIELD,     # lavoura: rastilho — vai rápido e morre rápido
	DIRT,      # terra batida: não queima. É no que o aceiro transforma o chão.
	ROCK,      # rocha: barreira natural, não queima nem deixa passar
	WATER,     # água: não queima e molha a vizinhança
}

const NAMES := {
	GRASS: "capim", BRUSH: "mato", TREE: "mata", HOUSE: "casa",
	FIELD: "lavoura", DIRT: "terra", ROCK: "rocha", WATER: "água",
}

# fuel, ignition, output, burn_rate, moisture (umidade natural)
#
# `burn_rate` não é enfeite: uma célula precisa ficar em chamas TEMPO SUFICIENTE
# pra acender a vizinha, senão a frente de fogo se apaga sozinha e o jogo não
# existe. Com os números da FireSim, capim leva ~10s pra pegar de um vizinho
# só e ~2,5s quando há uma frente inteira empurrando — então capim tem que
# queimar bem mais de 10s. Daí os tempos de vida abaixo (fuel ÷ burn_rate):
#
#   capim 22s · mato 20s · mata 40s · casa 30s · lavoura 12s
#
# É essa folga que dá ao incêndio a forma que o jogo precisa: um foco isolado
# demora a pegar embalo (dá pra conter), e uma frente formada anda sozinha.
const DATA := {
	GRASS: {"fuel": 1.0, "ignition": 0.50, "output": 0.55, "burn_rate": 0.045, "moisture": 0.05},
	BRUSH: {"fuel": 1.5, "ignition": 0.40, "output": 0.78, "burn_rate": 0.075, "moisture": 0.02},
	TREE:  {"fuel": 3.2, "ignition": 0.72, "output": 1.15, "burn_rate": 0.080, "moisture": 0.12},
	HOUSE: {"fuel": 2.4, "ignition": 0.85, "output": 0.80, "burn_rate": 0.080, "moisture": 0.10},
	FIELD: {"fuel": 1.4, "ignition": 0.38, "output": 0.58, "burn_rate": 0.120, "moisture": 0.08},
	DIRT:  {"fuel": 0.0, "ignition": 9.0,  "output": 0.0,  "burn_rate": 0.0,   "moisture": 0.10},
	ROCK:  {"fuel": 0.0, "ignition": 9.0,  "output": 0.0,  "burn_rate": 0.0,   "moisture": 0.10},
	WATER: {"fuel": 0.0, "ignition": 9.0,  "output": 0.0,  "burn_rate": 0.0,   "moisture": 1.00},
}

# O caractere de cada terreno nos mapas ASCII das fases (scripts/levels.gd).
const CHARS := {
	".": GRASS, ",": BRUSH, "T": TREE, "H": HOUSE,
	"=": FIELD, "_": DIRT, "#": ROCK, "~": WATER,
}

static func from_char(c: String) -> int:
	return CHARS.get(c, GRASS)

static func fuel_of(kind: int) -> float:
	return DATA[kind]["fuel"]

static func ignition_of(kind: int) -> float:
	return DATA[kind]["ignition"]

static func output_of(kind: int) -> float:
	return DATA[kind]["output"]

static func burn_rate_of(kind: int) -> float:
	return DATA[kind]["burn_rate"]

static func moisture_of(kind: int) -> float:
	return DATA[kind]["moisture"]

static func is_flammable(kind: int) -> bool:
	return DATA[kind]["fuel"] > 0.0

static func name_of(kind: int) -> String:
	return NAMES.get(kind, "?")

# Dá pra pisar? Rocha e água barram gente; casa também (você contorna, não
# atravessa). O resto é chão livre — inclusive o que já queimou.
static func is_walkable(kind: int) -> bool:
	return kind != ROCK and kind != WATER and kind != HOUSE

# Dá pra cavar aceiro aqui? Só faz sentido em chão queimável: cavar rocha é
# pedido inválido, e a ferramenta precisa recusar em vez de gastar o turno.
#
# E casa NÃO. Casa é combustível como qualquer outra coisa, então a primeira
# versão desta função (só `is_flammable`) deixava o aceiro passar por cima
# dela — o brigadista demolia a casa pra impedir que ela queimasse, o contador
# de casas totais caía, e a fase ficava impossível por um motivo que não
# aparecia em lugar nenhum na tela.
static func can_dig(kind: int) -> bool:
	return is_flammable(kind) and kind != HOUSE
