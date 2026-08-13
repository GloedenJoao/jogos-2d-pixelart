class_name Population
extends RefCounted

# Mão de obra deixa de ser infinita e instantânea a partir da Fase 6: até
# aqui, todo trabalhador e o carregador nasciam prontos no primeiro frame.
# Agora existe uma POPULAÇÃO que cresce devagar até a capacidade habitacional
# (soma das Casas construídas — `Buildings.housing_capacity()`), e só quem
# está "disponível" (`available()`) pode ser empregado (`employ()`). Sem
# nenhuma Casa, capacidade é 0 e a população nunca sai do lugar — não dá pra
# ter gente sem lugar pra morar.
#
# Necessidade de COMIDA: cada habitante consome comida por segundo
# (`CONSUMPTION_PER_CAPITA`); `advance()` recebe quanto estoque de comida
# está disponível e devolve quanto foi de fato consumido, pra quem chama
# (main.gd) descontar do estoque jogável (`Buildings.stock`) — a mesma
# separação usada em todo o resto do projeto: `Population` não conhece
# `Buildings` diretamente, só troca números com quem chama.
#
# Crescimento acima de `BOOTSTRAP_POPULATION` exige comida em dia (sem
# déficit no tick); abaixo disso, cresce de graça — sem esse piso, a vila
# trava: ninguém pra construir/staffar a Fazenda sem população, e nenhuma
# comida sem Fazenda. `BOOTSTRAP_POPULATION` é só gente o bastante pra
# arrancar a economia, não pra vencer o jogo sozinha. Faltando comida acima
# do piso, a população encolhe na proporção do déficit
# (`STARVATION_SHRINK_PER_UNIT`) até no mínimo o próprio piso — nunca some
# de vez, mas para de crescer e de fato recua enquanto a fome durar. Medido
# (ver tests/calibrate_farm.gd, removido depois de usado): zero comida
# prende a vila no piso; comida parcial encontra um equilíbrio entre o piso
# e a capacidade cheia, proporcional ao quanto sustenta.
#
# Água potável e descanso continuam de fora de propósito — a mesma
# simplificação dos dois estendida: são necessidades reais no plano do
# projeto, mas cada uma pediria sua própria fonte (poço ligado ao WaterSim,
# um lugar de descanso) que nenhuma fase construiu ainda. Comida sozinha já
# prova o mecanismo (produção real → consumo real → consequência real).

# Devagar o bastante pra dar pra VER a vila se povoando (não é tudo pronto
# no frame 1, que era o comportamento até a Fase 5), rápido o bastante pra
# não fazer todo teste da Fase 2-5 precisar de um teto de passos muito maior
# só pra esperar gente nascer. Preencher as 4 vagas iniciais (3 trabalhadores
# + 1 carregador) leva ~13s nesse ritmo.
const GROWTH_PER_SECOND := 0.3

# Comida por segundo, por habitante. Medido junto com `Buildings.FARM`
# (ver tests/calibrate_farm.gd, removido depois de usado): com as duas Casas
# iniciais cheias (6 habitantes) e uma Fazenda staffada sozinha (0.7/s), a
# vila fica bem alimentada com folga — não tão justo que qualquer engasgo no
# transporte já mate gente de fome, não tão folgado que a necessidade vire
# decoração.
const CONSUMPTION_PER_CAPITA := 0.05
# Quanto a população encolhe por unidade de déficit de comida não atendido
# num segundo. 1:1 significa "um habitante-segundo faminto custa um
# habitante-segundo de população" — direto o bastante pra fome ser visível
# no HUD em vez de um decaimento imperceptível.
const STARVATION_SHRINK_PER_UNIT := 1.0
# Piso de população que nasce/sobrevive sem depender de comida nenhuma —
# gente o bastante pra formar a primeira leva de trabalhadores (construir e
# staffar a Fazenda em si já usa gente). Abaixo da capacidade típica de UMA
# Casa (`Buildings.HOUSE_CAPACITY`), então o piso nunca é o jogo inteiro.
const BOOTSTRAP_POPULATION := 2.0

var count: float = 0.0
var _employed := 0

# Devolve quanto de comida foi consumido neste avanço, pra quem chama
# descontar do estoque jogável.
func advance(delta: float, housing_capacity: int, food_available: float) -> float:
	var needed: float = count * CONSUMPTION_PER_CAPITA * delta
	var consumed: float = minf(needed, food_available)
	var shortfall: float = needed - consumed
	var starving: bool = shortfall > 0.0
	var bootstrap_cap: float = minf(BOOTSTRAP_POPULATION, float(housing_capacity))

	var can_grow: bool = count < bootstrap_cap or not starving
	if can_grow and count < housing_capacity:
		count = minf(float(housing_capacity), count + GROWTH_PER_SECOND * delta)
	if starving:
		count = maxf(bootstrap_cap, count - shortfall * STARVATION_SHRINK_PER_UNIT)

	return consumed

func available() -> int:
	return int(count) - _employed

func employ() -> bool:
	if available() <= 0:
		return false
	_employed += 1
	return true

func employed() -> int:
	return _employed
