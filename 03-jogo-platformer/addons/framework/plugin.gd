@tool
extends EditorPlugin

const AUTOLOADS := {
	"SceneManager": "res://addons/framework/scene_manager.gd",
	"SaveSystem": "res://addons/framework/save_system.gd",
	"AudioManager": "res://addons/framework/audio_manager.gd",
	"UITheme": "res://addons/framework/ui_theme.gd",
}

func _enter_tree() -> void:
	for autoload_name in AUTOLOADS:
		add_autoload_singleton(autoload_name, AUTOLOADS[autoload_name])

func _exit_tree() -> void:
	for autoload_name in AUTOLOADS:
		remove_autoload_singleton(autoload_name)
