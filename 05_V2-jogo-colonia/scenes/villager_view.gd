class_name VillagerView
extends Node2D

# O boneco. Um morador na tela é um Node2D com seis pedaços recortados da
# textura que o VillagerArt assou pra ele (cabeça, tronco, dois braços, duas
# pernas), mais rosto, ferramenta, carga e balão.
#
# **Por que pedaços e não quadros assados.** Assar spritesheet de animação por
# morador custaria dezenas de imagens por pessoa (5 estados × 4 direções ×
# 4 quadros) e, com 120 moradores de aparência única, isso não fecha. Mover
# seis retângulos custa nada, dá pose contínua (a caminhada acelera junto com
# quem anda rápido) e deixa a ferramenta girar de verdade na mão, em vez de
# pular entre desenhos prontos.
#
# As faixas dos pedaços se sobrepõem (o tronco começa uma linha antes de a
# cabeça acabar), então deslocar uma parte 1px nunca abre buraco na silhueta.
#
# Tudo é ancorado pelos PÉS: `position` é onde a pessoa pisa. É o que faz o
# y-sort funcionar (quem está mais embaixo aparece na frente) e o que impede o
# morador de flutuar acima do chão quando anda.

const SCALE := 3
const ANCHOR := Vector2(8, 16)   # pixel do tile que fica em cima da posição do morador

# Quantos segundos dura um quadro da caminhada na velocidade normal. Mais
# rápido que isso vira corridinha nervosa; mais lento, patinação.
const WALK_FRAME := 0.115
const BASE_SPEED := 90.0

const RESOURCE_COLORS := {
	"comida": Color("8fd17a"),
	"materiais": Color("d8a45c"),
	"conhecimento": Color("7ab8f0"),
}

# Onde a mão agarra cada ferramenta, em pixels do tile dela. Os sprites da
# Kenney têm um vão no cabo justamente onde a mão entra — é esse vão.
const TOOL_GRIP := {
	"chop": Vector2(1.5, 11.5),
	"mine": Vector2(2.5, 13.0),
	"farm": Vector2(1.5, 11.5),
	"craft": Vector2(2.5, 10.5),
}
# Posição da mão direita no corpo, em pixels do tile.
const HAND := Vector2(13.5, 11.5)

var villager_id: int = 0

var _body_texture: ImageTexture
var _face_texture: ImageTexture
var _pose: int = VillagerArt.POSE_FRONT

var _flip: Node2D
var _parts: Dictionary = {}      # nome -> Sprite2D
var _base_positions: Dictionary = {}
var _face: Sprite2D
var _hand: Node2D
var _tool: Sprite2D
var _held: Sprite2D
var _cargo: Sprite2D
var _bubble: Node2D
var _bubble_icon: Sprite2D
var _shadow: Sprite2D
var _work_kind: String = "craft"

# ---- texturas compartilhadas (uma vez por execução, não por morador) ----
static var _shadow_texture: Texture2D = null
static var _bubble_texture: Texture2D = null
static var _glyphs: Dictionary = {}

# Glifos 7×7 desenhados como texto: legíveis no código e exatos no pixel. Um
# ícone dizendo o que a pessoa faz lê muito melhor que a bolinha colorida do
# V1 — "amarelo" não significa nada, um martelo significa.
const GLYPH_ART := {
	"work": ["..###..", "..###..", "...#...", "...#...", "...#...", "...#...", "......."],
	"eat": ["#.#.#..", "#.#.#..", "#####..", "..#..##", "..#..##", "..#...#", "..#...#"],
	"rest": ["#####..", "....#..", "...#...", "..#....", ".#.....", "#####..", "......."],
	"chat": [".......", ".#####.", ".#####.", ".#####.", "..###..", "...#...", "......."],
	"haul": [".#####.", ".#...#.", ".#####.", ".#...#.", ".#####.", ".......", "......."],
	"build": ["..###..", ".#####.", "...#...", "...#...", "...#...", "...#...", "......."],
	"party": ["...#...", ".#.#.#.", "..###..", "#######", "..###..", ".#.#.#.", "...#..."],
	"study": [".#####.", ".#...#.", ".#####.", ".#...#.", ".#####.", ".......", "......."],
}

