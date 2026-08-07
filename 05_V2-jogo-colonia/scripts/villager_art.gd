class_name VillagerArt
extends RefCounted

# A fábrica de gente do V2.
#
# O sheet "Roguelike Characters" da Kenney não é um catálogo de 12 personagens
# prontos (que foi como o V1 o usou): é um **paper doll modular**. Corpos nus,
# camisas, cabelos, barbas e chapéus são todos desenhados na MESMA grade de
# 16×16, alinhados pixel a pixel. Descoberto isso, o morador deixa de ser
# "sprite nº 7" e passa a ser uma combinação — pele, roupa, cabelo, barba,
# chapéu, cada um com cor própria.
#
# Este arquivo faz três coisas, todas sem depender de cena (testável headless):
#
#   1. `random_look()`  — sorteia uma aparência (milhões de combinações).
#   2. `bake()`         — compõe as camadas e devolve UMA textura por morador,
#                         com duas poses (de frente e de costas) lado a lado.
#   3. rosto            — um atlas separado de expressões (olhos/boca/sobrancelha)
#                         desenhado por cima, porque a cara muda com humor, fome
#                         e cansaço e não pode estar assada no corpo.
#
# O corpo é assado UMA vez por morador; a ANIMAÇÃO não é assada. A cena recorta
# essa textura em partes (cabeça, tronco, braços, pernas) e move cada parte —
# ver `scenes/villager_view.gd`. Assar 20 quadros × 4 direções por morador
# custaria caro e daria movimento travado; mover 6 pedaços custa nada e permite
# pose contínua.

const SHEET_PATH := "res://assets/characters/roguelikeChar_transparent.png"
const TILE := 16
const MARGIN := 1           # o sheet tem 1px de respiro entre tiles

# ---- anatomia do sprite de 16×16 (conferida pixel a pixel no sheet) ----
# linhas 2..7 cabeça · 7..13 tronco+braços · 14..15 pernas/pés
const EYE_LEFT_X := 6
const EYE_RIGHT_X := 9
const EYE_Y := 5
const MOUTH_Y := 7
const MOUTH_X := 7

# Recortes de cada parte animável, em pixels do tile de 16×16. As faixas se
# SOBREPÕEM de propósito (tronco começa na linha 6, cabeça termina na 7): ao
# deslocar uma parte 1px, a sobreposição tapa a costura que apareceria.
const PART_HEAD := Rect2i(3, 0, 10, 8)
const PART_TORSO := Rect2i(3, 6, 10, 9)
const PART_ARM_LEFT := Rect2i(0, 6, 4, 9)
const PART_ARM_RIGHT := Rect2i(12, 6, 4, 9)
const PART_LEG_LEFT := Rect2i(3, 14, 4, 2)
const PART_LEG_RIGHT := Rect2i(9, 14, 4, 2)

# Poses assadas na textura do morador, lado a lado.
const POSE_FRONT := 0
const POSE_BACK := 1
const POSE_COUNT := 2

# ---- expressões ----
const EXPR_NEUTRAL := 0
const EXPR_HAPPY := 1
const EXPR_SAD := 2
const EXPR_TIRED := 3
const EXPR_HUNGRY := 4
const EXPR_BLINK := 5
const EXPR_SLEEP := 6
const EXPR_TALK := 7
const EXPR_COUNT := 8

# Cada expressão é assada de frente e de perfil (de perfil só um olho aparece).
const FACE_FRONT := 0
const FACE_SIDE := 1
const FACE_VIEWS := 2

# ---- catálogo de peças (coordenadas conferidas no sheet) ----

# Corpo nu com boca (coluna 1). A linha escolhe o desenho-base; a cor real vem
# da recolorização, então a paleta de pele não fica presa aos 3 tons do sheet.
const BODY_TILE := Vector2i(1, 0)

const SKIN_COLORS := [
	Color("f2d3ac"), Color("e8bf90"), Color("d9a877"),
	Color("bd8a5c"), Color("9c6b42"), Color("7a5132"),
]

# Camisas de gola aberta — as únicas que deixam a boca à mostra (as de gola
# alta cobrem a linha 7 e o morador fica sem cara). Filtradas do sheet.
const SHIRT_TILES := [
	Vector2i(6, 0), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4),
	Vector2i(7, 2), Vector2i(7, 3), Vector2i(8, 0), Vector2i(8, 3),
	Vector2i(8, 4), Vector2i(9, 3),
]

const SHIRT_COLORS := [
	Color("c4622a"), Color("a8452b"), Color("d08c3a"), Color("7f9b3c"),
	Color("4d7d4a"), Color("3f7d8c"), Color("39628f"), Color("6b5aa0"),
	Color("9c4f7a"), Color("8c7a5c"), Color("c9c2b0"), Color("55565f"),
	Color("b8983c"), Color("2f6d6a"),
]

