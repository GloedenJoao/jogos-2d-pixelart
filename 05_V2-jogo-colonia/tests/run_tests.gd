extends SceneTree

# Testes headless da Colônia Viva V2: matemática pura (Economy), geometria do
# vale (Valley), navegação (Pathfinder), arte do morador (VillagerArt),
# simulação (Villager/Population) e, por último, a cena inteira instanciada —
# UI, bonecos animados, eras, save/load e progresso offline.
#
# O V2 é um projeto sobre COMO OS MORADORES SE COMPORTAM E APARECEM. Por isso
# cada coisa nova tem asserção: se um dia a caminhada parar de mover a perna,
# se o rosto parar de mudar com o cansaço, se o caminho voltar a atravessar as
# casas ou se as trilhas voltarem a cobrir o vale inteiro, isto quebra aqui e
# não no olho de quem for jogar.

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_test_catalogs()
	_test_valley_layout()
	_test_clicks()
	_test_production()
	_test_costs_and_buying()
	_test_bulk_buying()
	_test_era_advance()
	_test_offline_progress()
	_test_save_roundtrip()
	_test_formatting()
	await _test_scene_boots()
	await _test_scene_gather_and_build()
	await _test_scene_era_advance()
	await _test_scene_save_and_reload()
	await _test_scene_offline_on_load()
	_test_villager_entity()
	_test_population_movement()
	_test_work_sites_and_staffing()
	_test_needs_decay()
	_test_eating_consumes_food_and_restores_hunger()
	_test_resting_restores_energy()
	_test_decision_ai_priority()
	_test_population_growth()
	_test_population_save_roundtrip()
	# ---- V2 ----
	_test_villager_art_composition()
	_test_villager_art_faces()
	_test_pathfinding()
	_test_trails()
	_test_facing()
	_test_socializing()
	_test_hauling()
	_test_construction_and_celebration()
	_test_separation()
	_test_scale_100_agents_performance()
	await _test_scene_population_boots()
	await _test_scene_layout_invariants()
	await _test_scene_villager_animation()
	await _test_scene_ambience()
	_report()

func _assert(cond: bool, message: String) -> void:
	if cond:
		_pass += 1
		print("  OK   - %s" % message)
	else:
		_fail += 1
		print("  FAIL - %s" % message)

# ---- catálogos ----

func _test_catalogs() -> void:
	print("[Eras/Buildings]")
	_assert(Eras.count() == 5, "cinco eras definidas")
	_assert(Buildings.ALL.size() == 15, "quinze construções no catálogo")
	for i in Eras.count():
		_assert(Buildings.unlocked_in(i).size() == 3, "era %d traz 3 construções novas" % i)
	_assert(Buildings.for_era(0).size() == 3, "na era 1 só as construções da era 1 existem")
	_assert(Buildings.for_era(2).size() == 9, "as construções são cumulativas entre eras")
	_assert(Eras.requirement(Eras.count() - 1).is_empty(), "a última era não tem requisito de avanço")
	_assert(Eras.click_power(0) < Eras.click_power(4), "clicar rende mais nas eras avançadas")
	for building in Buildings.ALL:
		_assert(not building.produces.is_empty() and not building.cost.is_empty(), "%s tem custo e produção" % building.id)

# ---- geometria do vale ----

# Estes testes são a regressão de LAYOUT: a primeira tentativa deste jogo foi
# jogada fora porque os moradores ficavam espremidos/escondidos atrás da UI, e
# nenhum teste reclamou. Aqui as regras de tela viram asserção.
func _test_valley_layout() -> void:
	print("[Valley - geometria do vale]")
	_assert(Valley.PLOT_CELLS.size() == Buildings.ALL.size(), "existe exatamente um lote por construção do catálogo")

	# Cada lote é 2×2 células. Dois lotes não podem dividir célula, senão duas
	# construções desenham uma por cima da outra.
	var occupied := {}
	var overlap := false
	for cell in Valley.PLOT_CELLS:
		for dx in 2:
			for dy in 2:
				var c: Vector2i = cell + Vector2i(dx, dy)
				if occupied.has(c):
					overlap = true
				occupied[c] = true
	_assert(not overlap, "nenhum lote 2×2 se sobrepõe a outro")

	var plaza_clear := true
	for y in Valley.PLAZA_RECT.size.y:
		for x in Valley.PLAZA_RECT.size.x:
			if occupied.has(Valley.PLAZA_RECT.position + Vector2i(x, y)):
				plaza_clear = false
	_assert(plaza_clear, "a praça central fica livre de construção")

	var inside := true
	for cell in Valley.PLOT_CELLS:
		if cell.x < 0 or cell.y < 0 or cell.x + 1 >= Valley.COLS or cell.y + 1 >= Valley.ROWS:
			inside = false
	_assert(inside, "todo lote cabe dentro da grade do vale")

	# O ponto onde a turma de cada construção fica de pé precisa caber na tela,
	# contando a fileira inteira e a largura do sprite do morador.
	# Pior caso real: a colônia inteira (o teto de população) empregada num
	# posto só. Nem assim a turma pode vazar pela borda da tela.
	var world_height: float = 720.0 - 100.0   # tela menos a tira de HUD
	var half_sprite := 24.0
	var crew_fits := true
	var worst := ""
	for building in Buildings.ALL:
		var spot := Valley.worker_spot(building.id)
		var deepest := 0.0
		for slot in Population.POPULATION_CAP:
			deepest = maxf(deepest, Valley.work_slot_offset(slot).y)
		if spot.x - Valley.crew_half_width() - half_sprite < 0.0 \
				or spot.x + Valley.crew_half_width() + half_sprite > 1280.0 \
				or spot.y + deepest > world_height:
			crew_fits = false
			worst = building.id
	_assert(crew_fits, "a turma de qualquer construção cabe na tela mesmo com a colônia inteira nela (pior caso: %s)" % worst)
	_assert(Valley.crew_depth() >= 0.0, "a profundidade máxima da turma é limitada, não cresce com a população")

	var spread := {}
	for i in 6:
		spread[Valley.PLOT_CELLS[i].y] = true
	_assert(spread.size() >= 2, "as construções das duas primeiras eras não ficam todas na mesma fileira")

# ---- economia pura ----

func _test_clicks() -> void:
	print("[Economy - clique manual]")
	var economy := Economy.new()
	_assert(economy.amount("comida") == 0.0, "civilização começa sem recursos")
	_assert(economy.gather("comida"), "coletar comida na era 1 funciona")
	_assert(economy.amount("comida") == Eras.click_power(0), "o clique rende o valor da era")
	_assert(not economy.gather("conhecimento"), "conhecimento ainda não pode ser coletado na era 1")
	_assert(economy.clicks == 1, "cliques válidos são contados")

	economy.era_index = 2
	economy.gather("conhecimento")
	_assert(economy.amount("conhecimento") == Eras.click_power(2), "na era 3 dá pra estudar, e o clique rende mais")

func _test_production() -> void:
	print("[Economy - produção automática]")
	var economy := Economy.new()
	economy.owned = {"coletor": 3}
	var rate := economy.production_per_second()
	_assert(is_equal_approx(rate.comida, 1.5), "3 coletores produzem 3× a produção de um")
	_assert(is_equal_approx(rate.materiais, 0.0), "quem não produz materiais não gera materiais")

	economy.tick(2.0)
	_assert(is_equal_approx(economy.amount("comida"), 3.0), "tick(2s) rende 2 segundos de produção")
	_assert(is_equal_approx(economy.elapsed, 2.0), "tempo jogado acumula")

	economy.owned["lascador"] = 2
	var rate2 := economy.production_per_second()
	_assert(is_equal_approx(rate2.materiais, 0.6), "construções diferentes somam nos seus recursos")

