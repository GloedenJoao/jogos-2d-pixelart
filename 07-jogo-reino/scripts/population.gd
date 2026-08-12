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
# Deliberadamente NÃO modela necessidades (comida, água potável, descanso)
# ainda — o plano do projeto pede isso também na Fase 6, mas exigiria uma
# fonte de comida (Fazenda/Posto de Caça) que nenhuma fase anterior
# construiu. Fica para quando essa cadeia existir; por ora, população é só
# "quantas pessoas existem", não "quão bem elas vivem".

# Devagar o bastante pra dar pra VER a vila se povoando (não é tudo pronto
# no frame 1, que era o comportamento até a Fase 5), rápido o bastante pra
# não fazer todo teste da Fase 2-5 precisar de um teto de passos muito maior
# só pra esperar gente nascer. Preencher as 4 vagas iniciais (3 trabalhadores
# + 1 carregador) leva ~13s nesse ritmo.
const GROWTH_PER_SECOND := 0.3

var count: float = 0.0
var _employed := 0

func advance(delta: float, housing_capacity: int) -> void:
	if count < housing_capacity:
		count = minf(float(housing_capacity), count + GROWTH_PER_SECOND * delta)

func available() -> int:
	return int(count) - _employed

func employ() -> bool:
	if available() <= 0:
		return false
	_employed += 1
	return true

func employed() -> int:
	return _employed
