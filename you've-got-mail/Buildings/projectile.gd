extends Area2D

@export var speed: float = 350.0
@export var damage: float = 15.0
@export var lifetime: float = 2.0
@export var projectile_color: Color = Color(0.8, 1.0, 1.0, 1.0)
@export var radius: float = 5.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var life_timer: Timer = $LifeTimer

var target: Node = null
var velocity: Vector2 = Vector2.ZERO
var _hit := false

func _ready() -> void:
	_configure_visuals()
	collision_layer = 8
	collision_mask = 4
	body_entered.connect(_on_body_entered)
	life_timer.wait_time = lifetime
	life_timer.one_shot = true
	life_timer.timeout.connect(queue_free)
	life_timer.start()

func setup(target_enemy: Node, projectile_speed: float, projectile_damage: float) -> void:
	target = target_enemy
	speed = projectile_speed
	damage = projectile_damage
	if target != null and is_instance_valid(target):
		var direction: Vector2 = (target.global_position - global_position).normalized()
		velocity = direction * speed
		rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if _hit:
		return
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		queue_free()
		return
	var direction: Vector2 = (target.global_position - global_position)
	if direction.length_squared() > 0.001:
		velocity = direction.normalized() * speed
		rotation = velocity.angle()
	global_position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if _hit:
		return
	if body == null or not is_instance_valid(body):
		return
	if body != target:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_hit = true
	queue_free()

func _configure_visuals() -> void:
	var image := Image.create(max(int(radius * 2.0), 2), max(int(radius * 2.0), 2), false, Image.FORMAT_RGBA8)
	image.fill(projectile_color)
	var texture := ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision_shape.shape = shape
