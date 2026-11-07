extends Node2D

@export var enemy_scene: PackedScene = preload("res://Enemies/enemy.tscn")
@export_node_path("Camera2D") var camera_path: NodePath = ^"../Camera2D"
@export_node_path("TileMapLayer") var ground_path: NodePath = ^"../Ground"
@export_node_path("Node2D") var enemies_container_path: NodePath = ^"../Enemies"
@export var spawn_interval: float = 3.0
@export var max_enemies: int = 30
@export var spawn_offset: float = 32.0
@export var max_spawn_attempts: int = 20

@onready var camera: Camera2D = get_node_or_null(camera_path) as Camera2D
@onready var ground: TileMapLayer = get_node_or_null(ground_path) as TileMapLayer
@onready var enemies_container: Node2D = get_node_or_null(enemies_container_path) as Node2D
@onready var spawn_timer: Timer = $SpawnTimer

var active_enemies: Array[Node] = []
var level: Node

func _ready() -> void:
	randomize()
	level = get_parent()
	spawn_timer.wait_time = max(spawn_interval, 0.1)
	spawn_timer.one_shot = false
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.start()

func _on_spawn_timer_timeout() -> void:
	_cleanup_enemy_list()
	if enemy_scene == null or camera == null or ground == null or enemies_container == null:
		return
	if active_enemies.size() >= max_enemies:
		return
	var spawn_result := _find_spawn_position()
	if not spawn_result.get("success", false):
		return
	var enemy := enemy_scene.instantiate()
	if enemy == null:
		return
	enemies_container.add_child(enemy)
	enemy.global_position = spawn_result.get("position", Vector2.ZERO)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	active_enemies.append(enemy)

func _on_enemy_died(enemy: Node) -> void:
	active_enemies.erase(enemy)

func _cleanup_enemy_list() -> void:
	active_enemies = active_enemies.filter(func(enemy: Node) -> bool: return enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion())

func _find_spawn_position() -> Dictionary:
	var rect := _get_camera_world_rect()
	var used_rect := ground.get_used_rect()
	for _i in range(max_spawn_attempts):
		var side := randi() % 4
		var world_position := Vector2.ZERO
		match side:
			0:
				world_position = Vector2(randf_range(rect.position.x, rect.end.x), rect.position.y - spawn_offset)
			1:
				world_position = Vector2(randf_range(rect.position.x, rect.end.x), rect.end.y + spawn_offset)
			2:
				world_position = Vector2(rect.position.x - spawn_offset, randf_range(rect.position.y, rect.end.y))
			3:
				world_position = Vector2(rect.end.x + spawn_offset, randf_range(rect.position.y, rect.end.y))
		var local := ground.to_local(world_position)
		var cell := ground.local_to_map(local)
		cell.x = clampi(cell.x, used_rect.position.x, used_rect.position.x + used_rect.size.x - 1)
		cell.y = clampi(cell.y, used_rect.position.y, used_rect.position.y + used_rect.size.y - 1)
		if level != null and level.has_method("is_cell_occupied") and level.is_cell_occupied(cell):
			continue
		var adjusted_world := ground.to_global(ground.map_to_local(cell))
		if level != null and level.has_method("is_world_position_near_structure") and level.is_world_position_near_structure(adjusted_world, 12.0):
			continue
		return {"success": true, "position": adjusted_world}
	return {"success": false, "position": Vector2.ZERO}

func _get_camera_world_rect() -> Rect2:
	var viewport := get_viewport()
	var visible_size := viewport.get_visible_rect().size
	var zoom := camera.zoom
	var size := Vector2(visible_size.x * zoom.x, visible_size.y * zoom.y)
	var center := camera.get_screen_center_position()
	return Rect2(center - size * 0.5, size)