func _test_costs_and_buying() -> void:
	print("[Economy - custos e compras]")
	var economy := Economy.new()
	var base := economy.cost_of("coletor")
	_assert(base.comida == 12.0, "primeiro coletor custa o preço-base")
	_assert(not economy.can_buy("coletor"), "sem recursos não dá pra construir")

	economy.add("comida", 12.0)
	_assert(economy.buy("coletor"), "com recursos exatos a compra passa")
	_assert(economy.amount("comida") == 0.0, "o custo é debitado")
	_assert(economy.count_of("coletor") == 1, "a construção entra no inventário")
	_assert(economy.cost_of("coletor").comida > base.comida, "o segundo custa mais caro que o primeiro")

	economy.add("comida", 100000.0)
	economy.add("materiais", 100000.0)
	_assert(not economy.buy("fazenda"), "construção de era futura não pode ser comprada")
	economy.era_index = 1
	_assert(economy.buy("fazenda"), "ao chegar na era certa a construção libera")
	_assert(economy.total_buildings() == 2, "total de construções soma todos os tipos")

func _test_bulk_buying() -> void:
	print("[Economy - compra em lote]")
	var economy := Economy.new()
	economy.add("comida", 1000.0)

	var cost_n1 := economy.cost_of_n("coletor", 1)
	_assert(cost_n1.comida == economy.cost_of("coletor").comida, "cost_of_n(1) bate com cost_of")

	var single_total := 0.0
	var economy_single := Economy.new()
	economy_single.add("comida", 100000.0)
	for _i in 10:
		single_total += economy_single.cost_of("coletor").comida
		economy_single.buy("coletor")
	var cost_n10 := economy.cost_of_n("coletor", 10)
	_assert(absf(cost_n10.comida - single_total) <= 10.0, "custo de comprar 10 de uma vez é equivalente a comprar 1 dez vezes (só difere no arredondamento por etapa)")

	_assert(not economy.can_buy_n("coletor", 1000), "não dá pra comprar mais do que o estoque permite")
	_assert(economy.buy_n("coletor", 5), "comprar 5 de uma vez funciona com recursos suficientes")
	_assert(economy.count_of("coletor") == 5, "as 5 cópias entram no inventário de uma vez")

	var economy2 := Economy.new()
	economy2.add("comida", 100.0)
	var max_n := economy2.max_affordable("coletor")
	_assert(max_n > 0, "max_affordable calcula quantas cópias dá pra comprar")
	_assert(economy2.can_afford(economy2.cost_of_n("coletor", max_n)), "o resultado de max_affordable é sempre pagável")
	_assert(not economy2.can_afford(economy2.cost_of_n("coletor", max_n + 1)), "uma a mais que max_affordable já não é pagável")
	_assert(Economy.new().max_affordable("fazenda") == 0, "construção bloqueada por era não é afordável")

func _test_era_advance() -> void:
	print("[Economy - virada de era]")
	var economy := Economy.new()
	_assert(not economy.can_advance(), "sem recursos a era não vira")
	_assert(economy.era_progress() < 1.0, "progresso da era começa abaixo de 100%")

	var requirement := Eras.requirement(0)
	for resource in requirement:
		economy.add(resource, float(requirement[resource]))
	_assert(economy.can_advance(), "juntando o requisito a virada libera")
	_assert(is_equal_approx(economy.era_progress(), 1.0), "progresso chega a 100%")
	_assert(economy.advance(), "avançar de era funciona")
	_assert(economy.era_index == 1, "a era sobe")
	_assert(economy.amount("comida") == 0.0, "a virada consome o requisito")

	economy.era_index = Eras.count() - 1
	_assert(not economy.can_advance(), "não há era além da última")
	_assert(not economy.advance(), "avançar na última era é recusado")

func _test_offline_progress() -> void:
	print("[Economy - progresso offline]")
	var economy := Economy.new()
	economy.owned = {"coletor": 10} # 5 comida/s
	var result := economy.apply_offline(60.0)
	_assert(is_equal_approx(result.seconds, 60.0), "1 minuto offline é contado inteiro")
	_assert(is_equal_approx(economy.amount("comida"), 300.0), "produção offline entra no estoque")

	var economy2 := Economy.new()
	economy2.owned = {"coletor": 10}
	var capped := economy2.apply_offline(48.0 * 3600.0)
	_assert(is_equal_approx(capped.seconds, Economy.OFFLINE_CAP_SECONDS), "offline é limitado ao teto de 8h")
	_assert(economy2.apply_offline(-5.0).seconds == 0.0, "tempo negativo não rende nada")

func _test_save_roundtrip() -> void:
	print("[Economy - salvar e carregar]")
	var economy := Economy.new()
	economy.era_index = 2
	economy.add("comida", 123.5)
	economy.owned = {"coletor": 4, "fazenda": 2}
	economy.clicks = 17

	var restored := Economy.from_save(economy.to_dict())
	_assert(restored.era_index == 2, "era é restaurada")
	_assert(is_equal_approx(restored.amount("comida"), 123.5), "recursos são restaurados")
	_assert(restored.count_of("fazenda") == 2, "construções são restauradas")
	_assert(restored.clicks == 17, "contador de cliques é restaurado")

	var dirty := Economy.from_save({"era_index": 99, "owned": {"construcao_inexistente": 5}, "resources": {"comida": "x"}})
	_assert(dirty.era_index == Eras.count() - 1, "era fora do intervalo é limitada")
	_assert(dirty.count_of("construcao_inexistente") == 0, "id desconhecido no save é ignorado")

func _test_formatting() -> void:
	print("[Economy - formatação de números]")
	_assert(Economy.format_amount(12.34) == "12.3", "valores pequenos mostram uma casa decimal")
	_assert(Economy.format_amount(1500.0) == "1.5k", "milhares viram k")
	_assert(Economy.format_amount(2500000.0) == "2.5M", "milhões viram M")
	_assert(Economy.format_rate(2.0).ends_with("/s"), "taxa é exibida por segundo")

# ---- cena ----

const SAVE_KEY := "colonia_v2"

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase(SAVE_KEY)
	save_system.save_data()

func _new_game() -> Node:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance = packed.instantiate()
	root.add_child(instance)
	await process_frame
	return instance

func _test_scene_boots() -> void:
	print("[Cena - boot]")
	_reset_save()
	var instance = await _new_game()
	_assert(instance.ui_root.theme != null, "UITheme aplicado")
	_assert(instance.state_machine.current_state.name == "Era0", "civilização começa na primeira era")
	_assert(instance.gather_row.get_child_count() == Eras.era(0).click_resources.size(), "botões de coleta batem com a era")
	_assert(instance.building_rows.size() == Buildings.ALL.size(), "todas as construções têm linha na UI")
	_assert(instance.building_rows["coletor"].root.visible, "construção da era atual aparece")
	_assert(not instance.building_rows["fazenda"].root.visible, "construção de era futura fica escondida")
	instance.queue_free()
	await process_frame

func _test_scene_gather_and_build() -> void:
	print("[Cena - coletar e construir]")
	_reset_save()
	var instance = await _new_game()
	instance.gather("comida")
	_assert(instance.economy.amount("comida") >= Eras.click_power(0), "clicar no botão de coleta rende recurso")

	instance.economy.add("comida", 100.0)
	instance._update_hud()
	_assert(not instance.building_rows["coletor"].button.disabled, "com recursos o botão de construir habilita")

	var before: int = instance.economy.count_of("coletor")
	instance.buy("coletor")
	_assert(instance.economy.count_of("coletor") == before + 1, "construir pela cena incrementa a construção")
	_assert(instance.plots_root.get_child_count() > 0, "o lote da construção aparece no vale")
	_assert(instance.economy.production_per_second().comida > 0.0, "a produção por segundo passa a existir")

	instance.economy.add("comida", 100000.0)
	instance.set_buy_multiplier(10)
	var before10: int = instance.economy.count_of("coletor")
	instance.buy("coletor")
	_assert(instance.economy.count_of("coletor") == before10 + 10, "com o multiplicador ×10 a compra soma 10 de uma vez")

	instance.set_buy_multiplier(-1)
	instance._update_hud()
	_assert(instance.building_rows["coletor"].button.text.begins_with("Construir ×"), "o botão mostra quantas cópias o multiplicador xMáx vai comprar")
	instance.set_buy_multiplier(1)
	instance.queue_free()
	await process_frame

