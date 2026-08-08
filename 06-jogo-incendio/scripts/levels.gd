class_name Levels
extends RefCounted

# As fases, escritas como mapa ASCII — mesma ideia que salvou o Projeto 3: uma
# fase é DADO, não código, então dá pra ler o vale inteiro de bater o olho, dá
# pra editar sem abrir o editor, e dá pra um bot jogá-la nos testes. Se um mapa
# novo ficar impossível (ou trivial), a suíte reclama antes de alguém jogar.
#
# ---- o alfabeto ----
#
#   .  capim      ,  mato       T  mata      H  casa
#   =  lavoura    _  terra      #  rocha     ~  água
#   *  foco inicial do incêndio (fica sobre capim)
#   P  morador a evacuar (sobre capim)
#   B  brigadista (sobre capim)
#   E  abrigo: onde os moradores estão salvos (é terra batida)
#
# ---- o arco das seis fases ----
#
# Cada fase existe pra ensinar UMA regra do sistema, e a seguinte cobra que a
# anterior tenha sido entendida:
#
#   1. cavar aceiro fecha uma passagem
#   2. o vento decide qual lado queima primeiro
#   3. fogo sobe morro muito mais rápido do que desce
#   4. água apaga e protege — mas acaba
#   5. com vento forte a brasa PULA o aceiro
#   6. contra o fogo grande, o jeito é gastar o combustível antes: contra-fogo
#
# `heights` é opcional: sem ele o vale é plano. Cada dígito é um degrau, e a
# FireSim cobra 55% mais propagação por degrau de subida.

