class_name PlayingState
extends State

# O incêndio andando. Este estado não sabe nada sobre fogo: ele empurra o
# relógio da Mission e observa o veredito. Toda a regra mora em Mission, toda a
# física em FireSim — é o que permite o bot dos testes jogar a mesma partida
# sem cena nenhuma.

var main: Node = null

func enter(_params: Dictionary = {}) -> void:
	main.screen = "playing"

func update(delta: float) -> void:
	if main.mission == null:
		return
	if main.bot_active:
		main.bot.update(delta * main.mission.speed())
	main.mission.update(delta)
	main.refresh_forecast(delta)
	main.queue_redraw()
	if main.mission.phase != Mission.PLAYING:
		transitioned.emit(self, "result", {})

func handle_input(event: InputEvent) -> void:
	main.handle_play_input(event)
