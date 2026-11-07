extends StaticBody2D

@export var max_health: float = 100.0
@export var attack_range: float = 180.0
@export var attack_damage: float = 15.0
@export var fire_rate: float = 1.5
@export var projectile_speed: float = 350.0
@export var projectile_scene: PackedScene = preload("res://Buildings/projectile.tscn")
@export var body_color: Color = Color(1.0, 1.0, 1.0, 1.0)

@onready var sprite: Polygon2D = $Polygon2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var fire_timer: Timer = $FireTimer
@onready var retarget_timer: Timer = $RetargetTimer

var build_system: Node
var cell: Vector2i
var current_health: float
var destroyed := false
var current_target: Node = null
var tower_size: Vector2 = Vector2(24.0, 24.0)

func _ready() -> void:
	add_to_group("structure_targets")
	add_to_group("player_blocks")
	add_to_group("antivirus_towers")
	current_health = max_health
	fire_timer.wait_time = 1.0 / max(fire_rate, 0.01)
	fire_timer.one_shot = false
	retarget_timer.wait_time = 0.25
	retarget_timer.one_shot = false
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	retarget_timer.timeout.connect(_on_retarget_timer_timeout)
	retarget_timer.start()
	_configure_visuals()
	_update_health_bar()

func setup_block(owner_build_system: Node, owner_cell: Vector2i, size: Vector2) -> void:
	build_system = owner_build_system
	cell = owner_cell
	tower_size = size
	_configure_visuals()
	_update_health_bar()

func take_damage(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	current_health = max(current_health - amount, 0.0)
	_update_health_bar()
	if current_health <= 0.0:
		destroyed = true
		if build_system != null and is_instance_valid(build_system):
			build_system.destroy_block_at_cell(cell)

func is_structure_alive() -> bool:
	return not destroyed and current_health > 0.0

func is_destroyed() -> bool:
	return destroyed or current_health <= 0.0

func get_anchor_cell() -> Vector2i:
	return cell

func get_occupied_cells() -> Array[Vector2i]:
	return [cell]

func get_cell_world_center(query_cell: Vector2i = cell) -> Vector2:
	if build_system != null and is_instance_valid(build_system):
		return build_system.get_cell_world_center(query_cell)
	return global_position

func get_closest_attack_point(from_world: Vector2) -> Vector2:
	var half: Vector2 = tower_size * 0.5
	return Vector2(
		clampf(from_world.x, global_position.x - half.x, global_position.x + half.x),
		clampf(from_world.y, global_position.y - half.y, global_position.y + half.y)
	)

func get_attack_radius() -> float:
	return max(tower_size.x, tower_size.y) * 0.5

func _on_retarget_timer_timeout() -> void:
	if destroyed:
		return
	current_target = _find_nearest_enemy_in_range()
	if current_target != null:
		if fire_timer.is_stopped():
			fire_timer.start()
	else:
		fire_timer.stop()

func _on_fire_timer_timeout() -> void:
	if destroyed:
		fire_timer.stop()
		return
	if current_target == null or not is_instance_valid(current_target) or current_target.is_queued_for_deletion():
		current_target = _find_nearest_enemy_in_range()
		if current_target == null:
			fire_timer.stop()
			return
	if global_position.distance_to(current_target.global_position) > attack_range:
		current_target = _find_nearest_enemy_in_range()
		if current_target == null:
			fire_timer.stop()
			return
	_fire_projectile(current_target)

func _find_nearest_enemy_in_range() -> Node:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node = null
	var best_distance := INF
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var distance: float = global_position.distance_squared_to(enemy.global_position)
		if distance <= attack_range * attack_range and distance < best_distance:
			best_distance = distance
			nearest = enemy
	return nearest

func _fire_projectile(target_enemy: Node) -> void:
	if projectile_scene == null:
		return
	var projectile := projectile_scene.instantiate()
	if projectile == null:
		return
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position
	if projectile.has_method("setup"):
		projectile.setup(target_enemy, projectile_speed, attack_damage)

func _configure_visuals() -> void:
	var half := tower_size * 0.5
	sprite.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	sprite.color = body_color
	var rect := RectangleShape2D.new()
	rect.size = tower_size
	collision_shape.shape = rect
	health_bar.custom_minimum_size = Vector2(max(tower_size.x, 24.0), 8.0)
	health_bar.size = health_bar.custom_minimum_size
	health_bar.position = Vector2(-health_bar.custom_minimum_size.x * 0.5, -half.y - 14.0)

func _update_health_bar() -> void:
	health_bar.min_value = 0.0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false
	health_bar.visible = current_health < max_health