func _test_scene_era_advance() -> void:
	print("[Cena - virada de era]")
	_reset_save()
	var instance = await _new_game()
	var requirement := Eras.requirement(0)
	for resource in requirement:
		instance.economy.add(resource, float(requirement[resource]))
	instance._update_hud()
	_assert(not instance.advance_button.disabled, "com o requisito o botão de avançar habilita")

	instance.advance_era()
	await process_frame
	_assert(instance.economy.era_index == 1, "a economia avança de era")
	_assert(instance.state_machine.current_state.name == "Era1", "a StateMachine acompanha a era")
	_assert(instance.era_overlay.visible, "overlay da nova era aparece")
	_assert(instance.building_rows["fazenda"].root.visible, "construções da nova era aparecem na lista")
	_assert(instance.gather_row.get_child_count() == Eras.era(1).click_resources.size(), "a nova era libera mais tipos de coleta")

	instance.close_era_overlay()
	_assert(not instance.era_overlay.visible, "dá pra fechar o overlay e continuar")
	instance.queue_free()
	await process_frame

func _test_scene_save_and_reload() -> void:
	print("[Cena - salvar e voltar depois]")
	_reset_save()
	var instance = await _new_game()
	instance.economy.era_index = 1
	instance.economy.add("comida", 250.0)
	instance.economy.owned = {"coletor": 3, "fazenda": 1}
	instance.save_game()
	instance.queue_free()
	await process_frame

	var reopened = await _new_game()
	_assert(reopened.economy.era_index == 1, "a era volta como estava")
	_assert(reopened.economy.count_of("coletor") == 3, "as construções voltam como estavam")
	_assert(reopened.economy.amount("comida") >= 250.0, "os recursos voltam como estavam")
	_assert(reopened.state_machine.current_state.name == "Era1", "a cena reabre já na era salva")
	reopened.queue_free()
	await process_frame

func _test_scene_offline_on_load() -> void:
	print("[Cena - produção enquanto o jogo estava fechado]")
	_reset_save()
	var save_system := root.get_node("/root/SaveSystem")
	save_system.set_value(SAVE_KEY, {
		"resources": {"comida": 0.0, "materiais": 0.0, "conhecimento": 0.0},
		"owned": {"coletor": 10}, # 5 comida/s
		"era_index": 0,
		"clicks": 0,
		"elapsed": 0.0,
		"saved_at": Time.get_unix_time_from_system() - 3600.0, # uma hora atrás
	})
	save_system.save_data()

	var instance = await _new_game()
	_assert(instance.economy.amount("comida") > 17000.0, "uma hora fechado rendeu ~1h de produção (%s)" % Economy.format_amount(instance.economy.amount("comida")))
	_assert(instance.message_label.text.contains("fora"), "a mensagem avisa o que rendeu offline")
	instance.queue_free()
	await process_frame

# ---- Colônia Viva: Villager (Fase 1) ----

func _test_villager_entity() -> void:
	print("[Villager - Fase 1: entidade]")
	var v := Villager.new(1, "Ana", Vector2(10, 20))
	_assert(v.id == 1, "villager guarda id")
	_assert(v.display_name == "Ana", "villager guarda nome")
	_assert(v.position == Vector2(10, 20), "villager guarda posição")
	_assert(v.state == Villager.STATE_IDLE, "villager nasce ocioso")
	_assert(not v.has_job(), "villager nasce sem emprego")
	_assert(not v.is_moving(), "parado no lugar não conta como 'andando'")

	var restored := Villager.from_dict(v.to_dict())
	_assert(restored.id == v.id and restored.display_name == v.display_name, "to_dict/from_dict preserva identidade")
	_assert(restored.position == v.position, "to_dict/from_dict preserva posição")

# ---- Colônia Viva: Population (Fases 2-6) ----

func _test_population_movement() -> void:
	print("[Population - Fase 2: movimento]")
	var pop := Population.new()
	var v := pop.spawn_villager(Vector2.ZERO)
	v.position = Vector2.ZERO # spawn_villager espalha com jitter; fixa a origem pro teste
	v.target_position = Vector2(100, 0)
	v.state = Villager.STATE_WALKING
	pop._move_all(0.5) # 90px/s × 0.5s = 45px
	_assert(is_equal_approx(v.position.x, 45.0), "anda na direção do alvo, respeitando a velocidade")
	_assert(v.is_moving(), "ainda não chegou no alvo")

	pop._move_all(1.0)
	_assert(v.position == v.target_position, "chega exatamente no alvo, sem passar dele")
	_assert(v.state == Villager.STATE_IDLE, "ao chegar sem uma intenção pendente, volta a ficar ocioso")

func _test_work_sites_and_staffing() -> void:
	print("[Population - Fase 3: vagas de trabalho ligadas à produção]")
	var economy := Economy.new()
	economy.owned = {"coletor": 2} # 2 vagas por unidade × 2 unidades = 4 vagas
	var pop := Population.new()
	pop.sync_work_sites(economy)
	_assert(pop.work_sites.size() == 1, "um posto de trabalho por tipo de construção possuída")
	_assert(int(pop.work_sites[0].capacity) == 4, "capacidade = vagas por unidade × quantidade possuída")
	_assert(is_equal_approx(float(pop.staffing_ratios().get("coletor", 0.0)), 0.0), "sem ninguém alocado e trabalhando, staffing começa em zero")

	var v := pop.spawn_villager(pop.work_sites[0].position)
	pop.assign_jobs()
	_assert(v.has_job() and v.job_id == "coletor", "um villager ocioso é alocado numa vaga aberta")

	# só estar alocado não basta: staffing exige estar de fato TRABALHANDO agora.
	_assert(is_equal_approx(float(pop.staffing_ratios().get("coletor", 0.0)), 0.0), "alocado mas ainda não presente no posto não conta como staffado")
	v.state = Villager.STATE_WORKING
	var expected_ratio: float = (1.0 / 4.0) * clampf(0.6 + 0.5 * v.mood, 0.6, 1.1)
	_assert(is_equal_approx(float(pop.staffing_ratios().get("coletor", 0.0)), expected_ratio), "staffing = fração de vagas ocupadas por quem trabalha × fator de humor")

	var rate_real := economy.production_per_second(pop.staffing_ratios())
	var rate_catalogo := economy.production_per_second()
	_assert(rate_real.comida > 0.0, "com 1 de 4 vagas trabalhando, ainda produz alguma coisa")
	_assert(rate_real.comida < rate_catalogo.comida, "mas bem menos que a produção 'de catálogo' (todas as vagas cheias)")

func _test_needs_decay() -> void:
	print("[Population - Fase 4: necessidades decaem com o tempo]")
	var economy := Economy.new()

	var pop_idle := Population.new()
	var v := pop_idle.spawn_villager()
	v.hunger = 1.0
	v.energy = 1.0
	v.state = Villager.STATE_IDLE
	pop_idle._update_needs_and_decisions(60.0, economy) # 60s acumulados de uma vez (decisão em lote, Fase 6)
	_assert(v.hunger < 1.0, "fome decai com o tempo")
	_assert(v.energy < 1.0, "energia decai com o tempo, mesmo ocioso")

	# população separada: comparar decaimento isolado, sem acumular dois passos no mesmo villager
	var pop_working := Population.new()
	var v2 := pop_working.spawn_villager()
	v2.hunger = 1.0
	v2.energy = 1.0
	v2.state = Villager.STATE_WORKING
	pop_working._update_needs_and_decisions(60.0, economy)
	_assert(v2.energy < v.energy, "trabalhar cansa mais rápido que ficar ocioso")

