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

	await _capture("01_vila_inicial", main)

	# Zoom nos prédios + trabalhadores (Fase 2): centraliza entre eles e avança
	# a simulação até TODOS os trabalhadores chegarem e começarem a trabalhar
	# — um único prédio ficar de fora do enquadramento (ou de pé, esperando)
	# foi exatamente o que confundiu o João da primeira vez.
	if not main.buildings.list.is_empty():
		var mid := Vector2.ZERO
		for building in main.buildings.list:
			mid += Vector2(building.cell)
		mid = mid / float(main.buildings.list.size()) * float(main.CELL)
		main.camera.zoom = Vector2(1.1, 1.1)
		main.camera.position = mid
		var steps := 0
		while steps < 3000 and not main.workers.list.all(func(w): return w.state == Worker.State.WORKING):
			main._process(1.0 / 30.0)
			steps += 1
		await process_frame
		await _capture("02_trabalhadores_nos_postos", main)

	# Fase 3: avança até o carregador completar pelo menos uma entrega de
	# verdade (produzir → coletar → entregar) — é o que separa "pátio cheio"
	# de "estoque que dá pra gastar".
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
	await _capture("03_carregador_entregando", main)

	# Explora um pedaço bem longe da vila, pra mostrar a névoa recuando de
	# verdade em vez de só a área que já nasce revelada.
	main._scout_at(Vector2(8, 8) * float(main.CELL))
	main._scout_at(Vector2(50, 32) * float(main.CELL))
	await process_frame
	await _capture("04_depois_de_explorar", main)

	# Afasta a câmera (zoom out) pra ver uma fatia maior do mapa de uma vez —
	# mostra o relevo/depósitos variados que a Fase 1 promete.
	main.camera.zoom = Vector2(main.ZOOM_MIN, main.ZOOM_MIN)
	main.camera.position = Vector2(main.MAP_COLS, main.MAP_ROWS) * float(main.CELL) * 0.5
	await process_frame
	await _capture("05_vista_afastada", main)

	print("capturas salvas em %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _capture(name: String, main: Node) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("capturado: %s" % name)
