class_name Tools
extends RefCounted

# As três maneiras de interferir num incêndio, e o preço de cada uma.
#
# O que separa este jogo de um jogo de cliques é que NENHUMA delas é instantânea
# e nenhuma delas é você: você dá a ordem, um brigadista caminha até lá e passa
# alguns segundos trabalhando. Errar o lugar custa o tempo da ida, e é esse
# tempo que transforma "onde eu clico" numa decisão.
#
# As três formam um triângulo de propósito:
#
#   * **Aceiro** é infinito e lento. É a resposta padrão, e a única que muda o
#     terreno pra sempre.
#   * **Água** é rápida e escassa. É a única que DESFAZ (apaga chama acesa),
#     e é o que se usa quando o fogo já está em cima.
#   * **Contra-fogo** é instantâneo e perigoso: acende de propósito, gasta o
#     combustível de uma área inteira antes de a frente chegar, e pode virar
#     contra você se o vento mudar.
#
# Um jogo com só a primeira seria paciência; com só a segunda, um jogo de
# recurso; com só a terceira, roleta.

enum { DIG, WATER, BACKFIRE }

const ORDER := [DIG, WATER, BACKFIRE]

const DATA := {
	DIG: {
		"name": "Aceiro",
		"hint": "Cava o chão até virar terra. Sem combustível, o fogo para aqui.",
		"seconds": 2.0,
		"limited": false,
		"key": "1",
	},
	WATER: {
		"name": "Água",
		"hint": "Apaga o que está pegando e molha o que não pegou. Some com o tempo.",
		"seconds": 1.1,
		"limited": true,
		"key": "2",
	},
	BACKFIRE: {
		"name": "Contra-fogo",
		"hint": "Ateia fogo de propósito pra gastar o combustível antes da frente chegar.",
		"seconds": 0.9,
		"limited": true,
		"key": "3",
	},
}

static func name_of(tool_id: int) -> String:
	return DATA[tool_id]["name"]

static func hint_of(tool_id: int) -> String:
	return DATA[tool_id]["hint"]

static func seconds_of(tool_id: int) -> float:
	return DATA[tool_id]["seconds"]

static func is_limited(tool_id: int) -> bool:
	return DATA[tool_id]["limited"]

static func key_of(tool_id: int) -> String:
	return DATA[tool_id]["key"]

# A ordem faz sentido nesta célula? Chamado ANTES de mandar alguém caminhar
# até lá — mandar um brigadista atravessar meio vale pra descobrir que não dá
# pra cavar em cima de uma pedra seria o pior tipo de tempo perdido, o que o
# jogador não consegue nem ver acontecendo.
static func can_target(tool_id: int, sim: FireSim, cell: Vector2i) -> bool:
	if not sim.inside(cell.x, cell.y):
		return false
	var idx := sim.index_of(cell.x, cell.y)
	var kind: int = sim.kind[idx]
	var state: int = sim.state[idx]
	match tool_id:
		DIG:
			# Não se cava chão em chamas nem rocha/água, e cavar o que já virou
			# cinza não adianta nada (não tem mais o que tirar).
			return state == FireSim.INTACT and Terrain.can_dig(kind)
		WATER:
			return state != FireSim.BURNT
		BACKFIRE:
			return state == FireSim.INTACT and Terrain.is_flammable(kind) and sim.fuel[idx] > 0.0
	return false

# Executa. Só é chamado quando o brigadista já está no lugar e já trabalhou o
# tempo da ferramenta; devolve se surtiu efeito (o mundo pode ter mudado
# durante a caminhada — a célula que ia ser cavada pode já estar em chamas).
static func apply(tool_id: int, sim: FireSim, cell: Vector2i) -> bool:
	match tool_id:
		DIG:
			return sim.strip(cell.x, cell.y)
		WATER:
			return sim.douse(cell.x, cell.y)
		BACKFIRE:
			return sim.ignite(cell.x, cell.y)
	return false
