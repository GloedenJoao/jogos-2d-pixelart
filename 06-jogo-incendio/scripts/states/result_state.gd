class_name ResultState
extends State

# Vitória ou derrota. Grava o progresso na entrada (uma vez, não a cada frame)
# e deixa o vale à mostra por trás do painel: ver ONDE o fogo passou é metade
# do aprendizado, e um painel opaco cobrindo o mapa apagaria justamente a
# prova do que deu errado.

var main: Node = null

func enter(_params: Dictionary = {}) -> void:
	main.screen = "result"
	main.commit_result()
	main.queue_redraw()

func handle_input(event: InputEvent) -> void:
	if main.is_restart(event):
		main.start_level(main.level_index)
		transitioned.emit(self, "briefing", {})
		return
	if main.is_confirm(event):
		# Vitória avança; derrota repete. Sem menu no meio: a fase seguinte (ou
		# a mesma) começa na tela de briefing, que é onde se decide o plano.
		if main.mission.phase == Mission.WON and main.level_index + 1 < Levels.count():
			main.start_level(main.level_index + 1)
		else:
			main.start_level(main.level_index)
		transitioned.emit(self, "briefing", {})