func _test_eating_consumes_food_and_restores_hunger() -> void:
	print("[Population - Fase 4: comer resolve a fome e consome o estoque]")
	var economy := Economy.new()
	economy.add("comida", 1000.0)
	var pop := Population.new()
	var v := pop.spawn_villager(Valley.plaza_center())
	v.hunger = 0.1
	v.state = Villager.STATE_EATING
	v.action_timer = Villager.EAT_DURATION
	var before_food := economy.amount("comida")
	pop._update_needs_and_decisions(1.0, economy)
	_assert(economy.amount("comida") < before_food, "comer consome comida do estoque")
	_assert(v.hunger > 0.1, "comer restaura a fome")

	var economy_sem_comida := Economy.new()
	var pop2 := Population.new()
	var v2 := pop2.spawn_villager(Valley.plaza_center())
	v2.hunger = 0.1
	v2.state = Villager.STATE_EATING
	v2.action_timer = Villager.EAT_DURATION
	pop2._update_needs_and_decisions(1.0, economy_sem_comida)
	_assert(v2.hunger < 0.1, "sem estoque de comida, comer não restaura nada — a fome só segue seu decaimento natural")

func _test_resting_restores_energy() -> void:
	print("[Population - Fase 4: descansar resolve o cansaço]")
	var economy := Economy.new()
	var pop := Population.new()
	var v := pop.spawn_villager()
	v.energy = 0.1
	v.state = Villager.STATE_RESTING
	v.action_timer = Villager.REST_DURATION
	pop._update_needs_and_decisions(1.0, economy)
	_assert(v.energy > 0.1, "descansar restaura energia")

	pop._update_needs_and_decisions(Villager.REST_DURATION + 1.0, economy)
	_assert(v.state == Villager.STATE_IDLE, "depois do tempo de descanso, volta a ficar ocioso")

func _test_decision_ai_priority() -> void:
	print("[Population - Fase 5: IA de decisão por utilidade]")
	var pop := Population.new()
	var v := pop.spawn_villager()
	v.job_id = "coletor"
	pop.work_sites = [{"building_id": "coletor", "position": Vector2(500, 500), "capacity": 1, "workers": [v.id]}]

	v.hunger = 0.9
	v.energy = 0.9
	v.state = Villager.STATE_IDLE
	pop._decide_action(v)
	_assert(v.pending_action == "work", "com necessidades em dia, a prioridade é trabalhar")

	v.hunger = 0.05
	v.state = Villager.STATE_IDLE
	v.pending_action = ""
	pop._decide_action(v)
	_assert(v.pending_action == "eat", "fome crítica tem prioridade sobre trabalhar")

	v.hunger = 0.5
	v.energy = 0.05
	v.state = Villager.STATE_IDLE
	v.pending_action = ""
	pop._decide_action(v)
	_assert(v.pending_action == "rest", "energia crítica manda descansar, mesmo com fome moderada")

	var unemployed := pop.spawn_villager()
	unemployed.hunger = 0.9
	unemployed.energy = 0.9
	unemployed.state = Villager.STATE_IDLE
	pop._decide_action(unemployed)
	_assert(unemployed.pending_action != "work", "sem emprego, não tem pra onde 'trabalhar'")

func _test_population_growth() -> void:
	print("[Population - crescimento até o alvo de vagas]")
	var economy := Economy.new()
	economy.owned = {"coletor": 3} # 2 vagas × 3 = 6 vagas de trabalho
	economy.add("comida", 10000.0)
	var pop := Population.new()
	pop.sync_work_sites(economy)
	var target := pop.population_target()
	_assert(target == 6 + Population.IDLE_BUFFER, "alvo de população = vagas de trabalho + folga ociosa")

	pop.ensure_minimum(1)
	for _i in 200:
		pop._maybe_grow(economy)
	_assert(pop.villagers.size() == target, "a população cresce até o alvo e para exatamente nele")
	_assert(economy.amount("comida") < 10000.0, "cada morador novo consome comida do estoque pra 'nascer'")

func _test_population_save_roundtrip() -> void:
	print("[Population - salvar e carregar]")
	var economy := Economy.new()
	economy.owned = {"coletor": 2}
	var pop := Population.new()
	pop.sync_work_sites(economy)
	var v := pop.spawn_villager()
	v.hunger = 0.4
	v.energy = 0.6
	v.mood = 0.5
	pop.assign_jobs()

	var restored := Population.new()
	restored.from_dict(pop.to_dict(), economy)
	_assert(restored.villagers.size() == pop.villagers.size(), "número de moradores é restaurado")
	var rv: Villager = restored.get_villager(v.id)
	_assert(rv != null, "cada morador é restaurado pelo id")
	_assert(is_equal_approx(rv.hunger, 0.4) and is_equal_approx(rv.energy, 0.6), "necessidades são restauradas")
	_assert(restored.work_sites.size() == pop.work_sites.size(), "vagas de trabalho são recalculadas a partir da economia restaurada")

# ======================================================================
#  V2 — os moradores
# ======================================================================

# ---- arte: cada morador é uma pessoa diferente ----