# Balão SÓ pro que o corpo não conta sozinho. Trabalhar já se lê pela
# ferramenta na mão e pelo lugar onde a pessoa está; andar e ficar à toa se
# leem pelo movimento. Colocar balão em tudo (a primeira versão fazia isso)
# cobre a colônia de caixinhas pretas e o olho para de distinguir o que importa.
const BUBBLE_ICONS := {
	Villager.STATE_EATING: "eat",
	Villager.STATE_RESTING: "rest",
	Villager.STATE_SOCIALIZING: "chat",
	Villager.STATE_CELEBRATING: "party",
	Villager.STATE_BUILDING: "build",
}

const BUBBLE_TINTS := {
	"work": Color("ffd166"),
	"eat": Color("8fd17a"),
	"rest": Color("c58fff"),
	"chat": Color("9fd0ff"),
	"haul": Color("d8a45c"),
	"build": Color("ff9f6e"),
	"party": Color("ffe08a"),
	"study": Color("7ab8f0"),
}

static func shadow_texture() -> Texture2D:
	if _shadow_texture == null:
		var w := 14
		var h := 6
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var d := Vector2((x - (w - 1) * 0.5) / (w * 0.5), (y - (h - 1) * 0.5) / (h * 0.5)).length()
				if d <= 1.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0.30 * (1.0 - d * 0.55)))
		_shadow_texture = ImageTexture.create_from_image(img)
	return _shadow_texture

static func bubble_texture() -> Texture2D:
	if _bubble_texture == null:
		var w := 11
		var h := 12
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var body := Color(0.07, 0.08, 0.12, 0.86)
		for y in 9:
			for x in w:
				var corner: bool = (x == 0 or x == w - 1) and (y == 0 or y == 8)
				if not corner:
					img.set_pixel(x, y, body)
		# rabinho apontando pra cabeça
		img.set_pixel(4, 9, body)
		img.set_pixel(5, 9, body)
		img.set_pixel(5, 10, body)
		_bubble_texture = ImageTexture.create_from_image(img)
	return _bubble_texture

static func glyph_texture(name: String) -> Texture2D:
	if not _glyphs.has(name):
		var art: Array = GLYPH_ART.get(name, GLYPH_ART["work"])
		var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
		for y in art.size():
			var row: String = art[y]
			for x in row.length():
				if row[x] == "#":
					img.set_pixel(x, y, Color.WHITE)
		_glyphs[name] = ImageTexture.create_from_image(img)
	return _glyphs[name]

# Comida na mão de quem está comendo e livro na mão de quem estuda: 4×4 e 6×5,
# desenhados aqui porque nenhum tile do pack tem esses objetos nesse tamanho —
# e sem eles "comendo" e "lendo" viram a mesma pose de braço levantado.
static func food_texture() -> Texture2D:
	if not _glyphs.has("__food"):
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		var flesh := Color("c9482f")
		for y in 4:
			for x in 4:
				img.set_pixel(x, y, flesh)
		img.set_pixel(0, 0, Color(0, 0, 0, 0))
		img.set_pixel(3, 0, Color("6ea84c"))
		_glyphs["__food"] = ImageTexture.create_from_image(img)
	return _glyphs["__food"]

static func crate_texture() -> Texture2D:
	if not _glyphs.has("__crate"):
		var art := ["#####", "#.#.#", "#####", "#.#.#", "#####"]
		var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
		for y in art.size():
			var row: String = art[y]
			for x in row.length():
				img.set_pixel(x, y, Color("8a6238") if row[x] == "#" else Color("5a3d24"))
		_glyphs["__crate"] = ImageTexture.create_from_image(img)
	return _glyphs["__crate"]