# Cabelos: 4 formatos curtos (linha base) e 4 compridos (linha base + 1).
const HAIR_TILES := [
	Vector2i(19, 0), Vector2i(20, 0), Vector2i(21, 0), Vector2i(22, 0),
	Vector2i(19, 1), Vector2i(20, 1), Vector2i(21, 1), Vector2i(22, 1),
]
# Barbas ficam duas linhas abaixo do cabelo do mesmo formato.
const BEARD_TILES := [
	Vector2i(19, 2), Vector2i(20, 2), Vector2i(21, 2), Vector2i(22, 2),
	Vector2i(19, 3), Vector2i(21, 3),
]
const HAIR_COLORS := [
	Color("3a2a1c"), Color("5a3d24"), Color("7d5a30"), Color("a8752f"),
	Color("c2892f"), Color("d9c07a"), Color("8f8f8f"), Color("d6d6d6"),
	Color("6b3a1f"),
]

const HAT_TILES := [Vector2i(28, 0), Vector2i(28, 2), Vector2i(28, 4), Vector2i(28, 8)]
const HAT_COLORS := [
	Color("8a8a8a"), Color("6b4a2a"), Color("3f7d8c"), Color("a8452b"), Color("55565f"),
]

# Ferramentas seguradas durante o trabalho, por "jeito de trabalhar".
const TOOL_TILES := {
	"chop": Vector2i(51, 0),    # machado
	"mine": Vector2i(48, 0),    # picareta
	"farm": Vector2i(50, 1),    # enxada
	"craft": Vector2i(47, 1),   # martelo
	"study": Vector2i(-1, -1),  # sem ferramenta: lê um livro (desenhado à parte)
	"trade": Vector2i(-1, -1),  # sem ferramenta: carrega caixote
}

static var _sheet: Image = null

# O sheet é lido uma vez por execução. `get_image()` funciona headless porque a
# textura é importada sem compressão de VRAM (compress/mode=0 no .import).
static func sheet() -> Image:
	if _sheet == null:
		var texture: Texture2D = load(SHEET_PATH)
		var img := texture.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_sheet = img
	return _sheet

static func tile_rect(coord: Vector2i) -> Rect2i:
	return Rect2i(coord.x * (TILE + MARGIN), coord.y * (TILE + MARGIN), TILE, TILE)

static func tile_image(coord: Vector2i) -> Image:
	return sheet().get_region(tile_rect(coord))

# ---- recolorização por rampa ----

# Troca a paleta de uma peça mantendo a ORDEM de luminância: o pixel mais escuro
# do desenho continua sendo o mais escuro depois de trocar a cor. É isso que
# preserva o sombreado do pixel art — tingir com `modulate` só escurece tudo e
# transforma arte detalhada em borrão (erro do V1).
static func recolor(src: Image, base: Color) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var found := {}
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a > 0.0:
				found[c] = true
	var shades: Array = found.keys()
	shades.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())

	var ramp := {}
	var n := shades.size()
	for i in n:
		var t: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		var v: float = clampf(lerpf(base.v * 0.52, minf(1.0, base.v * 1.22), t), 0.05, 1.0)
		var s: float = clampf(base.s * lerpf(1.15, 0.82, t), 0.0, 1.0)
		ramp[shades[i]] = Color.from_hsv(base.h, s, v, 1.0)

	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a > 0.0:
				var mapped: Color = ramp[c]
				mapped.a = c.a
				out.set_pixel(x, y, mapped)
	return out

# ---- aparência ----

# Uma aparência é um punhado de índices e cores — dá pra salvar/carregar como
# dado puro, então o morador reabre o jogo com a mesma cara.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var has_beard: bool = rng.randf() < 0.28
	var has_hat: bool = rng.randf() < 0.18
	var hair_color: Color = HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]
	return {
		"skin": SKIN_COLORS[rng.randi_range(0, SKIN_COLORS.size() - 1)].to_html(false),
		"shirt": rng.randi_range(0, SHIRT_TILES.size() - 1),
		"shirt_color": SHIRT_COLORS[rng.randi_range(0, SHIRT_COLORS.size() - 1)].to_html(false),
		"hair": rng.randi_range(0, HAIR_TILES.size() - 1),
		"hair_color": hair_color.to_html(false),
		"beard": rng.randi_range(0, BEARD_TILES.size() - 1) if has_beard else -1,
		"hat": rng.randi_range(0, HAT_TILES.size() - 1) if has_hat else -1,
		"hat_color": HAT_COLORS[rng.randi_range(0, HAT_COLORS.size() - 1)].to_html(false),
	}

static func _color_of(look: Dictionary, key: String, fallback: Color) -> Color:
	var raw = look.get(key, "")
	if raw is String and not String(raw).is_empty():
		return Color(String(raw))
	return fallback

