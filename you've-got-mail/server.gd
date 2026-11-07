extends Node2D

signal server_destroyed

@export var width: float = 25.6
@export var height: float = 27.648
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var occupied_size_in_cells: Vector2i = Vector2i.ONE

@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision_shape: CollisionShape2D = $StaticBody2D/CollisionShape2D

var _destroyed_emitted := false
var _placeholder_texture: ImageTexture

func _ready() -> void:
	z_index = 2
	max_health = max(max_health, 1.0)
	current_health = clamp(current_health, 0.0, max_health)
	_update_placeholder_visual()
	_update_collision_shape()
	_update_health_bar()

func set_placeholder_size(new_size: Vector2) -> void:
	width = max(new_size.x, 1.0)
	height = max(new_size.y, 1.0)
	_update_placeholder_visual()
	_update_collision_shape()
	_update_health_bar()

func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_current_health(current_health - amount)

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_current_health(current_health + amount)

func get_occupied_cells(origin_cell: Vector2i) -> Array[Vector2i]:
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

func _update_placeholder_visual() -> void:
	if not is_node_ready():
		return
	var image := Image.create(maxi(int(round(width)), 1), maxi(int(round(height)), 1), false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_placeholder_texture = ImageTexture.create_from_image(image)
	sprite.texture = _placeholder_texture
	sprite.centered = true

func _update_collision_shape() -> void:
	if not is_node_ready():
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width, height)
	collision_shape.shape = rectangle

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
