extends Node2D

@export_node_path("TileMapLayer") var ground_path: NodePath = ^"Ground"
@export_node_path("Camera2D") var camera_path: NodePath = ^"Camera2D"
@export var server_scene: PackedScene = preload("res://server.tscn")

@onready var ground: TileMapLayer = get_node(ground_path) as TileMapLayer
@onready var camera: Camera2D = get_node_or_null(camera_path) as Camera2D

var server_instance: Node2D
var server_anchor_cell: Vector2i

func _ready() -> void:
	if ground == null:
		push_error("Level: Ground TileMapLayer not found.")
		return
	_spawn_server()
	_center_camera_on_server()

func get_server() -> Node2D:
	return server_instance

func get_server_occupied_cells() -> Array[Vector2i]:
	if server_instance == null or not server_instance.has_method("get_occupied_cells"):
		return []
	return server_instance.get_occupied_cells(server_anchor_cell)

func _spawn_server() -> void:
	if server_scene == null:
		push_error("Level: server_scene is not assigned.")
		return
	if server_instance != null:
		server_instance.queue_free()
	server_instance = server_scene.instantiate() as Node2D
	if server_instance == null:
		push_error("Level: Failed to instantiate server scene.")
		return
	add_child(server_instance)
	server_anchor_cell = _get_map_center_anchor_cell()
	server_instance.global_position = _get_footprint_center_world(server_anchor_cell, Vector2i(3, 3))
	if server_instance.has_method("set_footprint_size"):
		server_instance.set_footprint_size(_get_cell_world_size() * Vector2(3, 3))

func _center_camera_on_server() -> void:
	if camera == null or server_instance == null:
		return
	camera.global_position = server_instance.global_position
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()

func _get_map_center_anchor_cell() -> Vector2i:
	var used_rect := ground.get_used_rect()
	var center_local := used_rect.position + Vector2i(used_rect.size.x >> 1, used_rect.size.y >> 1)
	return Vector2i(center_local)

func _get_footprint_center_world(anchor_cell: Vector2i, footprint: Vector2i) -> Vector2:
	var start := anchor_cell - Vector2i(footprint.x >> 1, footprint.y >> 1)
	var end := start + footprint - Vector2i.ONE
	var start_world := _get_cell_center_world(start)
	var end_world := _get_cell_center_world(end)
	return (start_world + end_world) * 0.5

func _get_cell_center_world(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))

func _get_cell_world_size() -> Vector2:
	return Vector2(ground.tile_set.tile_size) * ground.global_scale
