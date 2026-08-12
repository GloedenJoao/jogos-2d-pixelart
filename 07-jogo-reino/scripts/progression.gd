class_name Progression
extends RefCounted

# Fase 7: a vila sobe de nível conforme acumula recurso entregue no Armazém
# — qualquer tipo conta (madeira, pedra, tábua, bloco), é XP puro por
# volume, sem hierarquia de valor entre recursos ainda.
#
# Por ora, nível só desbloqueia ALCANCE DE EXPLORAÇÃO (o raio que a névoa
# revela ao redor da vila) — ver `reveal_radius()`. "Desbloqueio de
# prédios", que o plano do projeto também pede pra esta fase, fica de fora
# de propósito: hoje TODO prédio nasce de uma vez em `_place_starting_buildings`
# (main.gd), antes de existir qualquer conceito de nível; gatear isso por
# nível pediria reescrever a colocação de prédios pra ser progressiva, uma
# mudança de arquitetura maior do que o resto desta fase. Fica registrado
# como corte deliberado, não esquecimento — ver docs/plano-projeto7-reino.md.

# Medido rodando a economia real (ver tests/calibrate_progression.gd,
# removido depois de usado): com um extrator só ativo no começo do jogo, o
# Armazém acumula um punhado de unidades a cada poucos segundos assim que a
# cadeia (trabalhador → pátio → carregador → Armazém) emplaca. 40 XP por
# nível dá pra subir de nível em minutos de jogo, não segundos nem horas.
const XP_PER_LEVEL := 40.0

# Nível 1 é o inicial. O último nível da tabela é o teto — XP continua
# acumulando depois dele (sem custo, só não vira nível novo), em vez de
# travar o jogo numa trava de array.
const REVEAL_RADIUS_BY_LEVEL := {
	1: 9.0,
	2: 12.0,
	3: 15.0,
	4: 18.0,
	5: 21.0,
}

var level := 1
var xp := 0.0

func add_xp(amount: float) -> void:
	if amount <= 0.0:
		return
	xp += amount
	while xp >= XP_PER_LEVEL and REVEAL_RADIUS_BY_LEVEL.has(level + 1):
		xp -= XP_PER_LEVEL
		level += 1

func reveal_radius() -> float:
	return REVEAL_RADIUS_BY_LEVEL.get(level, REVEAL_RADIUS_BY_LEVEL[1])

func is_max_level() -> bool:
	return not REVEAL_RADIUS_BY_LEVEL.has(level + 1)
