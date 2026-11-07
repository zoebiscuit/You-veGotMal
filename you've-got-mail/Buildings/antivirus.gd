extends StaticBody2D

@export var max_health: float = 100.0
@export var attack_range: float = 260.0
@export var attack_damage: float = 10.0
@export var fire_rate: float = 1.5
@export var projectile_speed: float = 350.0
@export var projectile_scene: PackedScene = preload("res://Buildings/projectile.tscn")
@export var body_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var visual_fill_multiplier: float = 2.2
@export var sprite_offset: Vector2 = Vector2(3.0, 1.0)
@export var range_indicator_color: Color = Color(0.4, 0.9, 1.0, 0.14)
@export var range_indicator_outline_color: Color = Color(0.6, 1.0, 1.0, 0.35)
@export var range_indicator_outline_width: float = 2.0
@export var shoot_anim_length: float = 1.0
@export var shoot_anim_frame_interval: float = 0.12
@export var health_bar_height: float = 4.0
@export var health_bar_fade_delay: float = 3.0
@export var health_bar_fade_duration: float = 0.35

@onready var sprite: Sprite2D = $Sprite2D
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
var _base_sprite_scale: Vector2 = Vector2.ONE
var _shoot_anim_tween: Tween = null
var _health_bar_fade_tween: Tween = null

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

func heal(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	current_health = min(current_health + amount, max_health)
	_update_health_bar()

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
	if Global.gameplay_paused:
		return
	if destroyed:
		return
	var keep_current_target := false
	if current_target != null and is_instance_valid(current_target) and not current_target.is_queued_for_deletion():
		keep_current_target = global_position.distance_squared_to(current_target.global_position) <= attack_range * attack_range
	if not keep_current_target:
		current_target = _find_nearest_enemy_in_range()
	if current_target != null:
		if fire_timer.is_stopped():
			fire_timer.start()
	else:
		fire_timer.stop()

func _on_fire_timer_timeout() -> void:
	if Global.gameplay_paused:
		return
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
	_play_shoot_animation()

func _configure_visuals() -> void:
	var half := tower_size * 0.5
	if sprite.texture != null:
		var texture_size := sprite.texture.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			var frame_size := Vector2(texture_size.x / max(sprite.hframes, 1), texture_size.y / max(sprite.vframes, 1))
			if frame_size.x > 0.0 and frame_size.y > 0.0:
				_base_sprite_scale = Vector2(tower_size.x / frame_size.x, tower_size.y / frame_size.y) * max(visual_fill_multiplier, 0.1)
				sprite.scale = _base_sprite_scale
	sprite.modulate = body_color
	sprite.position = sprite_offset
	sprite.hframes = 2
	sprite.vframes = 1
	sprite.frame = 0
	var rect := RectangleShape2D.new()
	rect.size = tower_size
	collision_shape.shape = rect
	health_bar.custom_minimum_size = Vector2(max(tower_size.x, 24.0), health_bar_height)
	health_bar.size = health_bar.custom_minimum_size
	health_bar.position = Vector2(-health_bar.custom_minimum_size.x * 0.5, -half.y - 14.0)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, attack_range, range_indicator_color)
	draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 96, range_indicator_outline_color, range_indicator_outline_width, true)

func _play_shoot_animation() -> void:
	if sprite == null:
		return
	if _shoot_anim_tween != null and _shoot_anim_tween.is_valid():
		_shoot_anim_tween.kill()
	sprite.frame = 0
	_shoot_anim_tween = create_tween()
	var step_count := maxi(1, int(ceil(max(shoot_anim_length, 0.01) / max(shoot_anim_frame_interval, 0.03))))
	for i in range(step_count):
		_shoot_anim_tween.tween_callback(func() -> void:
			sprite.frame = 1 if sprite.frame == 0 else 0
		)
		_shoot_anim_tween.tween_interval(max(shoot_anim_frame_interval, 0.03))
	_shoot_anim_tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.frame = 0
	)

func _update_health_bar() -> void:
	health_bar.min_value = 0.0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false
	_show_health_bar_temporarily(current_health < max_health)

func _show_health_bar_temporarily(should_show: bool) -> void:
	if health_bar == null:
		return
	if _health_bar_fade_tween != null and _health_bar_fade_tween.is_valid():
		_health_bar_fade_tween.kill()
	if not should_show:
		health_bar.visible = false
		return
	health_bar.visible = true
	var color := health_bar.modulate
	color.a = 1.0
	health_bar.modulate = color
	_health_bar_fade_tween = create_tween()
	_health_bar_fade_tween.tween_interval(max(health_bar_fade_delay, 0.0))
	_health_bar_fade_tween.tween_property(health_bar, "modulate:a", 0.0, max(health_bar_fade_duration, 0.01))
	_health_bar_fade_tween.tween_callback(func() -> void:
		if is_instance_valid(health_bar):
			health_bar.visible = false
	)