static func book_texture() -> Texture2D:
	if not _glyphs.has("__book"):
		var art := ["##.##", "#####", "#####", "#####", "##.##"]
		var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
		for y in art.size():
			var row: String = art[y]
			for x in row.length():
				if row[x] == "#":
					img.set_pixel(x, y, Color("d9cfae") if x != 2 else Color("8a6a3c"))
		_glyphs["__book"] = ImageTexture.create_from_image(img)
	return _glyphs["__book"]

# ---- construção ----

static func create(v: Villager, char_texture: Texture2D, town_texture: Texture2D) -> VillagerView:
	var view := VillagerView.new()
	view.villager_id = v.id
	view._build(v, char_texture, town_texture)
	return view

func _build(v: Villager, char_texture: Texture2D, town_texture: Texture2D) -> void:
	_body_texture = VillagerArt.bake_body(v.look)
	_face_texture = VillagerArt.bake_face(v.look)

	_shadow = Sprite2D.new()
	_shadow.name = "Sombra"
	_shadow.texture = shadow_texture()
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.scale = Vector2(SCALE, SCALE)
	_shadow.position = Vector2(0, -2)
	add_child(_shadow)

	_flip = Node2D.new()
	_flip.name = "Frente"
	add_child(_flip)

	# Ordem de desenho de trás pra frente. A cabeça por último pra o cabelo
	# cair sobre os ombros; as pernas depois do tronco pra o quadril ficar
	# parado enquanto o passo desliza.
	_add_part("tronco", VillagerArt.PART_TORSO)
	_add_part("braco_e", VillagerArt.PART_ARM_LEFT)
	_add_part("braco_d", VillagerArt.PART_ARM_RIGHT)
	_add_part("perna_e", VillagerArt.PART_LEG_LEFT)
	_add_part("perna_d", VillagerArt.PART_LEG_RIGHT)
	_add_part("cabeca", VillagerArt.PART_HEAD)

	_face = Sprite2D.new()
	_face.name = "Rosto"
	_face.texture = _face_texture
	_face.region_enabled = true
	_face.region_rect = _face_rect(VillagerArt.EXPR_NEUTRAL, VillagerArt.FACE_FRONT)
	_face.centered = false
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Filho da cabeça: quando a cabeça balança, a cara vai junto.
	_parts["cabeca"].add_child(_face)

	_hand = Node2D.new()
	_hand.name = "Mao"
	_hand.position = (HAND - ANCHOR) * SCALE
	_flip.add_child(_hand)

	_tool = Sprite2D.new()
	_tool.name = "Ferramenta"
	_tool.texture = char_texture
	_tool.region_enabled = true
	_tool.centered = false
	_tool.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tool.scale = Vector2(SCALE, SCALE)
	_tool.visible = false
	_hand.add_child(_tool)

	_held = Sprite2D.new()
	_held.name = "NaMao"
	_held.centered = true
	_held.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held.scale = Vector2(SCALE, SCALE)
	_held.visible = false
	_flip.add_child(_held)

	_cargo = Sprite2D.new()
	_cargo.name = "Carga"
	_cargo.texture = town_texture
	_cargo.region_enabled = true
	_cargo.region_rect = Rect2(10 * 16, 8 * 16, 16, 16)
	_cargo.centered = true
	_cargo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cargo.scale = Vector2(2, 2)
	_cargo.position = Vector2(0, -58)
	_cargo.visible = false
	add_child(_cargo)

	_bubble = Node2D.new()
	_bubble.name = "Balao"
	_bubble.position = Vector2(9, -62)
	_bubble.visible = false
	add_child(_bubble)

	var back := Sprite2D.new()
	back.texture = bubble_texture()
	back.centered = false
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.scale = Vector2(2, 2)
	back.position = Vector2(-11, -22)
	_bubble.add_child(back)

	_bubble_icon = Sprite2D.new()
	_bubble_icon.texture = glyph_texture("work")
	_bubble_icon.centered = false
	_bubble_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bubble_icon.scale = Vector2(2, 2)
	_bubble_icon.position = Vector2(-7, -20)
	_bubble.add_child(_bubble_icon)

	_apply_facing(v.facing)

