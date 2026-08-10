extends SceneTree

# Captura automática de tela da Fase 1 — mesmo método usado nos outros
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

	# Explora um pedaço bem longe da vila, pra mostrar a névoa recuando de
	# verdade em vez de só a área que já nasce revelada.
	main._scout_at(Vector2(8, 8) * float(main.CELL))
	main._scout_at(Vector2(50, 32) * float(main.CELL))
	await process_frame
	await _capture("02_depois_de_explorar", main)

	# Afasta a câmera (zoom out) pra ver uma fatia maior do mapa de uma vez —
	# mostra o relevo/depósitos variados que a Fase 1 promete.
	main.camera.zoom = Vector2(main.ZOOM_MIN, main.ZOOM_MIN)
	main.camera.position = Vector2(main.MAP_COLS, main.MAP_ROWS) * float(main.CELL) * 0.5
	await process_frame
	await _capture("03_vista_afastada", main)

	print("capturas salvas em %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _capture(name: String, main: Node) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("capturado: %s" % name)
