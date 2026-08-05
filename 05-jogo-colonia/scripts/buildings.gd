class_name Buildings
extends RefCounted

# Catálogo de construções. Cada uma pertence a uma era (só aparece quando a
# civilização chega nela), custa recursos (custo sobe a cada cópia comprada) e
# produz recursos por segundo.
#
# "icon"/"sheet" apontam o sprite de 16×16 usado na vila e na lista: "town" é o
# tileset Kenney Tiny Town e "dungeon" reaproveita o tileset do Projeto 2
# (roguelike), pras eras mais primitivas.
#
# "jobs": vagas de trabalho por cópia da construção (Colônia Viva, Fase 3). A
# produção de uma construção só sai de fato quando tem um Villager presente e
# em estado "trabalhando" numa dessas vagas — ver Population.staffing_ratios().

const COST_GROWTH := 1.15

const ALL := [
	# --- Era 0: Idade da Pedra ---
	{
		"id": "coletor",
		"name": "Coletor de frutas",
		"desc": "Gente vasculhando o mato atrás de comida.",
		"era": 0,
		"sheet": "dungeon",
		"icon": Vector2i(2, 7),
		"cost": {"comida": 12.0},
		"produces": {"comida": 0.5},
		"jobs": 2,
	},
	{
		"id": "lascador",
		"name": "Lascador de pedra",
		"desc": "Transforma pedra bruta em ferramenta.",
		"era": 0,
		"sheet": "town",
		"icon": Vector2i(8, 9),
		"cost": {"comida": 25.0},
		"produces": {"materiais": 0.3},
		"jobs": 2,
	},
	{
		"id": "fogueira",
		"name": "Fogueira do clã",
		"desc": "À noite, alguém começa a explicar o mundo.",
		"era": 0,
		"sheet": "dungeon",
		"icon": Vector2i(5, 2),
		"cost": {"comida": 45.0, "materiais": 15.0},
		"produces": {"conhecimento": 0.05},
		"jobs": 1,
	},
	# --- Era 1: Agricultura ---
	{
		"id": "fazenda",
		"name": "Fazenda",
		"desc": "Comida que nasce onde você planta.",
		"era": 1,
		"sheet": "town",
		"icon": Vector2i(9, 9),
		"cost": {"comida": 80.0, "materiais": 30.0},
		"produces": {"comida": 2.0},
		"jobs": 3,
	},
	{
		"id": "oleiro",
		"name": "Oficina de olaria",
		"desc": "Potes, telhas e tijolos.",
		"era": 1,
		"sheet": "town",
		"icon": Vector2i(11, 8),
		"cost": {"comida": 120.0, "materiais": 60.0},
		"produces": {"materiais": 1.2},
		"jobs": 2,
	},
	{
		"id": "escriba",
		"name": "Casa do escriba",
		"desc": "O que era memória vira registro.",
		"era": 1,
		"sheet": "dungeon",
		"icon": Vector2i(0, 7),
		"cost": {"comida": 200.0, "materiais": 80.0},
		"produces": {"conhecimento": 0.3},
		"jobs": 1,
	},
	# --- Era 2: Antiguidade ---
	{
		"id": "mercado",
		"name": "Mercado",
		"desc": "Excedente vira troca, troca vira cidade.",
		"era": 2,
		"sheet": "town",
		"icon": Vector2i(8, 7),
		"cost": {"comida": 500.0, "materiais": 300.0},
		"produces": {"comida": 6.0},
		"jobs": 3,
	},
	{
		"id": "mina",
		"name": "Mina",
		"desc": "Metal suficiente pra mudar de era.",
		"era": 2,
		"sheet": "town",
		"icon": Vector2i(10, 10),
		"cost": {"comida": 600.0, "materiais": 400.0},
		"produces": {"materiais": 5.0},
		"jobs": 3,
	},
	{
		"id": "biblioteca",
		"name": "Biblioteca",
		"desc": "Conhecimento que sobrevive a quem escreveu.",
		"era": 2,
		"sheet": "town",
		"icon": Vector2i(11, 10),
		"cost": {"comida": 900.0, "materiais": 600.0, "conhecimento": 50.0},
		"produces": {"conhecimento": 1.2},
		"jobs": 2,
	},
	# --- Era 3: Indústria ---
	{
		"id": "moinho_vapor",
		"name": "Moinho a vapor",
		"desc": "Grão processado em escala de cidade.",
		"era": 3,
		"sheet": "town",
		"icon": Vector2i(10, 8),
		"cost": {"comida": 3000.0, "materiais": 2000.0},
		"produces": {"comida": 25.0},
		"jobs": 4,
	},
	{
		"id": "fabrica",
		"name": "Fábrica",
		"desc": "Produção em série, fumaça na chaminé.",
		"era": 3,
		"sheet": "town",
		"icon": Vector2i(9, 10),
		"cost": {"comida": 3500.0, "materiais": 2500.0},
		"produces": {"materiais": 20.0},
		"jobs": 4,
	},
	{
		"id": "escola",
		"name": "Escola pública",
		"desc": "Educar todo mundo, não só os escribas.",
		"era": 3,
		"sheet": "town",
		"icon": Vector2i(0, 6),
		"cost": {"comida": 5000.0, "materiais": 3000.0, "conhecimento": 400.0},
		"produces": {"conhecimento": 5.0},
		"jobs": 2,
	},
	# --- Era 4: Informação ---
	{
		"id": "agroindustria",
		"name": "Agroindústria",
		"desc": "Comida para milhões, com poucas mãos.",
		"era": 4,
		"sheet": "town",
		"icon": Vector2i(9, 7),
		"cost": {"comida": 20000.0, "materiais": 15000.0},
		"produces": {"comida": 120.0},
		"jobs": 5,
	},
	{
		"id": "usina",
		"name": "Usina de energia",
		"desc": "Tudo que veio depois depende dela.",
		"era": 4,
		"sheet": "town",
		"icon": Vector2i(4, 6),
		"cost": {"comida": 22000.0, "materiais": 18000.0},
		"produces": {"materiais": 100.0},
		"jobs": 4,
	},
	{
		"id": "universidade",
		"name": "Universidade",
		"desc": "Pesquisa que inventa a próxima era.",
		"era": 4,
		"sheet": "town",
		"icon": Vector2i(2, 6),
		"cost": {"comida": 30000.0, "materiais": 25000.0, "conhecimento": 3000.0},
		"produces": {"conhecimento": 25.0},
		"jobs": 3,
	},
]

static func find(id: String) -> Dictionary:
	for building in ALL:
		if building.id == id:
			return building
	return {}

static func jobs_of(id: String) -> int:
	var building := find(id)
	return int(building.get("jobs", 0)) if not building.is_empty() else 0

static func for_era(era_index: int) -> Array:
	var out: Array = []
	for building in ALL:
		if building.era <= era_index:
			out.append(building)
	return out

static func unlocked_in(era_index: int) -> Array:
	var out: Array = []
	for building in ALL:
		if building.era == era_index:
			out.append(building)
	return out