func _add_part(part_name: String, rect: Rect2i) -> void:
	var sprite := Sprite2D.new()
	sprite.name = part_name
	sprite.texture = _body_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(SCALE, SCALE)
	var base: Vector2 = (Vector2(rect.position) - ANCHOR) * SCALE
	sprite.position = base
	_base_positions[part_name] = base
	_parts[part_name] = sprite
	_flip.add_child(sprite)

func _face_rect(expr: int, view: int) -> Rect2:
	var region := VillagerArt.face_region(expr, view)
	return Rect2(region.position.x, region.position.y, region.size.x, region.size.y)

func _part_rect(part_name: String) -> Rect2i:
	match part_name:
		"cabeca": return VillagerArt.PART_HEAD
		"tronco": return VillagerArt.PART_TORSO
		"braco_e": return VillagerArt.PART_ARM_LEFT
		"braco_d": return VillagerArt.PART_ARM_RIGHT
		"perna_e": return VillagerArt.PART_LEG_LEFT
		_: return VillagerArt.PART_LEG_RIGHT

# ---- direção ----

func _apply_facing(facing: int) -> void:
	var pose: int = VillagerArt.POSE_BACK if facing == Villager.DIR_NORTH else VillagerArt.POSE_FRONT
	if pose != _pose:
		_pose = pose
		var shift := VillagerArt.pose_offset(pose)
		for part_name in _parts:
			var rect := _part_rect(part_name)
			_parts[part_name].region_rect = Rect2(rect.position.x + shift, rect.position.y, rect.size.x, rect.size.y)

	var sideways: bool = facing == Villager.DIR_EAST or facing == Villager.DIR_WEST
	_flip.scale.x = -1.0 if facing == Villager.DIR_WEST else 1.0
	# De perfil o braço de trás some e o de frente vem pro meio: é isso que
	# estreita a silhueta e faz o morador parecer virado de lado, não de frente.
	_parts["braco_e"].visible = not sideways
	_face.visible = facing != Villager.DIR_NORTH
	_hand.position = (HAND - ANCHOR) * SCALE + (Vector2(-2, 0) * SCALE if sideways else Vector2.ZERO)

# ---- animação ----

func sync(v: Villager) -> void:
	position = v.position
	_apply_facing(v.facing)

	var offsets := _pose_offsets(v)
	var sideways: bool = v.facing == Villager.DIR_EAST or v.facing == Villager.DIR_WEST
	if sideways:
		# De perfil não basta esconder o braço de trás: a cabeça avança na
		# direção do olhar e o braço da frente vem pro meio do corpo. Sem esses
		# dois pixels a silhueta continua sendo a de alguém de frente.
		offsets["cabeca"] = offsets.get("cabeca", Vector2.ZERO) + Vector2(1, 0)
		offsets["braco_d"] = offsets.get("braco_d", Vector2.ZERO) + Vector2(-2, 0)
		offsets["perna_d"] = offsets.get("perna_d", Vector2.ZERO) + Vector2(-2, 0)

	for part_name in _parts:
		var offset: Vector2 = offsets.get(part_name, Vector2.ZERO)
		_parts[part_name].position = _base_positions[part_name] + offset * SCALE

	_face.region_rect = _face_rect(
		VillagerArt.expression_for(v.state, v.hunger, v.energy, v.mood, _is_blinking(v)),
		VillagerArt.FACE_SIDE if sideways else VillagerArt.FACE_FRONT
	)
	# A cara acompanha a cabeça: como o rosto é filho dela, basta o deslocamento
	# da cabeça já aplicado acima.

	_apply_tool(v, offsets)
	_apply_cargo(v)
	_apply_bubble(v)

	# Humor baixo escurece um pouco quem está mal, sem trocar as cores da arte:
	# dá pra varrer a colônia com o olho e ver que tem gente sofrendo.
	var gloom: float = clampf(1.0 - v.mood, 0.0, 1.0)
	_flip.modulate = Color.WHITE.lerp(Color("6c6a72"), gloom * 0.55)

