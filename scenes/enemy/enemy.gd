class_name Enemy
extends CharacterBody2D

const WALK_SPEED := 22.0

@onready var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var floor_detector_left: RayCast2D = $FloorDetectorLeft
@onready var floor_detector_right: RayCast2D = $FloorDetectorRight
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.play("walk") 


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	if velocity.x == 0:
		velocity.x = WALK_SPEED


	if velocity.x > 0 and not floor_detector_right.is_colliding():
		turn_around()

	elif velocity.x < 0 and not floor_detector_left.is_colliding():
		turn_around()

	if is_on_wall():
		turn_around()

	move_and_slide()


func turn_around() -> void:
	velocity.x *= -1
	sprite.flip_h = velocity.x < 0
