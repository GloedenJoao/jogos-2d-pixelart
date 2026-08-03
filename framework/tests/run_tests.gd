extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _test_menu_scene()
	await _test_em_breve_scene()
	await _test_save_system()
	await _test_audio_manager()
	await _test_state_machine()
	_report()

func _assert(cond: bool, message: String) -> void:
	if cond:
		_pass += 1
		print("  OK   - %s" % message)
	else:
		_fail += 1
		print("  FAIL - %s" % message)

func _test_menu_scene() -> void:
	print("[menu.tscn]")
	var packed: PackedScene = load("res://scenes/menu.tscn")
	_assert(packed != null, "carrega sem erro")
	var instance: Control = packed.instantiate()
	_assert(instance != null, "instancia sem erro")
	root.add_child(instance)
	await process_frame

	_assert(instance.get_node_or_null("%PlayButton") != null, "PlayButton existe")
	_assert(instance.get_node_or_null("%QuitButton") != null, "QuitButton existe")
	_assert(instance.get_node_or_null("%MusicSlider") != null, "MusicSlider existe")
	_assert(instance.get_node_or_null("%SfxSlider") != null, "SfxSlider existe")
	_assert(instance.get_node_or_null("%BestScoreLabel") != null, "BestScoreLabel existe")
	_assert(instance.theme != null, "UITheme foi aplicado (theme != null)")

	var slider: HSlider = instance.get_node("%MusicSlider")
	slider.value = 0.35 # múltiplo do step (0.05) do slider — evita arredondamento no assert
	await process_frame
	var save_system := root.get_node("/root/SaveSystem")
	_assert(is_equal_approx(save_system.get_value("music_volume", -1.0), 0.35), "slider de música grava no SaveSystem")

	instance.queue_free()
	await process_frame

func _test_em_breve_scene() -> void:
	print("[em_breve.tscn]")
	var packed: PackedScene = load("res://scenes/em_breve.tscn")
	_assert(packed != null, "carrega sem erro")
	var instance: Control = packed.instantiate()
	root.add_child(instance)
	await process_frame
	_assert(instance.get_node_or_null("%BackButton") != null, "BackButton existe")
	instance.queue_free()
	await process_frame

func _test_save_system() -> void:
	print("[SaveSystem]")
	var save_system := root.get_node("/root/SaveSystem")
	save_system.set_value("_test_key", 123)
	save_system.save_data()
	save_system.data.clear()
	save_system.load_data()
	_assert(save_system.get_value("_test_key", null) == 123, "set_value/save_data/load_data mantêm o valor")
	save_system.data.erase("_test_key")
	save_system.save_data()

func _test_audio_manager() -> void:
	print("[AudioManager]")
	var audio := root.get_node("/root/AudioManager")
	audio.set_music_volume(0.5)
	_assert(is_equal_approx(audio.get_music_volume(), 0.5), "set/get_music_volume consistente")
	audio.set_sfx_volume(0.3)
	_assert(is_equal_approx(audio.get_sfx_volume(), 0.3), "set/get_sfx_volume consistente")

func _test_state_machine() -> void:
	print("[StateMachine]")
	var sm := StateMachine.new()
	var state_a := State.new()
	state_a.name = "A"
	var state_b := State.new()
	state_b.name = "B"
	sm.add_child(state_a)
	sm.add_child(state_b)
	root.add_child(sm)
	await process_frame
	_assert(sm.current_state == state_a, "estado inicial é o primeiro filho")
	sm.transition_to("b")
	_assert(sm.current_state == state_b, "transition_to muda de estado")
	sm.queue_free()
	await process_frame

func _report() -> void:
	print("")
	print("Resultado: %d passou, %d falhou" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