func _is_blinking(v: Villager) -> bool:
	# Piscada curta a cada ~4s, cada um no seu tempo (anim_phase é sorteada no
	# nascimento) — todo mundo piscando junto entrega que são bonecos.
	return fmod(v.anim_phase, 4.3) < 0.14

# Devolve o deslocamento de cada parte, em pixels do tile. Inteiro de propósito:
# meio pixel com filtro nearest faz o sprite tremer.
func _pose_offsets(v: Villager) -> Dictionary:
	match v.state:
		Villager.STATE_WALKING:
			return _walk_offsets(v)
		Villager.STATE_WORKING:
			return _work_offsets(v)
		Villager.STATE_BUILDING:
			return _work_offsets(v, "craft", 0.55)
		Villager.STATE_EATING:
			return _eat_offsets(v)
		Villager.STATE_RESTING:
			return _rest_offsets(v)
		Villager.STATE_SOCIALIZING:
			return _talk_offsets(v)
		Villager.STATE_CELEBRATING:
			return _cheer_offsets(v)
		_:
			return _idle_offsets(v)

# Ciclo de 4 quadros: passada, passagem, passada oposta, passagem. O quadril
# (que mora no tronco) fica parado enquanto as pernas deslizam, e o corpo sobe
# 1px na passagem — é o repique que faz o andar parecer andar.
func _walk_offsets(v: Villager) -> Dictionary:
	var cadence: float = maxf(0.35, v.speed / BASE_SPEED)
	var frame: int = int(v.anim_phase / (WALK_FRAME / cadence)) % 4
	var carrying: bool = v.carrying != ""
	var arms_up := Vector2(0, -2) if carrying else Vector2.ZERO
	match frame:
		0:
			return {"perna_e": Vector2(-1, 0), "perna_d": Vector2(1, 0),
				"braco_e": arms_up + Vector2(0, 1), "braco_d": arms_up + Vector2(0, -1)}
		2:
			return {"perna_e": Vector2(1, 0), "perna_d": Vector2(-1, 0),
				"braco_e": arms_up + Vector2(0, -1), "braco_d": arms_up + Vector2(0, 1)}
		_:
			return {"cabeca": Vector2(0, -1), "tronco": Vector2(0, -1),
				"braco_e": arms_up + Vector2(0, -1), "braco_d": arms_up + Vector2(0, -1)}

# Trabalhar não é uma postura só: quem racha lenha levanta o machado acima da
# cabeça e desce com o corpo junto; quem lê balança a cabeça sobre o livro.
func _work_offsets(v: Villager, forced_kind: String = "", speed_scale: float = 1.0) -> Dictionary:
	var kind: String = forced_kind if forced_kind != "" else _work_kind
	var cycle: float = 0.9 * speed_scale
	var t: float = fmod(v.anim_phase, cycle) / cycle

	match kind:
		"study":
			# Leitura: sem golpe, só a cabeça descendo e subindo sobre o livro.
			var nod: int = 1 if fmod(v.anim_phase, 2.6) < 1.3 else 0
			return {"cabeca": Vector2(0, nod), "braco_e": Vector2(0, -1), "braco_d": Vector2(0, -1)}
		"trade":
			var sway: int = 1 if fmod(v.anim_phase, 1.6) < 0.8 else 0
			return {"cabeca": Vector2(sway, 0), "tronco": Vector2(sway, 0),
				"braco_e": Vector2(0, -2), "braco_d": Vector2(0, -2)}
		"farm":
			# Enxada: arco baixo e largo, o corpo acompanha o movimento.
			if t < 0.45:
				return {"cabeca": Vector2(0, -1), "tronco": Vector2(0, -1),
					"braco_e": Vector2(0, -2), "braco_d": Vector2(0, -2)}
			return {"cabeca": Vector2(0, 1), "tronco": Vector2(0, 1),
				"braco_e": Vector2(0, 1), "braco_d": Vector2(0, 1)}
		_:
			# Machado / picareta / martelo: levanta, segura, desce forte, recupera.
			if t < 0.30:
				return {"cabeca": Vector2(0, -1), "tronco": Vector2(0, -1),
					"braco_e": Vector2(0, -3), "braco_d": Vector2(0, -3)}
			if t < 0.45:
				return {"cabeca": Vector2(0, -1), "tronco": Vector2(0, -1),
					"braco_e": Vector2(0, -4), "braco_d": Vector2(0, -4)}
			if t < 0.62:
				return {"cabeca": Vector2(0, 2), "tronco": Vector2(0, 1),
					"braco_e": Vector2(0, 1), "braco_d": Vector2(0, 1)}
			return {"cabeca": Vector2(0, 1), "tronco": Vector2(0, 0),
				"braco_e": Vector2(0, -1), "braco_d": Vector2(0, -1)}