const ALL := [
	{
		"id": "garganta",
		"name": "A garganta",
		"brief": "Fogo no capim, sem vento. Entre ele e as casas o vale se estreita — feche a passagem com aceiro.",
		"teaches": "Cavar aceiro tira o combustível. Sem combustível o fogo para.",
		"map": [
			"####################################",
			"#......,,......###.................#",
			"#..............###...........B.....#",
			"#...*..........###.......H.........#",
			"#..*,,.........###.................#",
			"#...*..................H...H.......#",
			"#.................................B#",
			"#.........,,.......................#",
			"#........B.........................#",
			"#..............~~~~................#",
			"#....,,........~~~~................#",
			"#..............~~~~................#",
			"#..............~~~~......,,........#",
			"####################################",
		],
		"wind": {"angle_deg": 0.0, "force": 0.0, "swing_deg": 0.0, "period": 24.0},
		"seed": 1001,
		"goal_houses": 3,
		"budget": {"water": 2, "backfire": 0},
		"par_time": 180.0,
	},
	{
		"id": "vento",
		"name": "O vento manda",
		"brief": "Vento forte de oeste. As duas aldeias não podem ser defendidas ao mesmo tempo — escolha pela bússola.",
		"teaches": "A favor do vento o fogo anda 2,5× mais rápido; contra, quase para.",
		"map": [
			"########################################",
			"#....,,.....................H..H.......#",
			"#..........###.............H....B......#",
			"#...*......###......,,.................#",
			"#..*,......###.........................#",
			"#...*...........,,.....................#",
			"#..................................,,..#",
			"#........,,............................#",
			"#...............TTT....................#",
			"#..............TTTTT...........B.......#",
			"#...............TTT......H.....H.......#",
			"#.....,,.................H.............#",
			"#..............~~~~....................#",
			"#..............~~~~.......,,...........#",
			"#..........B...........................#",
			"########################################",
		],
		"wind": {"angle_deg": -18.0, "force": 0.45, "swing_deg": 10.0, "period": 30.0},
		"seed": 1002,
		"goal_houses": 3,
		"budget": {"water": 3, "backfire": 0},
		"par_time": 240.0,
	},
	{
		"id": "encosta",
		"name": "A encosta",
		"brief": "O povoado fica no alto e o fogo começou no sopé. Morro acima ele voa.",
		"teaches": "Relevo: subida acelera o fogo, descida segura. Corte a encosta, não o topo.",
		"map": [
			"##########################################",
			"#....,,.................,,,,,,,..........#",
			"#.......................,,H,,H,....B.....#",
			"#...........,,..........,,H,,H,..........#",
			"#........................,,,,,...........#",
			"#..........................,,......B.....#",
			"#.....,,.........TTT.....................#",
			"#................TTT.............,,......#",
			"#........,,......TTT.....................#",
			"#..............,,........,,..............#",
			"#...*..................,,................#",
			"#..*,,...........,,...............B......#",
			"#...*.................,,.................#",
			"#........................,,..............#",
			"#..~~~~..................................#",
			"#..~~~~........,,........................#",
			"#........................................#",
			"##########################################",
		],
		"heights": [
			"000000000000000000000000000000000000000000",
			"000000000000000000000226777776221000000000",
			"000000000000000000000226777776221000000000",
			"000000000000000000000226777776221000000000",
			"000000000000000000000225666665221000000000",
			"000000000000000000000114555554211000000000",
			"000000000000000000000113444443211000000000",
			"000000000000000000000112333332111000000000",
			"000000000000000000000111222221110000000000",
			"000000000000000000000011111111000000000000",
			"000000000000000000000001111110000000000000",
			"000000000000000000000000000000000000000000",
			"000000000000000000000000000000000000000000",
			"000000000000000000000000000000000000000000",
			"000000000000000000000000000000000000000000",
			"000000000000000000000000000000000000000000",
			"000000000000000000000000000000000000000000",
			"000000000000000000000000000000000000000000",
		],
		"wind": {"angle_deg": -35.0, "force": 0.35, "swing_deg": 14.0, "period": 26.0},
		"seed": 1003,
		"goal_houses": 3,
		"budget": {"water": 3, "backfire": 0},
		"par_time": 260.0,
	},
	{
		"id": "sede",
		"name": "Sede",
		"brief": "Um rastilho de mato seco corre do foco até o povoado, e ainda há gente no vale.",
		"teaches": "Água apaga chama acesa e molha o que ainda não pegou — mas cada balde é único.",
		"map": [
			"##########################################",
			"#....EE..................................#",
			"#....EE.....P............................#",
			"#........................................#",
			"#........B...............................#",
			"#........................,,,,,,..........#",
			"#.......................,,H,H,H,.........#",
			"#.......................,,,,,,,,.........#",
			"#.......P...............,,,,,,...........#",
			"#....................,,,,................#",
			"#.................,,,,..............EE...#",
			"#..............,,,,........B........EE...#",
			"#...........,,,,.........................#",
			"#........,,,,............................#",
			"#....*,,,................................#",
			"#...*,,..................P...............#",
			"#....*..........B........................#",
			"##########################################",
		],
		"wind": {"angle_deg": -62.0, "force": 0.42, "swing_deg": 12.0, "period": 22.0},
		"seed": 1004,
		"goal_houses": 2,
		"budget": {"water": 8, "backfire": 0},
		"par_time": 280.0,
	},
	{
		"id": "brasas",
		"name": "Brasas",
		"brief": "Vendaval. A chama joga brasa longe e o aceiro de uma cava não segura mais nada.",
		"teaches": "Com vento forte a brasa PULA a barreira. Cave largo, ou molhe o outro lado.",
		"map": [
			"##############################################",
			"#....,,.........,,........................,,.#",
			"#........P.............,,....................#",
			"#...*.........TTT..........H....H............#",
			"#..*,,........TTTTT.......H..H..H............#",
			"#...*..........TTT.............H.............#",
			"#..*,...............,,.......................#",
			"#...*........................................#",
			"#.......,,..........B........................#",
			"#..............###...........P...............#",
			"#..............###.....,,....................#",
			"#..............###..........B................#",
			"#.......,,.....###...........,,..............#",
			"#..............###...........................#",
			"#....P.........###.................EE........#",
			"#......................,,..........EE........#",
			"#.........,,.........B.......................#",
			"#..............~~~~..........................#",
			"#..............~~~~.........,,...............#",
			"##############################################",
		],
		"wind": {"angle_deg": -8.0, "force": 0.7, "swing_deg": 8.0, "period": 20.0},
		"seed": 1005,
		"goal_houses": 3,
		"budget": {"water": 6, "backfire": 2},
		"par_time": 300.0,
	},
	{
		"id": "contrafogo",
		"name": "Contra-fogo",
		"brief": "A frente é larga demais e vem depressa. Não há aceiro que se cave a tempo.",
		"teaches": "Fogo contra fogo: queime o combustível você mesmo, enquanto ainda escolhe onde.",
		"map": [
			"################################################",
			"#..*,,......======.............................#",
			"#...*.......======...........,,................#",
			"#..*,,......======.....................H.......#",
			"#...*.......======............P.......H.H......#",
			"#..*,,......======.....................H.......#",
			"#...*.......======.............................#",
			"#..*,,......======........TTT..................#",
			"#...*.......======.......TTTTT.................#",
			"#..*,,......======........TTT..................#",
			"#...*.......======.............................#",
			"#..*,,......======.............P...............#",
			"#...*.......======.............................#",
			"#..*,,......======.............................#",
			"#...........======.........,,..........B.......#",
			"#......,,...................................B..#",
			"#..........................EE..................#",
			"#..........................EE..................#",
			"#....,,...............B........................#",
			"#.................,,..........B................#",
			"#..............~~~~............................#",
			"################################################",
		],
		"wind": {"angle_deg": 0.0, "force": 0.6, "swing_deg": 6.0, "period": 28.0},
		"seed": 1006,
		"goal_houses": 3,
		"budget": {"water": 4, "backfire": 6},
		"par_time": 320.0,
	},
]

