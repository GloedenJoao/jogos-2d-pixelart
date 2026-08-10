extends Node2D

# Fase 0: só o scaffold do projeto. Não há jogo pra jogar ainda — a mecânica
# em validação (o autômato de água) é testada headless em tests/run_tests.gd.
# Este texto existe só pra quem abrir o projeto no editor não achar que travou.

func _ready() -> void:
	var label := Label.new()
	label.text = "Reino em Construção — Fase 0 (fundação técnica)\nSem jogo ainda: ver tests/run_tests.gd"
	label.position = Vector2(40, 40)
	add_child(label)
