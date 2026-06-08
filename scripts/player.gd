extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(delta: float) -> void:
	# Add gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("left", "right")

	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

	update_animation(direction)

var was_in_air = false

func update_animation(direction):
	# Flip sprite
	if direction > 0:
		animated_sprite_2d.flip_h = false
	elif direction < 0:
		animated_sprite_2d.flip_h = true

	# Dash
	if Input.is_action_pressed("dash"):
		animated_sprite_2d.play("dash")
		return

	# Shield (blocks normal walking)
	if Input.is_action_pressed("shield") and is_on_floor():
		if direction != 0:
			animated_sprite_2d.play("shield_up")
		else:
			animated_sprite_2d.play("shield_idle")
		return

	# Crouch
	if Input.is_action_pressed("crouch") and is_on_floor():
		if direction != 0:
			animated_sprite_2d.play("crouch_walk")
		else:
			animated_sprite_2d.play("crouch_idle")
		return

	# Air states
	if not is_on_floor():
		if velocity.y < 0:
			animated_sprite_2d.play("jump")
		else:
			animated_sprite_2d.play("fall")
		return

	# Ground states
	if direction != 0:
		animated_sprite_2d.play("walk")
	else:
		animated_sprite_2d.play("idle")
