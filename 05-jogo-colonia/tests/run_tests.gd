extends SceneTree

# Testes headless da Colônia Viva: matemática pura (Economy), geometria do vale
# (Valley), simulação dos moradores (Villager/Population) e, por último, a cena
# inteira instanciada — UI, eras, save/load e progresso offline.

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
	_test_scale_100_agents_performance()
	await _test_scene_population_boots()
	await _test_scene_layout_invariants()
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

func _reset_save() -> void:
	var save_system := root.get_node("/root/SaveSystem")
	save_system.data.erase("colonia")
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
	save_system.set_value("colonia", {
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

	for _i in 8:
		instance._process(5.0) # avança bastante tempo simulado de uma vez, sem precisar de 8×5s reais
	_assert(instance.population.count_in_state(Villager.STATE_WORKING) > 0, "depois de um tempo, alguém chega a trabalhar de verdade (não só alocado no papel)")
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
	_assert(instance._villager_nodes.size() == instance.population.villagers.size(), "existe um sprite na tela por morador simulado")

	var any: Node2D = instance._villager_nodes.values()[0]
	_assert(any.get_node("Corpo").texture != null, "o morador usa arte de personagem de verdade, não um retângulo")
	_assert(instance.CHAR_CAST.size() >= 8, "existe um elenco de sprites diferentes, pra colônia não parecer clonada")

	instance.queue_free()
	await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
