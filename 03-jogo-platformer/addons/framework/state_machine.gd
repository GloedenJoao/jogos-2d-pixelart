class_name StateMachine
extends Node

@export var initial_state: State

var current_state: State
var states: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.state_machine = self
			child.transitioned.connect(_on_state_transitioned)

	if initial_state == null and get_child_count() > 0:
		initial_state = get_child(0)

	if initial_state:
		current_state = initial_state
		current_state.enter()

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func transition_to(state_name: String, params: Dictionary = {}) -> void:
	var next: State = states.get(state_name.to_lower())
	if next == null:
		push_warning("StateMachine: estado desconhecido '%s'" % state_name)
		return
	if current_state:
		current_state.exit()
	current_state = next
	current_state.enter(params)

func _on_state_transitioned(state: State, next_state_name: String, params: Dictionary) -> void:
	if state == current_state:
		transition_to(next_state_name, params)
