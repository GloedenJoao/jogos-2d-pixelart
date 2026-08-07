class_name Villager
extends RefCounted

# Um morador da colônia. Dado puro, sem Node2D — quem lê/escreve isto é a
# Population (lógica) e, na cena, um boneco articulado que só espelha o estado
# (ver README: simulação e renderização continuam sendo coisas separadas).
#
# V2: o morador ganhou três coisas que ele não tinha.
#
#   * **Cara própria** (`look`): pele, camisa, cabelo, barba e chapéu sorteados
#     e salvos, em vez de "sprite nº id % 12".
#   * **Para onde ele olha** (`facing`): sem isso não existe animação
#     direcional — todo mundo andava de frente, inclusive andando pra trás.
#   * **Rota** (`path`): a Population não manda mais o morador em linha reta
#     atravessando as casas; manda uma sequência de pontos (ver Pathfinder).
#
# E uma quarta necessidade: `social`. Trabalhar, comer e dormir eram as três
# únicas coisas que alguém fazia aqui, e por isso a colônia parecia uma linha
# de montagem. Gente conversa.

const STATE_IDLE := "idle"
const STATE_WALKING := "walking"
const STATE_WORKING := "working"
const STATE_EATING := "eating"
const STATE_RESTING := "resting"
const STATE_SOCIALIZING := "socializing"
const STATE_CELEBRATING := "celebrating"
const STATE_BUILDING := "building"

# Duração de cada ação completa, em segundos de jogo.
const EAT_DURATION := 4.0
const REST_DURATION := 6.0
const SOCIAL_DURATION := 5.0
const CELEBRATE_DURATION := 3.5
const BUILD_DURATION := 4.0

# Direções assadas. Leste e oeste usam o mesmo desenho, espelhado.
const DIR_SOUTH := 0
const DIR_EAST := 1
const DIR_NORTH := 2
const DIR_WEST := 3

const FIRST_NAMES := [
	"Ana", "Bento", "Clara", "Davi", "Elis", "Flor", "Gil", "Helo",
	"Igor", "Julia", "Kaio", "Léa", "Mateus", "Noa", "Otto", "Pilar",
	"Quel", "Rian", "Sara", "Tiago", "Uma", "Vico", "Wilma", "Xico",
	"Yara", "Zeca",
]
const LAST_NAMES := [
	"do Vale", "da Fonte", "Pedra", "das Flores", "Correia", "do Morro",
	"Ferraz", "Lima", "Serra", "Campos", "Neves", "Rocha",
]

var id: int
var display_name: String
var position: Vector2
var target_position: Vector2
var speed: float = 90.0

var job_id: String = ""        # id de construção que este villager trabalha, "" = sem emprego

var state: String = STATE_IDLE
var pending_action: String = "" # "work"/"eat"/"rest"/...: o que fazer ao chegar (ver Population)
var action_timer: float = 0.0   # tempo restante da ação atual

# Necessidades em 0.0 (crítico) .. 1.0 (cheio). Começam cheias: um novo
# morador chega bem, e vai decaindo enquanto vive/trabalha.
var hunger: float = 1.0
var energy: float = 1.0
var mood: float = 0.8
var social: float = 1.0

# ---- V2 ----
var look: Dictionary = {}
var facing: int = DIR_SOUTH
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var velocity: Vector2 = Vector2.ZERO
var partner_id: int = 0         # com quem está conversando (0 = ninguém)
var carrying: String = ""       # recurso que leva na mão, "" = mãos livres
# Saiu do posto A TRABALHO (levar a produção ao celeiro e voltar). Cobre a ida
# E a volta: sem isso o trajeto de volta, já sem carga, contaria como "posto
# vazio" e a construção produziria menos só porque o V2 fez o trabalhador
# andar. O V2 muda comportamento, não o equilíbrio — ver Population.
var errand: bool = false
# Relógio próprio de animação: se todo mundo compartilhasse a mesma fase, a
# colônia inteira daria o mesmo passo no mesmo frame e pareceria um desfile.
var anim_phase: float = 0.0

func _init(p_id: int = 0, p_name: String = "", p_position: Vector2 = Vector2.ZERO) -> void:
	id = p_id
	display_name = p_name
	position = p_position
	target_position = p_position

func is_moving() -> bool:
	return position.distance_squared_to(target_position) > 1.0

func has_job() -> bool:
	return job_id != ""

func has_path() -> bool:
	return path_index < path.size()

func work_kind() -> String:
	return Buildings.work_of(job_id) if has_job() else "craft"

func clear_path() -> void:
	path = PackedVector2Array()
	path_index = 0

func set_path(points: PackedVector2Array) -> void:
	path = points
	path_index = 0
	target_position = points[points.size() - 1] if points.size() > 0 else position

# A direção vem do movimento quando ele anda, e da última direção quando para —
# senão o morador "vira de frente" no instante em que chega, o que faz o corpo
# dar um solavanco no fim de cada caminhada.
func face_towards(direction: Vector2) -> void:
	if direction.length_squared() < 0.01:
		return
	if absf(direction.x) > absf(direction.y) * 1.15:
		facing = DIR_EAST if direction.x > 0.0 else DIR_WEST
	else:
		facing = DIR_SOUTH if direction.y > 0.0 else DIR_NORTH

func face_point(point: Vector2) -> void:
	face_towards(point - position)

# O quanto ele está longe de estar bem: usado pra escolher a expressão e pro
# painel de inspeção. Necessidade mais baixa manda.
func worst_need() -> String:
	var lowest: float = hunger
	var which := "hunger"
	if energy < lowest:
		lowest = energy
		which = "energy"
	if social < lowest:
		lowest = social
		which = "social"
	return which

static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [
		FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
		LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
	]

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"x": position.x, "y": position.y,
		"job_id": job_id,
		"state": state,
		"hunger": hunger,
		"energy": energy,
		"mood": mood,
		"social": social,
		"look": look,
		"facing": facing,
	}

static func from_dict(data: Dictionary) -> Villager:
	var v := Villager.new(int(data.get("id", 0)), String(data.get("name", "")), Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))))
	v.target_position = v.position
	v.job_id = String(data.get("job_id", ""))
	# Estado ao recarregar sempre volta pra "ocioso": evita restaurar alguém
	# "andando" no meio do caminho pra um destino que pode nem existir mais.
	v.state = STATE_IDLE
	v.hunger = clampf(float(data.get("hunger", 1.0)), 0.0, 1.0)
	v.energy = clampf(float(data.get("energy", 1.0)), 0.0, 1.0)
	v.mood = clampf(float(data.get("mood", 0.8)), 0.0, 1.0)
	v.social = clampf(float(data.get("social", 1.0)), 0.0, 1.0)
	var saved_look = data.get("look", {})
	# A aparência é salva: reabrir o jogo e encontrar outra gente seria o mesmo
	# que trocar a colônia inteira por estranhos.
	v.look = saved_look.duplicate(true) if saved_look is Dictionary else {}
	v.facing = clampi(int(data.get("facing", DIR_SOUTH)), 0, 3)
	return v
