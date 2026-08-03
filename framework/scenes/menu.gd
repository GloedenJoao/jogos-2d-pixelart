extends Control

const EM_BREVE_SCENE := "res://scenes/em_breve.tscn"

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var best_score_label: Label = %BestScoreLabel

func _ready() -> void:
	theme = UITheme.theme

	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	music_slider.value = SaveSystem.get_value("music_volume", 0.8)
	sfx_slider.value = SaveSystem.get_value("sfx_volume", 0.8)
	AudioManager.set_music_volume(music_slider.value)
	AudioManager.set_sfx_volume(sfx_slider.value)

	var best_score: int = SaveSystem.get_value("best_score", 0)
	best_score_label.text = "Melhor pontuação: %d" % best_score

func _on_play_pressed() -> void:
	SceneManager.change_scene(EM_BREVE_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	SaveSystem.set_value("music_volume", value)
	SaveSystem.save_data()

func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	SaveSystem.set_value("sfx_volume", value)
	SaveSystem.save_data()
