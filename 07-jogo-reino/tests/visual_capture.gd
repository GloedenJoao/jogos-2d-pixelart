extends SceneTree

# Captura automática de tela — mesmo método usado nos outros
# projetos do repositório (ver memória "validação visual automatizada"):
# instancia a cena de verdade, força o estado por código, e salva o quadro
# em vez de abrir o editor e clicar.
#
# Rodar SEM --headless (precisa de renderização de verdade pra ler a textura
# do viewport):
#   Godot... --path 07-jogo-reino --script tests/visual_capture.gd

const OUT_DIR := "res://.visual_capture"

func _initialize() -> void:
	await process_frame
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# A vila nasce PEQUENA de propósito (Armazém + Fazenda + uma Casa) — o
	# resto do catálogo é escolha do jogador via menu de construção
	# (painel no canto superior direito), não mais automático por nível.
	await _capture("01_vila_inicial", main)

	# Demonstra o modo de construção: arma o modo pra Posto de Lenhador e
	# posiciona o quadrado-fantasma numa célula de floresta de verdade (sem
	# mouse real pra mover neste script offscreen, então o teste monta o
	# mesmo estado que `_update_ghost` montaria) — verde porque a célula é
	# válida.
	var forest_cell := Buildings.nearest_deposit_cell(main.map, MapGen.Kind.FOREST, main._village_cell, main.BUILDING_SEARCH_RADIUS)
	if forest_cell.x >= 0:
		main._placing_kind = Buildings.Kind.LUMBERJACK
		main._ghost.visible = true
		main._ghost.position = Vector2(forest_cell) * float(main.CELL)
		main._ghost.color = Color(0.3, 1.0, 0.3, 0.45)
		main._build_status_label.text = "Construindo Posto de Lenhador — clique num local válido (Esc cancela)"
		main.camera.position = Vector2(forest_cell) * float(main.CELL)
		await process_frame
		await _capture("02_modo_de_construcao", main)
		main._cancel_placing()

	# Constrói manualmente o resto do catálogo — simula o jogador clicando
	# em cada botão do painel e depois no mapa. Estoque de sobra só pra este
	# passo (a cadeia de produção de verdade continua sendo testada pelas
	# capturas seguintes, que avançam a simulação de verdade a partir daqui).
	for resource in main.buildings.stock:
		main.buildings.stock[resource] = 99999.0
	if forest_cell.x >= 0:
		main._build(Buildings.Kind.LUMBERJACK, forest_cell)
	var stone_cell := Buildings.nearest_deposit_cell(main.map, MapGen.Kind.STONE, main._village_cell, main.BUILDING_SEARCH_RADIUS)
	if stone_cell.x >= 0:
		main._build(Buildings.Kind.QUARRY, stone_cell)
	var ore_cell := Buildings.nearest_deposit_cell(main.map, MapGen.Kind.HILLS, main._village_cell, main.BUILDING_SEARCH_RADIUS)
	if ore_cell.x >= 0:
		main._build(Buildings.Kind.MINE, ore_cell)
	# Busca em quadrado ao redor da vila a primeira célula onde `_build`
	# funciona — mesma técnica do helper `_build_near` dos testes headless,
	# só que inline aqui (esta cena não precisa desse helper fora de teste).
	for kind in [Buildings.Kind.SAWMILL, Buildings.Kind.STONE_WORKSHOP, Buildings.Kind.GENERATOR, Buildings.Kind.FORGE, Buildings.Kind.WATERWHEEL, Buildings.Kind.WINDMILL, Buildings.Kind.HOUSE, Buildings.Kind.HOUSE]:
		for radius in range(0, main.BUILDING_SEARCH_RADIUS + 1):
			var placed := false
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					var cell: Vector2i = main._village_cell + Vector2i(dx, dy)
					if main._build(kind, cell):
						placed = true
						break
				if placed:
					break
			if placed:
				break

	# Zoom nos prédios + trabalhadores: centraliza entre eles e avança a
	# simulação até a população crescer o bastante pra TODOS os prédios
	# staffáveis ganharem trabalhador e chegarem a WORKING — um único prédio
	# ficar de fora do enquadramento (ou de pé, esperando) foi exatamente o
	# que confundiu o João da primeira vez.
	var unstaffed_kinds := [Buildings.Kind.WAREHOUSE, Buildings.Kind.GENERATOR, Buildings.Kind.STONE_WORKSHOP, Buildings.Kind.HOUSE, Buildings.Kind.WATERWHEEL, Buildings.Kind.WINDMILL]
	var staffable: Array = main.buildings.list.filter(func(b): return not (b.kind in unstaffed_kinds))
	if not main.buildings.list.is_empty():
		var mid := Vector2.ZERO
		for building in main.buildings.list:
			mid += Vector2(building.cell)
		mid = mid / float(main.buildings.list.size()) * float(main.CELL)
		main.camera.zoom = Vector2(1.1, 1.1)
		main.camera.position = mid
		await _capture("03_predios_construidos", main)

		var steps := 0
		# `Array.all()` num array vazio é vácuo (true) — por isso o tamanho
		# entra na condição, senão o loop nem chegaria a rodar um passo.
		while steps < 6000 and (main.workers.list.size() < staffable.size() or not main.workers.list.all(func(w): return w.state == Worker.State.WORKING)):
			main._process(1.0 / 30.0)
			steps += 1
		await process_frame
		await _capture("04_trabalhadores_nos_postos", main)

	# Avança até o carregador completar pelo menos uma entrega de verdade
	# (produzir → coletar → entregar) — é o que separa "pátio cheio" de
	# "estoque que dá pra gastar".
	var before := {}
	for resource in main.buildings.stock:
		before[resource] = main.buildings.stock[resource]
	var steps := 0
	var delivered := false
	while steps < 6000 and not delivered:
		main._process(1.0 / 30.0)
		steps += 1
		for resource in main.buildings.stock:
			if main.buildings.stock[resource] > before.get(resource, 0.0):
				delivered = true
	await process_frame
	await _capture("05_carregador_entregando", main)

	# Avança até a cadeia inteira (extrair → transportar → processar) render
	# tábua E bloco de verdade.
	var got_tabua := false
	var got_bloco := false
	steps = 0
	while steps < 10000 and not (got_tabua and got_bloco):
		main._process(1.0 / 30.0)
		steps += 1
		got_tabua = main.buildings.stock.get("tábua", 0.0) > 0.0
		got_bloco = main.buildings.stock.get("bloco", 0.0) > 0.0
	await process_frame
	await _capture("06_processamento", main)

	# Mina + Forja: terceira cadeia (minério → lingote), mesma técnica de
	# espera do bloco/tábua acima — avança até a Forja render lingote de
	# verdade.
	var got_lingote := false
	steps = 0
	while steps < 10000 and not got_lingote:
		main._process(1.0 / 30.0)
		steps += 1
		got_lingote = main.buildings.stock.get("lingote", 0.0) > 0.0
	await process_frame
	await _capture("07_minerio_e_lingote", main)

	# Fazenda + necessidade de comida: avança até a população passar do piso
	# de arranque (Population.BOOTSTRAP_POPULATION) — só acontece depois que
	# a Fazenda produziu, o carregador entregou, e sobrou comida de verdade
	# no Armazém pra sustentar crescimento além do piso.
	var past_bootstrap := false
	steps = 0
	while steps < 10000 and not past_bootstrap:
		main._process(1.0 / 30.0)
		steps += 1
		past_bootstrap = main.population.count > Population.BOOTSTRAP_POPULATION + 0.5
	await process_frame
	await _capture("08_fazenda_e_comida", main)

	# Afasta a câmera pra ver a vila inteira e avança até ela subir pra
	# nível 2 — o alcance de exploração (raio da névoa) cresce de verdade
	# nesse momento, não é só um número no HUD.
	main.camera.zoom = Vector2(0.9, 0.9)
	main.camera.position = Vector2(main._village_cell) * float(main.CELL)
	steps = 0
	while steps < 6000 and main.progression.level < 2:
		main._process(1.0 / 30.0)
		steps += 1
	await process_frame
	await _capture("09_vila_sobe_de_nivel", main)

	# Explora um pedaço bem longe da vila, pra mostrar a névoa recuando de
	# verdade em vez de só a área que já nasce revelada.
	main._scout_at(Vector2(8, 8) * float(main.CELL))
	main._scout_at(Vector2(50, 32) * float(main.CELL))
	await process_frame
	await _capture("10_depois_de_explorar", main)

	# Afasta a câmera (zoom out) pra ver uma fatia maior do mapa de uma vez —
	# mostra o relevo/depósitos variados que a Fase 1 promete.
	main.camera.zoom = Vector2(main.ZOOM_MIN, main.ZOOM_MIN)
	main.camera.position = Vector2(main.MAP_COLS, main.MAP_ROWS) * float(main.CELL) * 0.5
	await process_frame
	await _capture("11_vista_afastada", main)

	print("capturas salvas em %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _capture(name: String, main: Node) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("capturado: %s" % name)
