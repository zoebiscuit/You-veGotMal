extends CharacterBody2D

signal died(enemy: Node)

enum AnimState {
	WALK,
	ATTACK,
	HURT
}

@export var max_health: float = 50.0
@export var movement_speed: float = 100.0
@export var attack_damage: float = 10.0
@export var attack_interval: float = 1.0
@export var enemy_size: Vector2 = Vector2(40.0, 40.0)
@export var target_refresh_interval: float = 0.75
@export var attack_range_padding: float = 6.0
@export var hit_flash_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var hit_flash_duration: float = 0.12

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var attack_timer: Timer = $AttackTimer
@onready var retarget_timer: Timer = $RetargetTimer

var current_health: float
var level: Node
var current_target: Node = null
var current_target_cell: Vector2i = Vector2i.ZERO
var current_target_world: Vector2 = Vector2.ZERO
var _dead := false
var _debug_click_damage := 25.0
var _anim_state: int = AnimState.WALK
var _is_attacking_anim := false
var _is_hurt_anim := false
var _hit_flash_tween: Tween = null

func _ready() -> void:
	current_health = max_health
	z_index = 3
	add_to_group("enemies")
	_configure_visuals()
	animated_sprite.play(&"walk")
	_update_health_bar()
	attack_timer.wait_time = max(attack_interval, 0.05)
	attack_timer.one_shot = false
	retarget_timer.wait_time = max(target_refresh_interval, 0.1)
	retarget_timer.one_shot = false
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	retarget_timer.timeout.connect(_on_retarget_timer_timeout)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	retarget_timer.start()
	level = get_parent()
	while level != null and not level.has_method("find_nearest_structure_target"):
		level = level.get_parent()
	acquire_target()
	_update_animation_state()

func _physics_process(_delta: float) -> void:
	if Global.gameplay_paused:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("ui_accept"):
		if global_position.distance_to(get_global_mouse_position()) <= max(enemy_size.x, enemy_size.y) * 1.5:
			take_damage(_debug_click_damage)

	if not _is_target_valid():
		acquire_target()

	if not _is_target_valid():
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation_state()
		return

	current_target_world = _get_attack_position_for_target(current_target, current_target_cell)
	var to_target: Vector2 = current_target_world - global_position
	var attack_distance: float = _get_attack_distance_for_target(current_target)
	if to_target.length() <= attack_distance:
		velocity = Vector2.ZERO
		move_and_slide()
		_face_direction(to_target)
		_start_attacking()
		_update_animation_state()
		return

	_stop_attacking()
	var desired_direction: Vector2 = to_target.normalized()
	velocity = desired_direction * movement_speed
	_face_direction(desired_direction)
	move_and_slide()

	if get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var collision := get_slide_collision(i)
			if collision == null:
				continue
			var collider := collision.get_collider()
			if collider == null:
				continue
			var structure := _resolve_structure_from_collider(collider)
			if structure != null and structure != current_target:
				current_target = structure
				if current_target.has_method("get_anchor_cell"):
					current_target_cell = current_target.get_anchor_cell()
				current_target_world = _get_attack_position_for_target(current_target, current_target_cell)
				velocity = Vector2.ZERO
				_start_attacking()
				break

	_update_animation_state()

func acquire_target() -> void:
	_stop_attacking()
	current_target = null
	if level == null or not level.has_method("find_nearest_structure_target"):
		return
	var target_data = level.find_nearest_structure_target(global_position)
	if typeof(target_data) != TYPE_DICTIONARY or target_data.is_empty():
		return
	var node: Node = target_data.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	current_target = node
	current_target_cell = target_data.get("cell", Vector2i.ZERO)
	current_target_world = target_data.get("world_position", node.global_position)

func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	current_health = clamp(current_health - amount, 0.0, max_health)
	_update_health_bar()
	if current_health <= 0.0:
		die()
		return
	_play_hit_flash()
	if not _is_attacking_anim:
		_play_hurt_animation()

func die() -> void:
	if _dead:
		return
	_dead = true
	Global.GlobalCrypto += 10
	velocity = Vector2.ZERO
	_stop_attacking()
	current_target = null
	emit_signal("died", self)
	queue_free()

func _on_attack_timer_timeout() -> void:
	if Global.gameplay_paused:
		return
	if _dead or not _is_target_valid():
		_stop_attacking()
		_update_animation_state()
		return
	var distance: float = global_position.distance_to(_get_attack_position_for_target(current_target, current_target_cell))
	if distance > _get_attack_distance_for_target(current_target) + 4.0:
		_stop_attacking()
		_update_animation_state()
		return
	_play_attack_animation()
	if current_target.has_method("take_damage"):
		current_target.take_damage(attack_damage)
	if not _is_target_valid():
		acquire_target()