func _eat_offsets(v: Villager) -> Dictionary:
	# A mão sobe até a boca e volta; a cabeça desce um pouco pra encontrar ela.
	var up: bool = fmod(v.anim_phase, 0.8) < 0.4
	return {
		"cabeca": Vector2(0, 1 if up else 0),
		"braco_d": Vector2(0, -3 if up else 0),
		"braco_e": Vector2(0, 1),
	}

func _rest_offsets(v: Villager) -> Dictionary:
	# Sentado: o corpo inteiro desce e as pernas se recolhem pra dentro.
	var breath: int = 1 if fmod(v.anim_phase, 3.2) < 1.6 else 0
	return {
		"cabeca": Vector2(0, 4 - breath), "tronco": Vector2(0, 4 - breath),
		"braco_e": Vector2(1, 4), "braco_d": Vector2(-1, 4),
		"perna_e": Vector2(1, 1), "perna_d": Vector2(-1, 1),
	}

func _talk_offsets(v: Villager) -> Dictionary:
	# Gesticula com uma mão só, e a cabeça acompanha a fala.
	var beat: float = fmod(v.anim_phase, 1.2)
	var raised: bool = beat < 0.35
	var tilt: int = 1 if beat > 0.7 else 0
	return {
		"braco_d": Vector2(0, -3 if raised else -1),
		"cabeca": Vector2(tilt, 0),
	}

func _cheer_offsets(v: Villager) -> Dictionary:
	# Pulinho: os dois braços pra cima e o corpo inteiro fora do chão.
	var hop: int = -3 if fmod(v.anim_phase, 0.5) < 0.25 else 0
	return {
		"cabeca": Vector2(0, hop - 1), "tronco": Vector2(0, hop),
		"braco_e": Vector2(0, hop - 4), "braco_d": Vector2(0, hop - 4),
		"perna_e": Vector2(-1, hop), "perna_d": Vector2(1, hop),
	}

func _idle_offsets(v: Villager) -> Dictionary:
	# Respiração: o tronco e a cabeça sobem 1px por metade do ciclo. É pouco de
	# propósito — parado tem que parecer parado, só não morto.
	var breath: int = -1 if fmod(v.anim_phase, 2.6) < 1.3 else 0
	return {"cabeca": Vector2(0, breath), "tronco": Vector2(0, breath)}

func set_work_kind(kind: String) -> void:
	_work_kind = kind

func _apply_tool(v: Villager, offsets: Dictionary) -> void:
	_apply_held(v, offsets)
	var showing: bool = v.state == Villager.STATE_WORKING or v.state == Villager.STATE_BUILDING
	var kind: String = "craft" if v.state == Villager.STATE_BUILDING else _work_kind
	var coord: Vector2i = VillagerArt.TOOL_TILES.get(kind, Vector2i(-1, -1))
	if not showing or coord.x < 0:
		_tool.visible = false
		return
	_tool.visible = true
	_tool.region_rect = Rect2(coord.x * (VillagerArt.TILE + VillagerArt.MARGIN), coord.y * (VillagerArt.TILE + VillagerArt.MARGIN), VillagerArt.TILE, VillagerArt.TILE)
	var grip: Vector2 = TOOL_GRIP.get(kind, Vector2(1.5, 11.5))
	_tool.position = -grip * SCALE
	# A mão segue o braço: sem isto a ferramenta fica flutuando enquanto o
	# braço sobe, e a leitura de "está batendo com aquilo" se perde.
	var arm: Vector2 = offsets.get("braco_d", Vector2.ZERO)
	_hand.position = (HAND - ANCHOR + arm) * SCALE
	if v.facing == Villager.DIR_EAST or v.facing == Villager.DIR_WEST:
		_hand.position += Vector2(-2, 0) * SCALE
	_hand.rotation = _tool_angle(v, kind)

