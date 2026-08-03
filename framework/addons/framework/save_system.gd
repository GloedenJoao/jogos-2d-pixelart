extends Node

signal save_loaded
signal save_written

const SAVE_PATH := "user://save.json"

var data: Dictionary = {}

func _ready() -> void:
	load_data()

func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: falha ao abrir save para escrita (erro %d)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	save_written.emit()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		data = {}
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	data = parsed if parsed is Dictionary else {}
	save_loaded.emit()

func set_value(key: String, value) -> void:
	data[key] = value

func get_value(key: String, default = null):
	return data.get(key, default)

func has_value(key: String) -> bool:
	return data.has(key)

func clear() -> void:
	data = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