# ---- leitura ----

class Parsed extends RefCounted:
	var cols := 0
	var rows := 0
	var kinds := PackedInt32Array()
	var heights := PackedFloat32Array()
	var ignitions: Array = []      # Vector2i
	var civilians: Array = []      # Vector2i
	var crew: Array = []           # Vector2i
	var shelters: Array = []       # Vector2i
	var houses_total := 0

static func count() -> int:
	return ALL.size()

static func get_level(index: int) -> Dictionary:
	return ALL[clampi(index, 0, ALL.size() - 1)]

# Transforma o ASCII em grades. As entidades (*, P, B, E) não são terreno: cada
# uma vira uma posição na lista correspondente e deixa no lugar dela o chão que
# faz sentido — capim pra gente e pro foco, terra batida pro abrigo (um abrigo
# que pegasse fogo não seria abrigo).
static func parse(level: Dictionary) -> Parsed:
	var out := Parsed.new()
	var lines: Array = level["map"]
	out.rows = lines.size()
	out.cols = String(lines[0]).length()
	var n := out.cols * out.rows
	out.kinds.resize(n)
	out.heights.resize(n)

	var height_lines: Array = level.get("heights", [])
	for y in out.rows:
		var line: String = lines[y]
		var height_line: String = String(height_lines[y]) if y < height_lines.size() else ""
		for x in out.cols:
			var idx := y * out.cols + x
			var c := line.substr(x, 1)
			match c:
				"*":
					out.kinds[idx] = Terrain.GRASS
					out.ignitions.append(Vector2i(x, y))
				"P":
					out.kinds[idx] = Terrain.GRASS
					out.civilians.append(Vector2i(x, y))
				"B":
					out.kinds[idx] = Terrain.GRASS
					out.crew.append(Vector2i(x, y))
				"E":
					out.kinds[idx] = Terrain.DIRT
					out.shelters.append(Vector2i(x, y))
				_:
					out.kinds[idx] = Terrain.from_char(c)
			if out.kinds[idx] == Terrain.HOUSE:
				out.houses_total += 1
			var digit := height_line.substr(x, 1) if x < height_line.length() else ""
			out.heights[idx] = float(digit.to_int()) if digit != "" else 0.0
	return out

# Monta uma FireSim já com vento, relevo e focos da fase. Um lugar só pra isso
# porque o jogo, os testes e o bot precisam montar exatamente a mesma partida.
static func build_sim(level: Dictionary) -> FireSim:
	var parsed := parse(level)
	var sim := FireSim.new()
	sim.setup(parsed.cols, parsed.rows, parsed.kinds, parsed.heights, int(level.get("seed", 1)))
	var wind: Dictionary = level.get("wind", {})
	sim.set_wind(
		deg_to_rad(float(wind.get("angle_deg", 0.0))),
		float(wind.get("force", 0.0)),
		deg_to_rad(float(wind.get("swing_deg", 0.0))),
		float(wind.get("period", 24.0))
	)
	for cell in parsed.ignitions:
		sim.ignite(cell.x, cell.y)
	return sim
