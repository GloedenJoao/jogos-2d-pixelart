extends SceneTree

# Screenshots automatizados das telas-chave. Roda via:
#   Godot_..._console.exe --path . --script res://tests/visual_capture.gd
# PNGs em res://.visual_capture/ (gitignored), lidos direto com a ferramenta Read.
#
# O V2 acrescentou duas capturas que o V1 não precisava: um close do vale (pra
# conferir animação, direção e rosto, que somem numa captura de tela inteira) e
# uma "prova de elenco" que instancia bonecos direto, fora do jogo, em todos os
# estados e direções. Arte de 16px em escala 3 não dá pra revisar de longe.

const OUT_DIR := "res://.visual_capture"
const SAVE_KEY := "colonia_v2"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	await _capture_elenco()
	await _capture_inicio()
	await _capture_trabalho()
	await _capture_colonia_viva()
	await _capture_close()
	await _capture_colonia_grande()

	print("Capturas salvas em: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase(SAVE_KEY)
	save_system.save_data()

func _new_game() -> Node:
	_reset_save()
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	return instance

func _open_drawer(instance) -> void:
	instance.toggle_drawer()
	instance.drawer.position.x = 1280.0 - instance.DRAWER_WIDTH  # sem esperar a animação

# Avança a simulação de verdade (needs, decisões, caminhada) por N segundos.
# Passo curto: com passo grande a caminhada anda aos saltos e as capturas
# pegam todo mundo no mesmo quadro de animação.
func _simulate(instance, seconds: float, step: float = 0.1) -> void:
	for _i in int(seconds / step):
		instance._process(step)

func _shoot(scenario_name: String) -> void:
	# Frames de verdade antes do clique: partículas (a fumaça das chaminés) só
	# avançam em tempo real, não nos passos simulados por `_simulate`. Com dois
	# frames a chaminé sai sempre vazia na foto.
	for _i in 40:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, scenario_name])
	print("  capturado: %s.png" % scenario_name)

# ---- prova de elenco: os bonecos fora do jogo, grandes e parados ----

func _capture_elenco() -> void:
	var stage := Node2D.new()
	root.add_child(stage)

	var backdrop := ColorRect.new()
	backdrop.color = Color("20222e")
	backdrop.size = Vector2(1280, 720)
	stage.add_child(backdrop)

	var char_texture: Texture2D = load(VillagerArt.SHEET_PATH)
	var town_texture: Texture2D = load("res://assets/town/tilemap_packed.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var states := [
		Villager.STATE_IDLE, Villager.STATE_WALKING, Villager.STATE_WORKING,
		Villager.STATE_EATING, Villager.STATE_RESTING, Villager.STATE_SOCIALIZING,
		Villager.STATE_CELEBRATING, Villager.STATE_BUILDING,
	]
	var work_kinds := ["chop", "mine", "farm", "craft", "study", "trade"]

	# Linha 1-2: variedade de aparência (o mesmo sistema, doze pessoas).
	for i in 12:
		var v := Villager.new(i + 1, "Teste", Vector2.ZERO)
		v.look = VillagerArt.random_look(rng)
		v.anim_phase = float(i) * 0.37
		var view := VillagerView.create(v, char_texture, town_texture)
		view.scale = Vector2(2, 2)
		stage.add_child(view)
		v.position = Vector2(90 + (i % 6) * 130, 150 + int(i / 6) * 170)
		view.sync(v)

	# Linha 3: um estado por boneco.
	for i in states.size():
		var v := Villager.new(100 + i, "Teste", Vector2.ZERO)
		v.look = VillagerArt.random_look(rng)
		v.state = states[i]
		v.anim_phase = 0.2 + i * 0.13
		v.carrying = "materiais" if states[i] == Villager.STATE_WALKING and i == 1 else ""
		var view := VillagerView.create(v, char_texture, town_texture)
		view.scale = Vector2(2, 2)
		view.set_work_kind("chop")
		stage.add_child(view)
		v.position = Vector2(90 + i * 145, 480)
		view.sync(v)

	# Linha 4: direções + ferramentas por ofício + rostos por necessidade.
	var facings := [Villager.DIR_SOUTH, Villager.DIR_EAST, Villager.DIR_NORTH, Villager.DIR_WEST]
	for i in 4:
		var v := Villager.new(200 + i, "Teste", Vector2.ZERO)
		v.look = VillagerArt.random_look(rng)
		v.facing = facings[i]
		v.state = Villager.STATE_WALKING
		v.anim_phase = 0.05
		var view := VillagerView.create(v, char_texture, town_texture)
		view.scale = Vector2(2, 2)
		stage.add_child(view)
		v.position = Vector2(80 + i * 90, 650)
		view.sync(v)
	for i in work_kinds.size():
		var v := Villager.new(300 + i, "Teste", Vector2.ZERO)
		v.look = VillagerArt.random_look(rng)
		v.state = Villager.STATE_WORKING
		v.anim_phase = 0.55
		var view := VillagerView.create(v, char_texture, town_texture)
		view.scale = Vector2(2, 2)
		view.set_work_kind(work_kinds[i])
		stage.add_child(view)
		v.position = Vector2(500 + i * 100, 650)
		view.sync(v)
	var moods := [
		{"hunger": 1.0, "energy": 1.0, "mood": 0.95},
		{"hunger": 0.1, "energy": 0.9, "mood": 0.4},
		{"hunger": 0.9, "energy": 0.1, "mood": 0.4},
		{"hunger": 0.5, "energy": 0.5, "mood": 0.1},
	]
	for i in moods.size():
		var v := Villager.new(400 + i, "Teste", Vector2.ZERO)
		v.look = VillagerArt.random_look(rng)
		v.hunger = moods[i].hunger
		v.energy = moods[i].energy
		v.mood = moods[i].mood
		var view := VillagerView.create(v, char_texture, town_texture)
		view.scale = Vector2(2, 2)
		stage.add_child(view)
		v.position = Vector2(1185, 150 + i * 150)
		view.sync(v)

	await _shoot("00_elenco")
	stage.queue_free()
	await process_frame