func _on_retarget_timer_timeout() -> void:
	if Global.gameplay_paused:
		return
	if _dead:
		return
	if level == null or not level.has_method("find_nearest_structure_target"):
		return
	var target_data = level.find_nearest_structure_target(global_position)
	if typeof(target_data) != TYPE_DICTIONARY or target_data.is_empty():
		if not _is_target_valid():
			current_target = null
		return
	var node: Node = target_data.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	if current_target == null or node != current_target:
		current_target = node
		current_target_cell = target_data.get("cell", Vector2i.ZERO)
		current_target_world = target_data.get("world_position", node.global_position)
	elif target_data.has("cell"):
		current_target_cell = target_data.get("cell", current_target_cell)
		current_target_world = target_data.get("world_position", current_target_world)

func _is_target_valid() -> bool:
	if current_target == null or not is_instance_valid(current_target):
		return false
	if current_target.has_method("is_destroyed") and current_target.is_destroyed():
		return false
	if current_target.has_method("is_structure_alive"):
		return current_target.is_structure_alive()
	return true

func _start_attacking() -> void:
	if attack_timer.is_stopped():
		attack_timer.start()

func _stop_attacking() -> void:
	if not attack_timer.is_stopped():
		attack_timer.stop()
	_is_attacking_anim = false

func _get_attack_position_for_target(target: Node, target_cell: Vector2i) -> Vector2:
	if target == null:
		return global_position
	if target.has_method("get_closest_attack_point"):
		return target.get_closest_attack_point(global_position)
	if target.has_method("get_cell_world_center"):
		return target.get_cell_world_center(target_cell)
	return target.global_position

func _get_attack_distance_for_target(_target: Node) -> float:
	var own_radius: float = max(enemy_size.x, enemy_size.y) * 0.5
	return own_radius + attack_range_padding

func _resolve_structure_from_collider(collider: Object) -> Node:
	if collider == null:
		return null
	var node := collider as Node
	while node != null:
		if node.is_in_group("structure_targets"):
			return node
		node = node.get_parent()
	return null

func _configure_visuals() -> void:
	var rect := RectangleShape2D.new()
	rect.size = enemy_size
	collision_shape.shape = rect
	animated_sprite.position = Vector2(0.0, -4.0)
	animated_sprite.scale = Vector2(1.0, 1.0)
	health_bar.custom_minimum_size = Vector2(max(enemy_size.x + 8.0, 24.0), 8.0)
	health_bar.size = health_bar.custom_minimum_size
	health_bar.position = Vector2(-health_bar.custom_minimum_size.x * 0.5, -enemy_size.y * 0.5 - 14.0)

func _update_health_bar() -> void:
	health_bar.min_value = 0.0
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.show_percentage = false
	health_bar.visible = current_health < max_health
	var ratio := current_health / max_health if max_health > 0.0 else 0.0
	if ratio > 0.6:
		health_bar.modulate = Color(0.2, 0.9, 0.2, 1.0)
	elif ratio > 0.3:
		health_bar.modulate = Color(1.0, 0.85, 0.2, 1.0)
	else:
		health_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)

func _play_attack_animation() -> void:
	_is_attacking_anim = true
	_is_hurt_anim = false
	_anim_state = AnimState.ATTACK
	animated_sprite.play(&"attack")
	animated_sprite.frame = 0
	animated_sprite.frame_progress = 0.0

func _play_hurt_animation() -> void:
	if _is_attacking_anim:
		return
	_is_hurt_anim = true
	_set_animation_state(AnimState.HURT)

func _play_hit_flash() -> void:
	if animated_sprite == null:
		return
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	animated_sprite.modulate = hit_flash_color
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), max(hit_flash_duration, 0.01))

func _update_animation_state() -> void:
	if _dead:
		return
	if _is_attacking_anim:
		return
	if _is_hurt_anim:
		_set_animation_state(AnimState.HURT)
		return
	if velocity.length_squared() > 1.0:
		_set_animation_state(AnimState.WALK)
	else:
		_set_animation_state(AnimState.WALK)

func _set_animation_state(state: int) -> void:
	if _anim_state == state:
		if state == AnimState.WALK and animated_sprite.animation != &"walk":
			animated_sprite.play(&"walk")
		elif state == AnimState.WALK and not animated_sprite.is_playing():
			animated_sprite.play(&"walk")
		return
	_anim_state = state
	match state:
		AnimState.ATTACK:
			animated_sprite.play(&"attack")
		AnimState.HURT:
			animated_sprite.play(&"hurt")
		AnimState.WALK:
			animated_sprite.play(&"walk")

func _on_animation_finished() -> void:
	if animated_sprite.animation == &"attack":
		_is_attacking_anim = false
	elif animated_sprite.animation == &"hurt":
		_is_hurt_anim = false
	_update_animation_state()

func _face_direction(direction: Vector2) -> void:
	if absf(direction.x) > 0.01:
		animated_sprite.flip_h = direction.x < 0.0
