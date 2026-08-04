extends SceneTree

# Testes headless do jogo de civilização: primeiro a matemática pura (Economy),
# depois a cena (UI, StateMachine de eras, save/load e progresso offline).

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	_test_catalogs()
	_test_clicks()
	_test_production()
	_test_costs_and_buying()
	_test_era_advance()
	_test_offline_progress()
	_test_save_roundtrip()
	_test_formatting()
	await _test_scene_boots()
	await _test_scene_gather_and_build()
	await _test_scene_era_advance()
	await _test_scene_save_and_reload()
	await _test_scene_offline_on_load()
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
	save_system.data.erase("civilizacao")
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
	_assert(instance.village_root.get_child_count() > 0, "a vila ganha sprites das construções")
	_assert(instance.economy.production_per_second().comida > 0.0, "a produção por segundo passa a existir")
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
	save_system.set_value("civilizacao", {
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

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
