class_name Villager
extends RefCounted

# Um morador da colônia. Dado puro, sem Node2D — quem lê/escreve isto é a
# Population (lógica) e, na cena, um pool de sprites que só espelha o estado
# (ver "Fase 0" no README: simulação e renderização são coisas separadas).

const STATE_IDLE := "idle"
const STATE_WALKING := "walking"
const STATE_WORKING := "working"
const STATE_EATING := "eating"
const STATE_RESTING := "resting"

# Duração de uma refeição/descanso completos, em segundos de jogo.
const EAT_DURATION := 4.0
const REST_DURATION := 6.0

const FIRST_NAMES := [
	"Ana", "Bento", "Clara", "Davi", "Elis", "Flor", "Gil", "Helo",
	"Igor", "Julia", "Kaio", "Léa", "Mateus", "Noa", "Otto", "Pilar",
	"Quel", "Rian", "Sara", "Tiago", "Uma", "Vico", "Wilma", "Xico",
	"Yara", "Zeca",
]

var id: int
var display_name: String
var position: Vector2
var target_position: Vector2
var speed: float = 90.0

var job_id: String = ""        # id de construção que este villager trabalha, "" = sem emprego

var state: String = STATE_IDLE
var pending_action: String = "" # "work"/"eat"/"rest": o que fazer ao chegar no destino (ver Population)
var action_timer: float = 0.0   # tempo restante da ação atual (comer/descansar)

# Necessidades em 0.0 (crítico) .. 1.0 (cheio). Começam cheias: um novo
# morador chega bem, e vai decaindo enquanto vive/trabalha.
var hunger: float = 1.0
var energy: float = 1.0
var mood: float = 0.8

func _init(p_id: int = 0, p_name: String = "", p_position: Vector2 = Vector2.ZERO) -> void:
	id = p_id
	display_name = p_name
	position = p_position
	target_position = p_position

func is_moving() -> bool:
	return position.distance_squared_to(target_position) > 1.0

func has_job() -> bool:
	return job_id != ""

static func random_name(rng: RandomNumberGenerator) -> String:
	return FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)]

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
	return v