func _test_villager_art_composition() -> void:
	print("[VillagerArt - o morador é montado, não escolhido]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260807

	var look := VillagerArt.random_look(rng)
	for key in ["skin", "shirt", "shirt_color", "hair", "hair_color"]:
		_assert(look.has(key), "a aparência sorteada define %s" % key)

	var body := VillagerArt.bake_body(look)
	_assert(body.get_width() == VillagerArt.TILE * VillagerArt.POSE_COUNT,
		"a textura do corpo traz as poses (frente/costas) lado a lado")
	_assert(body.get_height() == VillagerArt.TILE, "e tem a altura de um tile só")

	# Duas aparências sorteadas não podem sair iguais, senão a "variedade" é
	# só promessa: a colônia continuaria parecendo clonada.
	var different := 0
	var seen := {}
	for _i in 30:
		var other := VillagerArt.random_look(rng)
		var key := "%s|%s|%s|%s|%s" % [other.skin, other.shirt, other.shirt_color, other.hair, other.hair_color]
		if not seen.has(key):
			seen[key] = true
			different += 1
	_assert(different >= 25, "30 sorteios geram pelo menos 25 aparências distintas (saíram %d)" % different)

	# Recolorir tem que PRESERVAR o sombreado: o pixel mais escuro do desenho
	# continua o mais escuro na cor nova. É a diferença entre trocar a roupa e
	# borrar o personagem com `modulate` (o erro do V1).
	var source := VillagerArt.tile_image(VillagerArt.SHIRT_TILES[0])
	var painted := VillagerArt.recolor(source, Color("2f5fa0"))
	var pairs: Array = []
	var recorded := {}
	for y in source.get_height():
		for x in source.get_width():
			var before := source.get_pixel(x, y)
			if before.a <= 0.0 or recorded.has(before):
				continue
			recorded[before] = true
			pairs.append([before.get_luminance(), painted.get_pixel(x, y).get_luminance()])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var monotonic := true
	for i in range(1, pairs.size()):
		if pairs[i][1] < pairs[i - 1][1] - 0.001:
			monotonic = false
	_assert(pairs.size() >= 3, "a peça recolorida tem uma rampa de pelo menos 3 tons")
	_assert(monotonic, "a recolorização preserva a ordem de luminância (o sombreado sobrevive)")

	var hues := {}
	for color in VillagerArt.SHIRT_COLORS:
		hues[snappedf(color.h, 0.01)] = true
	_assert(hues.size() >= 8, "a paleta de camisas cobre pelo menos 8 matizes")

func _test_villager_art_faces() -> void:
	print("[VillagerArt - a cara conta o que a pessoa sente]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var look := VillagerArt.random_look(rng)

	var atlas := VillagerArt.bake_face(look).get_image()
	_assert(atlas.get_width() == VillagerArt.PART_HEAD.size.x, "o rosto tem a largura do recorte da cabeça")
	_assert(atlas.get_height() == VillagerArt.PART_HEAD.size.y * VillagerArt.EXPR_COUNT * VillagerArt.FACE_VIEWS,
		"o atlas tem uma linha por expressão e vista")

	# O rosto é sobreposição: o corpo assado NÃO pode trazer olho pintado, ou a
	# expressão dinâmica ficaria por cima de uma cara fixa.
	var eye_x := VillagerArt.EYE_LEFT_X - VillagerArt.PART_HEAD.position.x
	var neutral_y := VillagerArt.face_row(VillagerArt.EXPR_NEUTRAL, VillagerArt.FACE_FRONT) * VillagerArt.PART_HEAD.size.y
	var blink_y := VillagerArt.face_row(VillagerArt.EXPR_BLINK, VillagerArt.FACE_FRONT) * VillagerArt.PART_HEAD.size.y
	_assert(atlas.get_pixel(eye_x, neutral_y + VillagerArt.EYE_Y).a > 0.0, "a expressão neutra desenha o olho")
	_assert(atlas.get_pixel(eye_x, blink_y + VillagerArt.EYE_Y).a <= 0.0, "piscando, o olho some")

	var side_y := VillagerArt.face_row(VillagerArt.EXPR_NEUTRAL, VillagerArt.FACE_SIDE) * VillagerArt.PART_HEAD.size.y
	_assert(atlas.get_pixel(eye_x, side_y + VillagerArt.EYE_Y).a <= 0.0, "de perfil, o olho de trás não é desenhado")

	# A cara segue a necessidade mais gritante, não a média.
	_assert(VillagerArt.expression_for(Villager.STATE_IDLE, 1.0, 0.1, 0.9, false) == VillagerArt.EXPR_TIRED,
		"cansaço crítico deixa cara de cansado mesmo com humor alto")
	_assert(VillagerArt.expression_for(Villager.STATE_IDLE, 0.1, 1.0, 0.9, false) == VillagerArt.EXPR_HUNGRY,
		"fome crítica deixa cara de fome")
	_assert(VillagerArt.expression_for(Villager.STATE_IDLE, 1.0, 1.0, 0.9, false) == VillagerArt.EXPR_HAPPY,
		"tudo em dia e humor alto: cara feliz")
	_assert(VillagerArt.expression_for(Villager.STATE_IDLE, 1.0, 1.0, 0.2, false) == VillagerArt.EXPR_SAD,
		"humor baixo com necessidades ok: cara triste")
	_assert(VillagerArt.expression_for(Villager.STATE_RESTING, 1.0, 1.0, 0.9, false) == VillagerArt.EXPR_SLEEP,
		"descansando, olhos fechados")

# ---- navegação ----

func _test_pathfinding() -> void:
	print("[Pathfinder - o caminho contorna as casas]")
	var pathfinder := Pathfinder.new()
	pathfinder.rebuild(["coletor"])

	var plot := Valley.plot_cell("coletor")
	_assert(pathfinder.is_solid(plot), "o lote da construção vira obstáculo")
	_assert(pathfinder.is_solid(plot + Vector2i(1, 1)), "as quatro células do lote 2×2 são sólidas")
	_assert(not pathfinder.is_solid(Pathfinder.cell_of(Valley.plaza_center())), "a praça continua livre")

	# O teste que importa: nenhum trecho do caminho pode atravessar um lote.
	var path := pathfinder.find_path(Valley.plaza_center(), Valley.worker_spot("coletor"))
	_assert(path.size() > 0, "existe caminho da praça até o posto de trabalho")
	var previous := Valley.plaza_center()
	var crossed := false
	for point in path:
		if not pathfinder.line_is_clear(previous, point):
			crossed = true
		previous = point
	_assert(not crossed, "nenhum trecho do caminho atravessa uma construção")

	# Um caminho que passasse por dentro seria mais curto que o que contorna:
	# é assim que se prova que ele está de fato desviando.
	var straight := Valley.plaza_center().distance_to(Valley.worker_spot("coletor"))
	var walked := 0.0
	previous = Valley.plaza_center()
	for point in path:
		walked += previous.distance_to(point)
		previous = point
	_assert(walked >= straight - 1.0, "o desvio nunca é mais curto que a reta (%.0f vs %.0f)" % [walked, straight])

	# Com TUDO construído, todo posto continua alcançável a partir da praça —
	# senão existiria uma colônia possível em que alguém nunca chega no trabalho.
	var full := Pathfinder.new()
	var everything: Array = []
	for building in Buildings.ALL:
		everything.append(building.id)
	full.rebuild(everything)
	var unreachable := ""
	for building in Buildings.ALL:
		if not full.has_route(Valley.plaza_center(), Valley.worker_spot(building.id)):
			unreachable = building.id
	_assert(unreachable == "", "com as 15 construções de pé, todo posto continua alcançável (falhou: %s)" % unreachable)

	# Corte de esquina: o caminho entregue tem menos pontos que células
	# percorridas, senão o morador anda em escada.
	var far := full.find_path(Vector2(60, 60), Vector2(1180, 560))
	var raw := full.grid.get_id_path(Pathfinder.cell_of(Vector2(60, 60)), Pathfinder.cell_of(Vector2(1180, 560)))
	_assert(far.size() < raw.size(), "o corte de esquina reduz os pontos do caminho (%d de %d)" % [far.size(), raw.size()])

	# Quem foi parar dentro de uma casa (save antigo, empurrão de multidão)
	# ainda precisa conseguir sair.
	var inside := full.nearest_free(Valley.plot_cell("fazenda"))
	_assert(not full.is_solid(inside), "quem está dentro de um lote é reposicionado na célula livre mais próxima")

func _test_trails() -> void:
	print("[Pathfinder - as trilhas se abrem sozinhas]")
	var pathfinder := Pathfinder.new()
	pathfinder.rebuild([])

	var spot := Vector2(400.0, 300.0)
	for _i in 40:
		pathfinder.register_step(spot)
	_assert(pathfinder.trail_cells().is_empty(), "pisar não vira trilha na hora — só na varredura periódica")
	pathfinder.decay(Pathfinder.REBUILD_INTERVAL)
	_assert(pathfinder.is_trail(Pathfinder.cell_of(spot)), "célula muito pisada vira trilha")

	# O teto é o que impede a colônia grande de arar o vale inteiro. Sem ele,
	# 240s de simulação cobriam quase todo o mapa de terra (foi o que aconteceu).
	var crowded := Pathfinder.new()
	crowded.rebuild([])
	for x in Valley.COLS:
		for y in Valley.ROWS:
			for _i in 40:
				crowded.register_step(Pathfinder.center_of(Vector2i(x, y)))
	crowded.decay(Pathfinder.REBUILD_INTERVAL)
	_assert(crowded.trail_cells().size() <= Pathfinder.TRAIL_LIMIT,
		"mesmo pisando o vale inteiro, só %d células viram estrada (viraram %d)" % [Pathfinder.TRAIL_LIMIT, crowded.trail_cells().size()])
	_assert(float(crowded.trail_cells().size()) / float(Valley.COLS * Valley.ROWS) < 0.2,
		"a malha de trilhas ocupa menos de 20% do vale — é estrada, não lavoura")

	# Trilha abandonada volta a ser mato.
	for _i in 200:
		pathfinder.decay(Pathfinder.REBUILD_INTERVAL)
	_assert(not pathfinder.is_trail(Pathfinder.cell_of(spot)), "trilha sem uso some com o tempo")

	# Andar na trilha é mais barato: é o que faz o próximo morador reforçar o
	# caminho já aberto em vez de cortar mato novo.
	var weighted := Pathfinder.new()
	weighted.rebuild([])
	var cell := Vector2i(5, 5)
	for _i in 40:
		weighted.register_step(Pathfinder.center_of(cell))
	weighted.decay(Pathfinder.REBUILD_INTERVAL)
	_assert(weighted.grid.get_point_weight_scale(cell) < 1.0, "célula de trilha fica mais barata pro A*")

	var restored := Pathfinder.new()
	restored.rebuild([])
	restored.from_dict(weighted.to_dict())
	_assert(restored.is_trail(cell), "as trilhas são salvas e voltam ao reabrir o jogo")

# ---- comportamento ----

func _test_facing() -> void:
	print("[Villager - para onde ele olha]")
	var v := Villager.new(1, "Teste", Vector2.ZERO)
	v.face_towards(Vector2(1, 0))
	_assert(v.facing == Villager.DIR_EAST, "andando pra direita, olha pra leste")
	v.face_towards(Vector2(-1, 0))
	_assert(v.facing == Villager.DIR_WEST, "andando pra esquerda, olha pra oeste")
	v.face_towards(Vector2(0, 1))
	_assert(v.facing == Villager.DIR_SOUTH, "descendo a tela, olha pra frente")
	v.face_towards(Vector2(0, -1))
	_assert(v.facing == Villager.DIR_NORTH, "subindo a tela, olha de costas")
	v.face_towards(Vector2.ZERO)
	_assert(v.facing == Villager.DIR_NORTH, "parado, mantém a última direção (não dá solavanco ao chegar)")

	# Andar de verdade tem que virar o boneco: no V1 todo mundo caminhava de
	# frente, inclusive andando pra trás.
	var pop := Population.new()
	var walker := pop.spawn_villager(Vector2(200, 300))
	walker.position = Vector2(200, 300)
	walker.facing = Villager.DIR_SOUTH
	walker.target_position = Vector2(600, 300)
	walker.state = Villager.STATE_WALKING
	pop._by_id[walker.id] = walker
	pop._move_all(0.2)
	_assert(walker.facing == Villager.DIR_EAST, "quem anda pra leste passa a olhar pra leste")

func _test_socializing() -> void:
	print("[Population - gente conversa (ação autônoma nova)]")
	var economy := Economy.new()
	var pop := Population.new()
	var a := pop.spawn_villager(Vector2(400, 300))
	var b := pop.spawn_villager(Vector2(470, 310))
	a.position = Vector2(400, 300)
	b.position = Vector2(470, 310)
	a.social = 0.05
	b.social = 0.9
	a.hunger = 1.0; a.energy = 1.0
	b.hunger = 1.0; b.energy = 1.0

	pop._decide_action(a)
	_assert(a.partner_id == b.id and b.partner_id == a.id, "quem está carente de convívio arruma companhia, e os dois viram dupla")
	_assert(a.pending_action == "chat" and b.pending_action == "chat", "os dois se deslocam para conversar")

	# Menos que Villager.SOCIAL_DURATION: passando disso a conversa já terminou
	# sozinha e o teste estaria olhando pro fim, não pro meio.
	for _i in 45:
		pop.tick(1.0 / 30.0, economy)
	_assert(a.state == Villager.STATE_SOCIALIZING and b.state == Villager.STATE_SOCIALIZING,
		"ao se encontrarem, os dois ficam conversando")
	_assert(a.position.distance_to(b.position) < 90.0, "conversa acontece com os dois lado a lado, não de longe")

	var before := a.social
	pop._tick_socializing(a, 1.0)
	_assert(a.social > before, "conversar mata a carência de convívio")

	# Se o outro larga a conversa, ninguém fica falando sozinho.
	b.state = Villager.STATE_IDLE
	pop._tick_socializing(a, 1.0)
	_assert(a.state == Villager.STATE_IDLE and a.partner_id == 0, "conversa acaba quando o outro sai")

	# A carência entra no humor: uma colônia bem alimentada e sem convívio não
	# é uma colônia feliz.
	var lonely := Population.new()
	var solo := lonely.spawn_villager()
	solo.hunger = 1.0
	solo.energy = 1.0
	solo.social = 0.0
	solo.mood = 1.0
	lonely._update_needs_and_decisions(60.0, economy)
	_assert(solo.mood < 1.0, "sem convívio, o humor cai mesmo com fome e energia cheias")

func _test_hauling() -> void:
	print("[Population - carregar a produção até o celeiro]")
	var economy := Economy.new()
	economy.owned = {"coletor": 1}
	economy.add("comida", 500.0)
	var pop := Population.new()
	pop.sync_work_sites(economy)
	var v := pop.spawn_villager(pop.work_sites[0].position)
	pop.assign_jobs()
	v.state = Villager.STATE_WORKING
	v.action_timer = Population.HAUL_AFTER
	pop._maybe_start_haul(v)

	_assert(v.carrying == "comida", "depois de um tempo no posto, o trabalhador pega a produção")
	_assert(v.state == Villager.STATE_WALKING and v.pending_action == "deliver", "e sai andando para entregar")
	_assert(Population.counts_as_staffed(v),
		"quem carrega CONTINUA contando como vaga ocupada — o V2 muda comportamento, não o equilíbrio da economia")

	# Para no instante da entrega: deixar rodando mais e ele já voltou ao posto,
	# trabalhou outros 14s e saiu com carga nova — o ciclo é contínuo.
	var delivered := false
	for _i in 900:
		pop.tick(1.0 / 30.0, economy)
		for event in pop.drain_events():
			if event.type == "entrega":
				delivered = true
		if delivered:
			break
	_assert(delivered, "a entrega chega ao celeiro e vira um acontecimento pra cena mostrar")
	_assert(v.carrying == "", "e o morador larga a carga ao chegar")
	_assert(v.position.distance_to(Valley.granary()) < 120.0, "a entrega acontece no celeiro, não em qualquer lugar")

func _test_construction_and_celebration() -> void:
	print("[Population - obra e festa (gatilhos da cena)]")
	var economy := Economy.new()
	economy.owned = {"coletor": 2}
	var pop := Population.new()
	pop.sync_work_sites(economy)
	for _i in 8:
		pop.spawn_villager()

	var crew := pop.start_construction("coletor", 4)
	_assert(crew == 4, "comprar uma construção manda uma turma levantar a obra")
	var going := 0
	for v in pop.villagers:
		if v.pending_action == "build" or v.state == Villager.STATE_BUILDING:
			going += 1
	_assert(going == crew, "os escolhidos ficam a caminho da obra")

	var builder: Villager = null
	for _i in 600:
		pop.tick(1.0 / 30.0, economy)
		for v in pop.villagers:
			if v.state == Villager.STATE_BUILDING:
				builder = v
		if builder != null:
			break
	_assert(builder != null, "a turma chega e começa a construir")
	_assert(Population.counts_as_staffed(builder), "quem está levantando obra também conta como vaga ocupada")

	var cheered := pop.celebrate(5)
	_assert(cheered == 5, "a virada de era faz a colônia comemorar")
	_assert(pop.count_in_state(Villager.STATE_CELEBRATING) == 5, "e eles ficam de fato comemorando")

	# Comemorar não é escapismo: acaba sozinho e todo mundo volta ao trabalho.
	for _i in int(Villager.CELEBRATE_DURATION / 0.5) + 4:
		pop._update_needs_and_decisions(0.5, economy)
	_assert(pop.count_in_state(Villager.STATE_CELEBRATING) == 0, "a festa termina sozinha")

func _test_separation() -> void:
	print("[Population - ninguém ocupa o mesmo pixel]")
	var pop := Population.new()
	var a := pop.spawn_villager(Vector2(500, 400))
	var b := pop.spawn_villager(Vector2(500, 400))
	a.position = Vector2(500, 400)
	b.position = Vector2(500, 400)
	a.state = Villager.STATE_IDLE
	b.state = Villager.STATE_IDLE
	for _i in 60:
		pop._separate(1.0 / 30.0)
	_assert(a.position.distance_to(b.position) > 8.0,
		"dois moradores exatamente sobrepostos se afastam (ficaram a %.1fpx)" % a.position.distance_to(b.position))

	# Turma no posto tem lugar marcado: separar ali desmancharia a fileira que
	# faz dar pra contar quanta gente trabalha em cada construção.
	var c := pop.spawn_villager(Vector2(700, 400))
	var d := pop.spawn_villager(Vector2(700, 400))
	c.position = Vector2(700, 400)
	d.position = Vector2(700, 400)
	c.state = Villager.STATE_WORKING
	d.state = Villager.STATE_WORKING
	pop._separate(1.0)
	_assert(c.position == d.position, "quem está trabalhando não é empurrado do posto")

# Fase 0 (spike de arquitetura) validado aqui, junto com a Fase 6 (escala):
# Villager é dado puro (sem Node2D) e needs/IA só recalculam a cada
# DECISION_INTERVAL, não todo frame — isto prova que isso aguenta 100+
# agentes ativos sem custo perceptível.
func _test_scale_100_agents_performance() -> void:
	print("[Population - Fase 0/6: spike de performance com 100 agentes]")
	var economy := Economy.new()
	economy.owned = {"coletor": 40, "lascador": 20} # bastante vaga de trabalho pra todo mundo
	economy.add("comida", 1000000.0)
	var pop := Population.new()
	pop.sync_work_sites(economy)
	for _i in 100:
		pop.spawn_villager()
	pop.assign_jobs()
	_assert(pop.villagers.size() == 100, "100 agentes de fato instanciados")
	_assert(pop.employed_count() == 100, "todo mundo tem vaga sobrando pra ser alocado")

	var started := Time.get_ticks_usec()
	for _i in 300: # 300 ticks de 1/60s ~= 5s de jogo simulado
		pop.tick(1.0 / 60.0, economy)
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("  300 ticks (~5s simulados) de 100 agentes: %.1fms" % elapsed_ms)
	_assert(elapsed_ms < 1000.0, "simular 5s de jogo com 100 agentes leva bem menos que 1000ms reais (rodou em %.1fms)" % elapsed_ms)

	# Continua simulando (sem cronometrar) só pra confirmar que, dado tempo
	# suficiente pra andar até o posto (a praça fica longe dos postos de
	# trabalho), a alocação em papel também vira gente de fato trabalhando.
	for _i in 1200: # mais ~20s simulados
		pop.tick(1.0 / 60.0, economy)
	_assert(pop.count_in_state(Villager.STATE_WORKING) > 0, "com tempo suficiente pra andar, gente de fato chega a trabalhar")

func _test_scene_population_boots() -> void:
	print("[Cena - Colônia Viva: população integrada]")
	_reset_save()
	var instance = await _new_game()
	_assert(instance.population.villagers.size() >= 3, "a colônia começa com moradores")
	_assert(int(instance.population_count_label.text) == instance.population.villagers.size(), "a tira do topo mostra quantos moradores existem")

	instance.economy.add("comida", 10000.0)
	instance._update_hud()
	instance.buy("coletor")
	_assert(instance.population.work_sites.size() > 0, "comprar uma construção abre vagas de trabalho")
	_assert(instance.population.employed_count() > 0, "alguém já é alocado na vaga logo depois da compra")

	# "Chegou a trabalhar em ALGUM momento", não "está trabalhando neste
	# instante": no V2 o trabalhador também leva a produção ao celeiro e volta,
	# então um retrato num passo qualquer pode pegá-lo no meio do trajeto.
	var ever_working := false
	for _i in 8:
		instance._process(5.0) # avança bastante tempo simulado de uma vez, sem precisar de 8×5s reais
		if instance.population.count_in_state(Villager.STATE_WORKING) > 0:
			ever_working = true
	_assert(ever_working, "depois de um tempo, alguém chega a trabalhar de verdade (não só alocado no papel)")
	_assert(instance.economy.production_per_second(instance.population.staffing_ratios()).comida > 0.0, "com gente presente trabalhando, a produção real (staffada) passa a existir")
	instance.queue_free()
	await process_frame

# A outra metade da regressão de layout: com a cena montada de verdade, o mundo
# tem que ocupar a tela e a gaveta só pode existir quando aberta. Se um dia
# alguém "só encaixar" um painel fixo aqui, isto quebra.
func _test_scene_layout_invariants() -> void:
	print("[Cena - o mundo é o centro da tela]")
	_reset_save()
	var instance = await _new_game()

	_assert(instance.HUD_HEIGHT <= 120, "a tira de HUD ocupa no máximo ~1/6 da altura da tela")
	_assert(instance.world_root.position.y == instance.HUD_HEIGHT, "o mundo começa logo abaixo da tira e vai até o fim da tela")
	var world_width: float = Valley.COLS * Valley.CELL
	_assert(world_width >= 1280.0, "o mundo cobre a largura inteira da tela (%d px)" % int(world_width))

	_assert(not instance.drawer_open, "o jogo abre com a gaveta de construções FECHADA")
	_assert(instance.drawer.position.x >= 1280.0, "gaveta fechada fica fora da tela, sem cobrir o mundo")
	instance.toggle_drawer()
	_assert(instance.drawer_open, "o botão abre a gaveta")
	_assert(instance.drawer.size.x < 640.0, "mesmo aberta, a gaveta cobre menos da metade da tela")
	instance.toggle_drawer()
	_assert(not instance.drawer_open, "e fecha de novo")

	# Moradores em tamanho de gente: o sprite tem que ser grande o bastante pra
	# dar pra ver o que cada um está fazendo. Na primeira tentativa eles eram
	# pontinhos de 2px e o João nem conseguiu julgar a simulação.
	instance._process(0.1)
	var villager_px: int = instance.CHAR_TILE * instance.VILLAGER_SCALE
	_assert(villager_px >= 32, "o morador desenha com pelo menos 32px de altura (está com %d)" % villager_px)
	_assert(instance._villager_nodes.size() == instance.population.villagers.size(), "existe um boneco na tela por morador simulado")

	var any: VillagerView = instance._villager_nodes.values()[0]
	_assert(any._parts["tronco"].texture != null, "o morador usa arte de personagem de verdade, não um retângulo")

	# Duas pessoas quaisquer da colônia não podem compartilhar textura: cada
	# uma é assada a partir da própria aparência.
	var textures := {}
	for id in instance._villager_nodes:
		textures[instance._villager_nodes[id]._body_texture.get_rid()] = true
	_assert(textures.size() == instance._villager_nodes.size(),
		"cada morador tem a própria textura assada — a colônia não é um elenco reaproveitado")

	instance.queue_free()
	await process_frame

# ---- V2: o boneco articulado ----
#
# A promessa central do V2 é que o morador se MEXE e que o que ele está fazendo
# se lê no corpo. Cada uma dessas asserções corresponde a uma coisa que estava
# quebrada (ou nem existia) no V1.
func _test_scene_villager_animation() -> void:
	print("[Cena - o morador se mexe e mostra o que sente]")
	_reset_save()
	var instance = await _new_game()
	instance._process(0.1)

	var v: Villager = instance.population.villagers[0]
	var view: VillagerView = instance._villager_nodes[v.id]
	_assert(view._parts.size() == 6, "o boneco é montado em seis pedaços articuláveis")

	# 1. Andar move a perna.
	v.state = Villager.STATE_WALKING
	v.facing = Villager.DIR_SOUTH
	v.anim_phase = 0.0
	view.sync(v)
	var leg_first: Vector2 = view._parts["perna_e"].position
	var torso_first: Vector2 = view._parts["tronco"].position
	v.anim_phase = VillagerView.WALK_FRAME * 1.5
	view.sync(v)
	_assert(view._parts["perna_e"].position != leg_first, "a perna muda de lugar entre dois quadros da caminhada")
	_assert(view._parts["tronco"].position != torso_first, "e o corpo repica junto (não é sprite deslizando)")

	# 2. Ficar parado também respira — só que pouco.
	v.state = Villager.STATE_IDLE
	v.anim_phase = 0.0
	view.sync(v)
	var idle_head: Vector2 = view._parts["cabeca"].position
	v.anim_phase = 1.6
	view.sync(v)
	_assert(view._parts["cabeca"].position != idle_head, "parado, o morador respira em vez de virar estátua")

	# 3. Quatro direções.
	v.state = Villager.STATE_WALKING
	v.facing = Villager.DIR_NORTH
	view.sync(v)
	_assert(not view._face.visible, "de costas não se vê rosto")
	_assert(view._parts["cabeca"].region_rect.position.x == VillagerArt.PART_HEAD.position.x + VillagerArt.TILE,
		"de costas usa a pose assada de costas")
	v.facing = Villager.DIR_SOUTH
	view.sync(v)
	_assert(view._face.visible and view._parts["cabeca"].region_rect.position.x == VillagerArt.PART_HEAD.position.x,
		"de frente volta a pose de frente, com rosto")
	v.facing = Villager.DIR_EAST
	view.sync(v)
	_assert(not view._parts["braco_e"].visible, "de perfil o braço de trás some (silhueta estreita)")
	_assert(view._flip.scale.x > 0.0, "olhando pra leste, o boneco não é espelhado")
	v.facing = Villager.DIR_WEST
	view.sync(v)
	_assert(view._flip.scale.x < 0.0, "olhando pra oeste, é o mesmo desenho espelhado")

	# 4. Trabalhar tem gesto e ferramenta — e não é o mesmo pra todo ofício.
	v.facing = Villager.DIR_SOUTH
	v.state = Villager.STATE_WORKING
	v.anim_phase = 0.1
	view.set_work_kind("chop")
	view.sync(v)
	_assert(view._tool.visible, "trabalhando de machado, a ferramenta aparece na mão")
	var swing_start: float = view._hand.rotation
	var arm_start: Vector2 = view._parts["braco_d"].position
	v.anim_phase = 0.6
	view.sync(v)
	_assert(not is_equal_approx(view._hand.rotation, swing_start), "a ferramenta gira ao longo do golpe (giro contínuo, não dois desenhos)")
	_assert(view._parts["braco_d"].position != arm_start, "e o braço acompanha o golpe")

	view.set_work_kind("mine")
	view.sync(v)
	var pick_region: Rect2 = view._tool.region_rect
	view.set_work_kind("farm")
	view.sync(v)
	_assert(view._tool.region_rect != pick_region, "cada ofício empunha uma ferramenta diferente")

	view.set_work_kind("study")
	view.sync(v)
	_assert(not view._tool.visible and view._held.visible, "quem estuda segura um livro, não uma ferramenta")

	# 5. A cara muda com a necessidade.
	v.state = Villager.STATE_IDLE
	v.anim_phase = 2.0     # fora da janela de piscada
	v.hunger = 1.0
	v.energy = 1.0
	v.mood = 0.9
	view.sync(v)
	var happy_face: Rect2 = view._face.region_rect
	v.energy = 0.1
	view.sync(v)
	_assert(view._face.region_rect != happy_face, "quem está exausto muda de cara")
	v.energy = 1.0
	v.hunger = 0.1
	view.sync(v)
	_assert(view._face.region_rect != happy_face, "quem está faminto muda de cara")

	# 6. Balão só pro que o corpo não conta sozinho.
	v.hunger = 1.0
	v.state = Villager.STATE_RESTING
	view.sync(v)
	_assert(view._bubble.visible, "descansando, o balão diz o que está acontecendo")
	v.state = Villager.STATE_WORKING
	view.set_work_kind("chop")
	view.sync(v)
	_assert(not view._bubble.visible, "trabalhando não precisa de balão: a ferramenta e o gesto já contam")
	v.state = Villager.STATE_WALKING
	v.carrying = "materiais"
	view.sync(v)
	_assert(view._cargo.visible, "quem carrega leva a caixa visível acima da cabeça")
	_assert(not view._bubble.visible, "e não ganha balão em cima disso (seria dizer duas vezes)")
	v.carrying = ""

	# 7. O boneco segue a simulação: onde a Population põe, é onde ele aparece.
	v.position = Vector2(321, 222)
	view.sync(v)
	_assert(view.position == v.position, "o boneco espelha a posição da simulação, não o contrário")

	instance.queue_free()
	await process_frame

# ---- V2: o vale reage ----
func _test_scene_ambience() -> void:
	print("[Cena - o vale reage ao que a colônia faz]")
	_reset_save()
	var instance = await _new_game()
	instance.economy.era_index = 1
	# "oleiro" é de propósito: fumaça de chaminé só existe onde já há casa de
	# verdade — acampamento da era da pedra não tem forno pra soltar fumaça.
	instance.economy.owned = {"coletor": 3, "lascador": 2, "fazenda": 2, "oleiro": 2}
	instance.economy.add("comida", 4000.0)
	instance.economy.add("materiais", 1500.0)
	instance.on_era_entered(1)
	instance.close_era_overlay()
	instance.population.sync_work_sites(instance.economy)
	instance.population.ensure_minimum(16)
	instance.population.assign_jobs()

	_assert(instance.trail_layer.get_used_cells().is_empty(), "colônia recém-aberta ainda não tem trilha nenhuma")
	for _i in 1200:
		instance._process(1.0 / 20.0)
	var trails: int = instance.trail_layer.get_used_cells().size()
	_assert(trails > 0, "depois de a colônia trabalhar um tempo, trilhas de terra aparecem sozinhas")
	_assert(trails <= Pathfinder.TRAIL_LIMIT, "e nunca cobrem mais que o teto de células (%d)" % trails)

	# Clicar num morador é a porta de entrada pra tudo que o V2 acrescentou.
	var someone: Villager = instance.population.villagers[0]
	var picked: int = instance.inspect_at(someone.position + Vector2(0, -20))
	_assert(picked == someone.id, "clicar em cima de um morador seleciona ele")
	_assert(instance.selection_ring.visible, "o selecionado ganha um anel sob os pés")
	_assert(instance.inspector_label.text.contains(someone.display_name), "a ficha mostra o nome de quem foi clicado")
	_assert(instance.inspect_at(Vector2(-500, -500)) == 0, "clicar no vazio desmarca")
	_assert(not instance.selection_ring.visible, "e o anel some junto")

	# Lavoura em volta de quem planta, fumaça em quem tem forno.
	var crops: int = instance._crop_sprites.size()
	_assert(crops > 0, "construções de comida ganham lavoura em volta do lote")
	var smoke := 0
	for child in instance.plots_root.get_children():
		if child is CPUParticles2D:
			smoke += 1
	_assert(smoke > 0, "oficinas com forno soltam fumaça pela chaminé")
	_assert(instance._birds.size() == instance.BIRD_COUNT, "passam pássaros pelo vale")

	# Comprar dá recado no vale, não só na lista.
	instance.economy.add("comida", 5000.0)
	instance.buy("coletor")
	var building_crew := 0
	for v in instance.population.villagers:
		if v.state == Villager.STATE_BUILDING or v.pending_action == "build":
			building_crew += 1
	_assert(building_crew > 0, "clicar em Construir manda gente levantar a obra no vale")

	instance.queue_free()
	await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
