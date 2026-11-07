extends Node

signal wave_started(wave_number: int)
signal wave_cleared(next_wave_number: int)
signal wave_updated(wave_number: int, enemies_remaining: int, state: String)

enum WaveState {
	WAITING,
	SPAWNING,
	IN_PROGRESS,
	CLEARED
}

@export_node_path("Node") var enemy_spawner_path: NodePath = ^"../EnemySpawner"
@export_node_path("Node") var email_event_manager_path: NodePath = ^"../EmailEventManager"
@export_node_path("Button") var start_wave_button_path: NodePath = ^"../BuildModeUI/StartWaveButton"
@export_node_path("Label") var wave_label_path: NodePath = ^"../BuildModeUI/WaveLabel"
@export_node_path("ProgressBar") var wave_progress_bar_path: NodePath = ^"../BuildModeUI/WaveProgressBar"
@export var starting_enemy_count: int = 3
@export var enemies_added_per_wave: int = 2
@export var health_increase_per_wave: float = 0.08
@export var damage_increase_per_wave: float = 0.05
@export var spawn_interval: float = 1.0
@export var base_enemy_health: float = 50.0
@export var base_enemy_damage: float = 10.0

@onready var enemy_spawner: Node = get_node_or_null(enemy_spawner_path)
@onready var email_event_manager: Node = get_node_or_null(email_event_manager_path)
@onready var start_wave_button: Button = get_node_or_null(start_wave_button_path)
@onready var wave_label: Label = get_node_or_null(wave_label_path)
@onready var wave_progress_bar: ProgressBar = get_node_or_null(wave_progress_bar_path)

var current_wave: int = 1
var state: int = WaveState.WAITING
var _spawn_timer: SceneTreeTimer = null
var _active_wave_id: int = 0
var _enemies_to_spawn: int = 0
var _enemies_spawned: int = 0
var _tracked_enemies: Dictionary = {}
var _wave_completed: bool = false

func _ready() -> void:
	Global.GlobalWaves = current_wave
	if start_wave_button != null and not start_wave_button.pressed.is_connected(_on_start_wave_pressed):
		start_wave_button.pressed.connect(_on_start_wave_pressed)
	if email_event_manager != null and email_event_manager.has_signal("email_event_finished") and not email_event_manager.email_event_finished.is_connected(_on_email_event_finished):
		email_event_manager.email_event_finished.connect(_on_email_event_finished)
	_update_ui()

func _on_start_wave_pressed() -> void:
	start_current_wave()

func start_current_wave() -> void:
	if state == WaveState.SPAWNING or state == WaveState.IN_PROGRESS:
		return
	if enemy_spawner == null or not enemy_spawner.has_method("spawn_enemy_for_wave"):
		push_error("WaveManager: EnemySpawner missing or incompatible.")
		return
	_wave_completed = false
	_tracked_enemies.clear()
	_active_wave_id += 1
	_enemies_spawned = 0
	_enemies_to_spawn = get_enemy_count_for_wave(current_wave)
	state = WaveState.SPAWNING
	Global.GlobalWaves = current_wave
	if start_wave_button != null:
		start_wave_button.visible = false
	emit_signal("wave_started", current_wave)
	_update_ui()
	_call_spawn_loop(_active_wave_id)

func get_enemy_count_for_wave(wave_number: int) -> int:
	return max(1, starting_enemy_count + (wave_number - 1) * enemies_added_per_wave)

func get_enemy_health_for_wave(wave_number: int) -> float:
	return base_enemy_health * (1.0 + health_increase_per_wave * float(max(wave_number - 1, 0)))

func get_enemy_damage_for_wave(wave_number: int) -> float:
	return base_enemy_damage * (1.0 + damage_increase_per_wave * float(max(wave_number - 1, 0)))

func _call_spawn_loop(wave_id: int) -> void:
	_spawn_next_enemy(wave_id)

func _spawn_next_enemy(wave_id: int) -> void:
	if wave_id != _active_wave_id:
		return
	if state != WaveState.SPAWNING:
		return
	if _enemies_spawned >= _enemies_to_spawn:
		state = WaveState.IN_PROGRESS
		_update_ui()
		_check_wave_completion()
		return
	var stats: Dictionary = {
		"max_health": get_enemy_health_for_wave(current_wave),
		"attack_damage": get_enemy_damage_for_wave(current_wave)
	}
	var enemy = enemy_spawner.spawn_enemy_for_wave(stats)
	if enemy != null:
		_register_enemy(enemy)
		_enemies_spawned += 1
		_update_ui()
	_spawn_timer = get_tree().create_timer(max(spawn_interval, 0.05))
	_spawn_timer.timeout.connect(func() -> void:
		_spawn_next_enemy(wave_id)
	)