static func skin_color(look: Dictionary) -> Color:
	return _color_of(look, "skin", SKIN_COLORS[0])

# Olho e boca derivam da pele: uma pele escura pede olho mais escuro ainda, ou
# o rosto some. Não são cores fixas.
static func eye_color(look: Dictionary) -> Color:
	var skin := skin_color(look)
	return Color.from_hsv(skin.h, clampf(skin.s * 1.1, 0.0, 1.0), clampf(skin.v * 0.34, 0.05, 1.0))

static func mouth_color(look: Dictionary) -> Color:
	var skin := skin_color(look)
	return Color.from_hsv(clampf(skin.h - 0.02, 0.0, 1.0), clampf(skin.s * 1.25, 0.0, 1.0), clampf(skin.v * 0.55, 0.06, 1.0))

# ---- composição do corpo ----

static func _blend(dst: Image, src: Image, at: Vector2i = Vector2i.ZERO) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)

# Sprite de 16×16 com todas as camadas, ainda COM a cara do sheet.
static func compose_base(look: Dictionary) -> Image:
	var out := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	_blend(out, recolor(tile_image(BODY_TILE), skin_color(look)))

	var shirt_index := int(look.get("shirt", -1))
	if shirt_index >= 0:
		var shirt := tile_image(SHIRT_TILES[shirt_index % SHIRT_TILES.size()])
		_blend(out, recolor(shirt, _color_of(look, "shirt_color", SHIRT_COLORS[0])))

	var hair_color := _color_of(look, "hair_color", HAIR_COLORS[0])
	var hair_index := int(look.get("hair", -1))
	if hair_index >= 0:
		_blend(out, recolor(tile_image(HAIR_TILES[hair_index % HAIR_TILES.size()]), hair_color))

	var beard_index := int(look.get("beard", -1))
	if beard_index >= 0:
		_blend(out, recolor(tile_image(BEARD_TILES[beard_index % BEARD_TILES.size()]), hair_color))

	var hat_index := int(look.get("hat", -1))
	if hat_index >= 0:
		_blend(out, recolor(tile_image(HAT_TILES[hat_index % HAT_TILES.size()]), _color_of(look, "hat_color", HAT_COLORS[0])))

	return out

# A cara do sheet é apagada do corpo: quem desenha olho e boca é o atlas de
# expressões, que troca em tempo real conforme fome/cansaço/humor.
static func _erase_face(img: Image, skin: Color) -> void:
	for point in [Vector2i(EYE_LEFT_X, EYE_Y), Vector2i(EYE_RIGHT_X, EYE_Y),
			Vector2i(MOUTH_X, MOUTH_Y), Vector2i(MOUTH_X + 1, MOUTH_Y)]:
		if img.get_pixel(point.x, point.y).a > 0.0:
			img.set_pixel(point.x, point.y, skin)

# De costas: além de não ter cara, a nuca é coberta pelo cabelo — sem isso um
# morador de costas fica só "um morador sem rosto", que lê como bug.
static func _make_back(front: Image, look: Dictionary) -> Image:
	var out := front.duplicate()
	var hair_index := int(look.get("hair", -1))
	if hair_index < 0:
		return out
	var hair := recolor(tile_image(HAIR_TILES[hair_index % HAIR_TILES.size()]), _color_of(look, "hair_color", HAIR_COLORS[0]))
	# Franja escorrida sobre o rosto: copia a linha mais baixa do cabelo pra
	# baixo até o queixo, respeitando a silhueta da cabeça.
	var fringe_row := -1
	for y in range(TILE - 1, -1, -1):
		for x in TILE:
			if hair.get_pixel(x, y).a > 0.0:
				fringe_row = y
				break
		if fringe_row >= 0:
			break
	if fringe_row < 0:
		return out
	for y in range(mini(fringe_row + 1, MOUTH_Y), MOUTH_Y):
		for x in range(4, 12):
			if out.get_pixel(x, y).a > 0.0 and hair.get_pixel(x, fringe_row).a > 0.0:
				out.set_pixel(x, y, hair.get_pixel(x, fringe_row))
			elif out.get_pixel(x, y).a > 0.0 and hair.get_pixel(clampi(x, 4, 11), fringe_row).a > 0.0:
				out.set_pixel(x, y, hair.get_pixel(clampi(x, 4, 11), fringe_row))
	return out

# Textura do morador: as duas poses (frente, costas) numa tira de 32×16.
static func bake_body(look: Dictionary) -> ImageTexture:
	var skin := skin_color(look)
	var front := compose_base(look)
	_erase_face(front, skin)
	var back := _make_back(front, look)

	var strip := Image.create(TILE * POSE_COUNT, TILE, false, Image.FORMAT_RGBA8)
	strip.blit_rect(front, Rect2i(0, 0, TILE, TILE), Vector2i(POSE_FRONT * TILE, 0))
	strip.blit_rect(back, Rect2i(0, 0, TILE, TILE), Vector2i(POSE_BACK * TILE, 0))
	return ImageTexture.create_from_image(strip)

