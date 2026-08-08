extends SceneTree

# Ferramenta de balanceamento: põe o bot pra jogar cada fase e reporta o placar,
# e depois roda tudo de novo SEM ninguém fazer nada.
#
# As duas metades importam. A primeira responde "dá pra vencer?"; a segunda,
# "precisa jogar?". Uma fase que se resolve sozinha passa despercebida se você
# só olhar a primeira. Não faz parte da suíte — o teste formal fica em
# run_tests.gd, que cobra as duas.

const STEP := 0.1
const LIMIT := 900.0

func _initialize() -> void:
	await process_frame
	for i in Levels.count():
		_play(i, true)
	print("")
	print("--- sem interferencia nenhuma (o que acontece se ninguem fizer nada) ---")
	for i in Levels.count():
		_play(i, false)
	quit(0)

func _play(index: int, use_bot: bool) -> void:
	var mission := Mission.new()
	mission.start(index)
	var bot := ContainmentBot.new()
	bot.setup(mission)

	var t := 0.0
	while mission.phase == Mission.PLAYING and t < LIMIT:
		if use_bot:
			bot.update(STEP)
		mission.update(STEP)
		t += STEP

	var s := mission.summary()
	var verdict := "VENCEU" if mission.phase == Mission.WON else ("PERDEU" if mission.phase == Mission.LOST else "ESTOUROU O TEMPO")
	print("%d %-12s %-8s casas=%d/%d(meta %d) civis=%d/%d queimou=%4d/%4d t=%5.1fs ordens=%d/%d(perd %d) brig=%d %s" % [
		index + 1, mission.level["id"], verdict,
		s["houses"], s["houses_total"], mission.goal_houses(),
		s["saved"], s["civilians"], s["burnt"], mission.sim.cols * mission.sim.rows,
		s["time"], mission.agents.orders_done, mission.agents.orders_given,
		mission.agents.orders_lost, mission.agents.crew.size(), mission.outcome,
	])
