extends Node2D

@export_node_path("TileMapLayer") var ground_path: NodePath = ^"Ground"
@export_node_path("Camera2D") var camera_path: NodePath = ^"Camera2D"
@export_node_path("Node2D") var build_system_path: NodePath = ^"BuildSystem"
@export var server_scene: PackedScene = preload("res://server.tscn")
@export var death_scene_path: String = "res://death.tscn"
@export var server_footprint_cells: Vector2i = Vector2i(5, 5)
@export var server_position_offset: Vector2 = Vector2(0.0, 24.0)

@onready var ground: TileMapLayer = get_node(ground_path) as TileMapLayer
@onready var camera: Camera2D = get_node_or_null(camera_path) as Camera2D
@onready var build_system: Node2D = get_node_or_null(build_system_path) as Node2D

var server_instance: Node2D
var server_anchor_cell: Vector2i
var _game_over_triggered := false

func _ready() -> void:
	if ground == null:
		push_error("Level: Ground TileMapLayer not found.")
		return
	_spawn_server()
	_center_camera_on_server()

func get_server() -> Node2D:
	return server_instance

func get_server_occupied_cells() -> Array[Vector2i]:
	if server_instance == null or not is_instance_valid(server_instance) or not server_instance.has_method("get_occupied_cells"):
		return []
	return server_instance.get_occupied_cells(server_anchor_cell)

func get_all_structure_nodes() -> Array[Node]:
	var result: Array[Node] = []
	if server_instance != null and is_instance_valid(server_instance) and (not server_instance.has_method("is_structure_alive") or server_instance.is_structure_alive()):
		result.append(server_instance)
	if build_system != null and build_system.has_method("get_structure_nodes"):
		for node in build_system.get_structure_nodes():
			if node != null and is_instance_valid(node):
				result.append(node)
	return result

func has_player_blocks() -> bool:
	if build_system == null or not build_system.has_method("get_structure_nodes"):
		return false
	for node in build_system.get_structure_nodes():
		if node != null and is_instance_valid(node):
			if not node.has_method("is_structure_alive") or node.is_structure_alive():
				return true
	return false

func is_cell_occupied(cell: Vector2i) -> bool:
	if build_system != null and build_system.has_method("has_occupied_cell") and build_system.has_occupied_cell(cell):
		return true
	return cell in get_server_occupied_cells()

func is_world_position_near_structure(world_position: Vector2, padding: float = 0.0) -> bool:
	for structure in get_all_structure_nodes():
		if structure == null or not is_instance_valid(structure):
			continue
		var radius: float = 16.0
		if structure.has_method("get_attack_radius"):
			radius = float(structure.get_attack_radius())
		if structure.global_position.distance_to(world_position) <= radius + padding:
			return true
	return false

func find_nearest_structure_target(from_world: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF

	for structure in get_all_structure_nodes():
		if structure == null or not is_instance_valid(structure):
			continue
		if structure.has_method("is_structure_alive") and not structure.is_structure_alive():
			continue

		var cells: Array[Vector2i] = _get_structure_cells(structure)
		if cells.is_empty():
			var distance_to_node: float = from_world.distance_squared_to(structure.global_position)
			if distance_to_node < best_distance:
				best_distance = distance_to_node
				best = {"node": structure, "cell": Vector2i.ZERO, "world_position": structure.global_position}
			continue

		for cell in cells:
			var world: Vector2 = _get_cell_center_world(cell)
			var distance: float = from_world.distance_squared_to(world)
			if distance < best_distance:
				best_distance = distance
				best = {"node": structure, "cell": cell, "world_position": world}

	if best.is_empty() and server_instance != null and is_instance_valid(server_instance):
		if not server_instance.has_method("is_structure_alive") or server_instance.is_structure_alive():
			best = {
				"node": server_instance,
				"cell": server_anchor_cell,
				"world_position": server_instance.global_position
			}
	return best

func _get_structure_cells(structure: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if structure == null or not is_instance_valid(structure) or not structure.has_method("get_occupied_cells"):
		return cells
	if structure == server_instance:
		return structure.get_occupied_cells(server_anchor_cell)
	var result = structure.call("get_occupied_cells")
	if result is Array:
		for cell in result:
			cells.append(cell)
	return cells

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
	server_instance.global_position = _get_footprint_center_world(server_anchor_cell, server_footprint_cells) + server_position_offset
	if server_instance.has_method("set_footprint_size"):
		server_instance.set_footprint_size(_get_cell_world_size() * Vector2(server_footprint_cells))
	if server_instance.has_method("set_anchor_cell"):
		server_instance.set_anchor_cell(server_anchor_cell)
	if server_instance.has_method("set_ground_ref"):
		server_instance.set_ground_ref(ground)
	if server_instance.has_signal("server_destroyed") and not server_instance.server_destroyed.is_connected(_on_server_destroyed):
		server_instance.server_destroyed.connect(_on_server_destroyed)

func _on_server_destroyed() -> void:
	if _game_over_triggered:
		return
	_game_over_triggered = true
	Global.gameplay_paused = true
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(death_scene_path)

func _center_camera_on_server() -> void:
	if camera == null:
		return
	camera.global_position = _get_footprint_center_world(server_anchor_cell, server_footprint_cells)
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()

func _get_map_center_anchor_cell() -> Vector2i:
	var used_rect: Rect2i = ground.get_used_rect()
	var center_local := used_rect.position + Vector2i(used_rect.size.x >> 1, used_rect.size.y >> 1)
	return Vector2i(center_local)

func _get_footprint_center_world(anchor_cell: Vector2i, footprint: Vector2i) -> Vector2:
	var start := anchor_cell - Vector2i(footprint.x >> 1, footprint.y >> 1)
	var end := start + footprint - Vector2i.ONE
	var start_world: Vector2 = _get_cell_center_world(start)
	var end_world: Vector2 = _get_cell_center_world(end)
	return (start_world + end_world) * 0.5

func _get_cell_center_world(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))

func _get_cell_world_size() -> Vector2:
	return Vector2(ground.tile_set.tile_size) * ground.global_scale
