class_name Eras
extends RefCounted

# As cinco eras da civilização. Cada era muda a paleta, o cenário da vila, o que
# um clique rende e quais construções existem (ver scripts/buildings.gd).
# "requirement" é o que precisa ser acumulado — e é consumido — pra passar pra
# era seguinte; a última era não tem requisito.

const ALL := [
	{
		"id": "pedra",
		"name": "Idade da Pedra",
		"subtitle": "Um punhado de gente, um vale e muito o que fazer.",
		"bg": Color("2a2118"),
		"ground": Color("3c3226"),
		"click_resources": ["comida"],
		"decor": [Vector2i(4, 1), Vector2i(3, 2), Vector2i(5, 2)],
		"requirement": {"comida": 100.0, "materiais": 60.0},
	},
	{
		"id": "agricultura",
		"name": "Era da Agricultura",
		"subtitle": "Plantar mudou tudo: dá pra ficar num lugar só.",
		"bg": Color("1e2a1c"),
		"ground": Color("2f4028"),
		"click_resources": ["comida", "materiais"],
		"decor": [Vector2i(4, 0), Vector2i(3, 1), Vector2i(6, 1)],
		"requirement": {"comida": 600.0, "materiais": 400.0, "conhecimento": 80.0},
	},
	{
		"id": "antiguidade",
		"name": "Era Antiga",
		"subtitle": "Mercados, escrita e as primeiras cidades grandes.",
		"bg": Color("1c2230"),
		"ground": Color("2b3550"),
		"click_resources": ["comida", "materiais", "conhecimento"],
		"decor": [Vector2i(0, 6), Vector2i(4, 6), Vector2i(11, 6)],
		"requirement": {"comida": 3000.0, "materiais": 2500.0, "conhecimento": 600.0},
	},
	{
		"id": "industria",
		"name": "Era Industrial",
		"subtitle": "Vapor, carvão e produção que não dorme.",
		"bg": Color("2a1e22"),
		"ground": Color("42302f"),
		"click_resources": ["comida", "materiais", "conhecimento"],
		"decor": [Vector2i(9, 10), Vector2i(4, 6), Vector2i(10, 8)],
		"requirement": {"comida": 15000.0, "materiais": 12000.0, "conhecimento": 4000.0},
	},
	{
		"id": "informacao",
		"name": "Era da Informação",
		"subtitle": "A civilização que você construiu agora se estuda.",
		"bg": Color("161d2b"),
		"ground": Color("222c44"),
		"click_resources": ["comida", "materiais", "conhecimento"],
		"decor": [Vector2i(8, 10), Vector2i(11, 10), Vector2i(0, 6)],
		"requirement": {},
	},
]

static func count() -> int:
	return ALL.size()

static func era(index: int) -> Dictionary:
	return ALL[clampi(index, 0, ALL.size() - 1)]

static func is_last(index: int) -> bool:
	return index >= ALL.size() - 1

static func requirement(index: int) -> Dictionary:
	return era(index).requirement

# Um clique rende mais nas eras avançadas (as mãos são as mesmas, as ferramentas não).
static func click_power(index: int) -> float:
	return 1.0 + index * 2.0
