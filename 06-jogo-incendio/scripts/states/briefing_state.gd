class_name BriefingState
extends State

# A tela que aparece antes de o relógio começar.
#
# Existe porque este jogo é sobre PREVER, e prever exige saber as regras da
# fase antes de o fogo andar. Um jogador que descobre o vento depois de já ter
# cavado do lado errado não perdeu por falta de habilidade — perdeu por falta
# de informação, que é o único tipo de derrota que um jogo de sistema não pode
# se dar ao luxo de causar.
#
# Nada de contagem regressiva: o incêndio só começa quando o jogador diz.

var main: Node = null

func enter(_params: Dictionary = {}) -> void:
	main.screen = "briefing"
	main.queue_redraw()

func handle_input(event: InputEvent) -> void:
	if main.is_confirm(event):
		transitioned.emit(self, "playing", {})
