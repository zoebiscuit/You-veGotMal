extends Node2D

signal server_destroyed

@export var width: float = 76.8
@export var height: float = 82.944
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var occupied_size_in_cells: Vector2i = Vector2i(3, 3)
@export var visual_scale_multiplier: float = 1.35
@export var server_texture: Texture2D = preload("res://assets/server.png")

@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision_shape: CollisionShape2D = $StaticBody2D/CollisionShape2D

var _destroyed_emitted := false
var anchor_cell: Vector2i = Vector2i.ZERO
var ground_ref: TileMapLayer

func _ready() -> void:
	z_index = 2
	add_to_group("structure_targets")
	max_health = max(max_health, 1.0)
	current_health = clamp(current_health, 0.0, max_health)
	_update_sprite_visual()
	_update_collision_shape()
	_update_health_bar()

func set_anchor_cell(value: Vector2i) -> void:
	anchor_cell = value

func set_ground_ref(value: TileMapLayer) -> void:
	ground_ref = value

func set_footprint_size(new_size: Vector2) -> void:
	width = max(new_size.x, 1.0)
	height = max(new_size.y, 1.0)
	_update_sprite_visual()
	_update_collision_shape()
	_update_health_bar()

func take_damage(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
	_set_current_health(current_health - amount)

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_current_health(current_health + amount)

func is_structure_alive() -> bool:
	return current_health > 0.0

func is_destroyed() -> bool:
	return current_health <= 0.0

func get_anchor_cell() -> Vector2i:
	return anchor_cell

func get_attack_radius() -> float:
	return max(width, height) * 0.5

func get_closest_attack_point(from_world: Vector2) -> Vector2:
	var half := Vector2(width, height) * 0.5
	return Vector2(
		clampf(from_world.x, global_position.x - half.x, global_position.x + half.x),
		clampf(from_world.y, global_position.y - half.y, global_position.y + half.y)
	)

func get_cell_world_center(cell: Vector2i) -> Vector2:
	if ground_ref == null:
		return global_position
	return ground_ref.to_global(ground_ref.map_to_local(cell))

func get_occupied_cells(origin_cell: Vector2i = anchor_cell) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var start := origin_cell - Vector2i(occupied_size_in_cells.x >> 1, occupied_size_in_cells.y >> 1)
	for y in range(occupied_size_in_cells.y):
		for x in range(occupied_size_in_cells.x):
			cells.append(start + Vector2i(x, y))
	return cells

func _set_current_health(value: float) -> void:
	current_health = clamp(value, 0.0, max_health)
	_update_health_bar()
	if current_health <= 0.0 and not _destroyed_emitted:
		_destroyed_emitted = true
		emit_signal("server_destroyed")
	elif current_health > 0.0:
		_destroyed_emitted = false

func _update_sprite_visual() -> void:
	if not is_node_ready():
		return
	sprite.centered = true
	sprite.texture = server_texture
	if server_texture == null:
		sprite.scale = Vector2.ONE
		return
	var texture_size := server_texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		sprite.scale = Vector2.ONE
		return
	var scale_factor: float = min(width / texture_size.x, height / texture_size.y) * visual_scale_multiplier
	sprite.scale = Vector2.ONE * scale_factor

func _update_collision_shape() -> void:
	if not is_node_ready():
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width, height)
	collision_shape.shape = rectangle
	$StaticBody2D.collision_layer = 2
	$StaticBody2D.collision_mask = 1

func _update_health_bar() -> void:
	if not is_node_ready():
		return
	health_bar.min_value = 0.0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false
	health_bar.position = Vector2(-health_bar.size.x * 0.5, -height * 0.5 - 18.0)
	var ratio := current_health / max_health if max_health > 0.0 else 0.0
	if ratio > 0.6:
		health_bar.modulate = Color(0.2, 0.9, 0.2, 1.0)
	elif ratio > 0.3:
		health_bar.modulate = Color(1.0, 0.85, 0.2, 1.0)
	else:
		health_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)