# O giro da ferramenta é contínuo (não em quadros): é o que faz a machadada
# parecer uma machadada e não dois desenhos alternando. O arco para antes da
# vertical — passando disso, a 48px de altura a ferramenta cobre a cabeça e o
# morador vira um borrão cinza empunhando alguma coisa.
func _tool_angle(v: Villager, kind: String) -> float:
	var cycle: float = 0.55 if v.state == Villager.STATE_BUILDING else 0.9
	var t: float = fmod(v.anim_phase, cycle) / cycle
	# Ângulo positivo = ponta pra direita (a mão é a direita). O arco vive
	# nesse lado: passando de zero pra esquerda, a ferramenta atravessa o
	# tronco e o morador some atrás dela.
	match kind:
		"farm":
			return lerpf(0.15, 1.5, sin(t * TAU) * 0.5 + 0.5)
		"craft":
			return lerpf(0.2, 1.35, absf(sin(t * TAU)))
		_:
			if t < 0.45:
				return lerpf(0.5, -0.35, t / 0.45)     # arma o golpe acima do ombro
			return lerpf(-0.35, 1.6, (t - 0.45) / 0.55)  # desce em arco pra frente

# Objeto pequeno na mão: a maçã de quem come, o livro de quem estuda. Sem isto
# "comendo" e "lendo" ficam sendo o mesmo braço levantado.
func _apply_held(v: Villager, offsets: Dictionary) -> void:
	var arm: Vector2 = offsets.get("braco_d", Vector2.ZERO)
	if v.state == Villager.STATE_EATING:
		_held.visible = true
		_held.texture = food_texture()
		_held.position = (Vector2(11.0, 9.0) - ANCHOR + arm) * SCALE
	elif v.state == Villager.STATE_WORKING and _work_kind == "study":
		_held.visible = true
		_held.texture = book_texture()
		_held.position = (Vector2(8.0, 10.5) - ANCHOR + arm) * SCALE
	elif v.state == Villager.STATE_WORKING and _work_kind == "trade":
		# Quem trabalha no mercado não bate em nada: fica com um caixote no colo.
		_held.visible = true
		_held.texture = crate_texture()
		_held.position = (Vector2(8.0, 10.0) - ANCHOR + arm) * SCALE
	else:
		_held.visible = false

func _apply_cargo(v: Villager) -> void:
	if v.carrying == "":
		_cargo.visible = false
		return
	_cargo.visible = true
	_cargo.modulate = RESOURCE_COLORS.get(v.carrying, Color.WHITE)
	# Sobe e desce de leve junto com o passo: caixa colada na cabeça parece adesivo.
	var bob: float = -58.0 + (0.0 if int(v.anim_phase / (WALK_FRAME * 2.0)) % 2 == 0 else 2.0)
	_cargo.position = Vector2(0, bob)

func _apply_bubble(v: Villager) -> void:
	# Carregar carga já aparece pela caixa acima da cabeça — balão em cima
	# disso seria dizer a mesma coisa duas vezes.
	var icon: String = String(BUBBLE_ICONS.get(v.state, "")) if v.carrying == "" else ""
	if icon == "":
		_bubble.visible = false
		return
	_bubble.visible = true
	_bubble_icon.texture = glyph_texture(icon)
	_bubble_icon.modulate = BUBBLE_TINTS.get(icon, Color.WHITE)
	# O balão não espelha junto com o corpo: texto/ícone de cabeça pra trás.
	_bubble.position = Vector2(9 if v.facing != Villager.DIR_WEST else -9, -60)