static func pose_offset(pose: int) -> int:
	return pose * TILE

# ---- rosto ----

# Uma expressão é meia dúzia de pixels: dois olhos, uma boca e, às vezes,
# sobrancelha. Tudo cabe dentro do recorte da cabeça (linhas 0..7), então o
# rosto é um sprite irmão que acompanha a cabeça quando ela balança.
static func _draw_face(img: Image, expr: int, view: int, eye: Color, mouth: Color) -> void:
	# De perfil, o olho de trás some e o rosto desliza pro lado que ele encara.
	var shift: int = 1 if view == FACE_SIDE else 0
	var eyes: Array = [EYE_LEFT_X, EYE_RIGHT_X] if view == FACE_FRONT else [EYE_RIGHT_X]
	var mx: int = MOUTH_X + shift

	var draw_eyes := true
	if expr == EXPR_BLINK or expr == EXPR_SLEEP:
		draw_eyes = false
	if draw_eyes:
		for x in eyes:
			img.set_pixel(int(x) + shift, EYE_Y, eye)
	if expr == EXPR_TIRED:
		# Olho semicerrado: uma risca de 2px em vez do ponto.
		for x in eyes:
			img.set_pixel(clampi(int(x) + shift - 1, 4, 11), EYE_Y, eye)

	match expr:
		EXPR_HAPPY:
			for dx in 4:
				img.set_pixel(clampi(mx - 1 + dx, 4, 11), MOUTH_Y, mouth)
		EXPR_SAD:
			img.set_pixel(mx, MOUTH_Y, mouth)
			img.set_pixel(mx + 1, MOUTH_Y, mouth)
			img.set_pixel(clampi(mx - 2, 4, 11), EYE_Y - 1, eye)
			img.set_pixel(clampi(mx + 3, 4, 11), EYE_Y - 1, eye)
		EXPR_HUNGRY, EXPR_TALK:
			for dy in 2:
				img.set_pixel(mx, MOUTH_Y - 1 + dy, mouth)
				img.set_pixel(mx + 1, MOUTH_Y - 1 + dy, mouth)
		EXPR_SLEEP:
			img.set_pixel(mx, MOUTH_Y, mouth)
		_:
			img.set_pixel(mx, MOUTH_Y, mouth)
			img.set_pixel(mx + 1, MOUTH_Y, mouth)

# Atlas vertical: uma linha por (expressão × vista), recortado no tamanho da
# cabeça pra o sprite do rosto usar exatamente o mesmo retângulo dela.
static func bake_face(look: Dictionary) -> ImageTexture:
	var eye := eye_color(look)
	var mouth := mouth_color(look)
	var w := PART_HEAD.size.x
	var h := PART_HEAD.size.y
	var atlas := Image.create(w, h * EXPR_COUNT * FACE_VIEWS, false, Image.FORMAT_RGBA8)
	for expr in EXPR_COUNT:
		for view in FACE_VIEWS:
			var frame := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
			_draw_face(frame, expr, view, eye, mouth)
			var cut := frame.get_region(PART_HEAD)
			atlas.blit_rect(cut, Rect2i(0, 0, w, h), Vector2i(0, face_row(expr, view) * h))
	return ImageTexture.create_from_image(atlas)

static func face_row(expr: int, view: int) -> int:
	return clampi(expr, 0, EXPR_COUNT - 1) * FACE_VIEWS + clampi(view, 0, FACE_VIEWS - 1)

static func face_region(expr: int, view: int) -> Rect2i:
	return Rect2i(0, face_row(expr, view) * PART_HEAD.size.y, PART_HEAD.size.x, PART_HEAD.size.y)

# ---- expressão a partir do estado do morador ----

# A cara segue a necessidade mais gritante, não o humor médio: quem está
# faminto parece faminto mesmo que o humor ainda não tenha desabado.
static func expression_for(state: String, hunger: float, energy: float, mood: float, blinking: bool) -> int:
	if state == Villager.STATE_RESTING:
		return EXPR_SLEEP
	if state == Villager.STATE_EATING:
		return EXPR_HUNGRY
	if state == Villager.STATE_SOCIALIZING:
		return EXPR_TALK
	if blinking:
		return EXPR_BLINK
	if energy < 0.3:
		return EXPR_TIRED
	if hunger < 0.3:
		return EXPR_HUNGRY
	if mood < 0.35:
		return EXPR_SAD
	if mood > 0.75:
		return EXPR_HAPPY
	return EXPR_NEUTRAL