# ---- o jogo ----

func _capture_inicio() -> void:
	var instance = await _new_game()
	_simulate(instance, 6.0)
	instance.set_message("Cinco pessoas, um vale e nenhuma construção ainda.")
	await _shoot("01_vale_inicial")
	instance.queue_free()
	await process_frame

func _capture_trabalho() -> void:
	var instance = await _new_game()
	instance.economy.add("comida", 260.0)
	instance.economy.add("materiais", 90.0)
	instance.economy.owned = {"coletor": 4, "lascador": 2, "fogueira": 1}
	instance.population.sync_work_sites(instance.economy)
	instance.population.assign_jobs()
	instance._rebuild_plots()
	_simulate(instance, 40.0)
	_open_drawer(instance)
	instance.set_message("A loja é uma gaveta: só cobre o mundo enquanto está aberta.")
	await _shoot("02_gaveta_aberta")
	instance.queue_free()
	await process_frame

func _capture_colonia_viva() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 1
	instance.economy.owned = {"coletor": 5, "lascador": 3, "fogueira": 2, "fazenda": 4, "oleiro": 2}
	instance.economy.add("comida", 3000.0)
	instance.economy.add("materiais", 900.0)
	instance.on_era_entered(1)
	instance.close_era_overlay()
	instance.population.sync_work_sites(instance.economy)
	instance.population.ensure_minimum(22)
	instance.population.assign_jobs()
	# Tempo suficiente pra as trilhas se abrirem e alguém já ter carregado carga.
	_simulate(instance, 240.0)
	instance.inspect_at(instance.population.villagers[0].position)
	instance.set_message("Cada morador decide sozinho o que fazer.")
	await _shoot("03_colonia_viva")
	instance.queue_free()
	await process_frame

# Zoom no vale: em tela cheia o morador tem 48px e a animação/rosto some. Esta
# captura existe pra revisar a arte de perto sem abrir o editor.
func _capture_close() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 1
	instance.economy.owned = {"coletor": 4, "lascador": 3, "fazenda": 3}
	instance.economy.add("comida", 2000.0)
	instance.economy.add("materiais", 700.0)
	instance.on_era_entered(1)
	instance.close_era_overlay()
	instance.population.sync_work_sites(instance.economy)
	instance.population.ensure_minimum(18)
	instance.population.assign_jobs()
	_simulate(instance, 120.0)
	instance.world_root.scale = Vector2(2.4, 2.4)
	instance.world_root.position = Vector2(-380, 100 - 340)
	instance.set_message("Zoom: dá pra ver o gesto, a ferramenta e a cara de cada um.")
	await _shoot("04_close")
	instance.queue_free()
	await process_frame

func _capture_colonia_grande() -> void:
	var instance = await _new_game()
	instance.economy.era_index = 3
	instance.economy.owned = {
		"coletor": 12, "lascador": 8, "fogueira": 5,
		"fazenda": 9, "oleiro": 6, "escriba": 4,
		"mercado": 5, "mina": 4, "biblioteca": 3,
		"moinho_vapor": 3, "fabrica": 2, "escola": 2,
	}
	instance.economy.add("comida", 90000.0)
	instance.economy.add("materiais", 42000.0)
	instance.economy.add("conhecimento", 6400.0)
	instance.on_era_entered(3)
	instance.close_era_overlay()
	instance.population.sync_work_sites(instance.economy)
	instance.population.ensure_minimum(70)
	instance.population.assign_jobs()
	_simulate(instance, 240.0)
	instance.set_message("Era Industrial: a colônia inteira em movimento.")
	await _shoot("05_colonia_grande")
	instance.queue_free()
	await process_frame
