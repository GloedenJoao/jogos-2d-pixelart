extends Control

@onready var back_button: Button = %BackButton

func _ready() -> void:
	theme = UITheme.theme
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	SceneManager.change_scene("res://scenes/menu.tscn")