func _register_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id: int = enemy.get_instance_id()
	if _tracked_enemies.has(id):
		return
	_tracked_enemies[id] = enemy
	if enemy.has_signal("died") and not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.tree_exited.is_connected(_on_enemy_tree_exited.bind(id)):
		enemy.tree_exited.connect(_on_enemy_tree_exited.bind(id))

func _on_enemy_died(enemy: Node) -> void:
	_unregister_enemy(enemy)

func _on_enemy_tree_exited(enemy_id: int) -> void:
	_tracked_enemies.erase(enemy_id)
	_check_wave_completion()
	_update_ui()

func _unregister_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	_tracked_enemies.erase(enemy.get_instance_id())
	_check_wave_completion()
	_update_ui()

func _get_active_enemy_count() -> int:
	var invalid_ids: Array = []
	for enemy_id in _tracked_enemies.keys():
		var enemy: Node = _tracked_enemies[enemy_id]
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			invalid_ids.append(enemy_id)
	for enemy_id in invalid_ids:
		_tracked_enemies.erase(enemy_id)
	return _tracked_enemies.size()

func _check_wave_completion() -> void:
	if _wave_completed:
		return
	if state == WaveState.WAITING or state == WaveState.CLEARED:
		return
	if _enemies_spawned < _enemies_to_spawn:
		return
	if _get_active_enemy_count() > 0:
		return
	_wave_completed = true
	state = WaveState.CLEARED
	_heal_all_structures_after_wave()
	current_wave += 1
	Global.GlobalWaves = current_wave
	if start_wave_button != null:
		start_wave_button.text = "Start Wave %d" % current_wave
		start_wave_button.visible = false
	_update_ui()
	if email_event_manager != null and email_event_manager.has_method("show_random_email_event"):
		email_event_manager.show_random_email_event()
	else:
		_on_email_event_finished()

func _heal_all_structures_after_wave() -> void:
	var level := get_parent()
	if level == null or not level.has_method("get_all_structure_nodes"):
		return
	for structure in level.get_all_structure_nodes():
		if structure == null or not is_instance_valid(structure):
			continue
		if structure.has_method("heal"):
			var max_health_value = structure.get("max_health")
			var current_health_value = structure.get("current_health")
			if max_health_value is float or max_health_value is int:
				var missing_health: float = float(max_health_value) - float(current_health_value)
				if missing_health > 0.0:
					structure.heal(missing_health)
			continue
		if structure.has_meta("max_health"):
			var firewall_max_health: float = float(structure.get_meta("max_health", 0.0))
			structure.set_meta("current_health", firewall_max_health)
			if structure.has_method("_update_health_bar"):
				structure.call("_update_health_bar")
			continue
		if structure.get("max_health") != null:
			structure.current_health = structure.max_health
			if structure.has_method("_update_health_bar"):
				structure.call("_update_health_bar")

func _on_email_event_finished() -> void:
	if start_wave_button != null:
		start_wave_button.text = "Start Wave %d" % current_wave
		start_wave_button.visible = true
	emit_signal("wave_cleared", current_wave)
	state = WaveState.WAITING
	_update_ui()

func _update_ui() -> void:
	var enemies_remaining: int = max(0, (_enemies_to_spawn - _enemies_spawned) + _get_active_enemy_count()) if state == WaveState.SPAWNING else _get_active_enemy_count()
	var total_wave_enemies: int = max(_enemies_to_spawn, get_enemy_count_for_wave(current_wave))
	var enemies_cleared: int = max(0, total_wave_enemies - enemies_remaining) if state == WaveState.SPAWNING or state == WaveState.IN_PROGRESS else 0
	if start_wave_button != null:
		start_wave_button.text = "Start Wave %d" % current_wave
		if email_event_manager != null and email_event_manager.get("_awaiting_response"):
			start_wave_button.visible = false
		else:
			start_wave_button.visible = state == WaveState.WAITING or state == WaveState.CLEARED
	if wave_label != null:
		wave_label.text = "Wave %d" % current_wave
	if wave_progress_bar != null:
		wave_progress_bar.min_value = 0
		wave_progress_bar.max_value = max(1, total_wave_enemies)
		wave_progress_bar.value = enemies_cleared
		wave_progress_bar.visible = state == WaveState.SPAWNING or state == WaveState.IN_PROGRESS
	emit_signal("wave_updated", current_wave, enemies_remaining, _state_to_string(state))

func _state_to_string(value: int) -> String:
	match value:
		WaveState.WAITING:
			return "WAITING"
		WaveState.SPAWNING:
			return "SPAWNING"
		WaveState.IN_PROGRESS:
			return "IN_PROGRESS"
		WaveState.CLEARED:
			return "CLEARED"
		_:
			return "UNKNOWN"
