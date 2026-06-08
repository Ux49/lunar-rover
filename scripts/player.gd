extends CharacterBody2D

const SPEED = 200.0
const JUMP_VELOCITY = -400.0
const COMBO_WINDOW = 0.5
const HITSTOP_DURATION = 0.08

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: CollisionShape2D = $AttackHitbox
@onready var hurtbox: CollisionShape2D = $Hurtbox
@onready var crouch_collision: CollisionShape2D = $crouch_collision
@onready var idle_collision: CollisionShape2D = $idle_collision

const ATTACK_DATA = {
	1: { "damage": 5,  "lunge": 60.0,  "anim": "attack_1" },
	2: { "damage": 7,  "lunge": 40.0,  "anim": "attack_2" },
	3: { "damage": 10, "lunge": 80.0,  "anim": "attack_3" },
	4: { "damage": 18, "lunge": 120.0, "anim": "attack_4" },
}

var is_attacking := false
var combo_step := 0
var combo_timer := 0.0
var buffered_attack := false
var hitstop_timer := 0.0
var facing := 1.0
var was_in_air := false


func _ready() -> void:
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	attack_hitbox.disabled = true


func _physics_process(delta: float) -> void:
	# Hitstop freeze
	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		animated_sprite_2d.pause()
		return
	else:
		animated_sprite_2d.play()

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY
		_reset_combo()

	if Input.is_action_just_pressed("attack"):
		if is_attacking:
			buffered_attack = true
		else:
			_start_attack(1)

	var direction := Input.get_axis("left", "right")

	if is_attacking:
		var lunge = ATTACK_DATA[combo_step]["lunge"] * facing
		velocity.x = move_toward(velocity.x, lunge, SPEED * delta * 10)
	elif Input.is_action_pressed("dash") and is_on_floor():
		velocity.x = direction * SPEED * 1.8
	elif Input.is_action_pressed("crouch") and is_on_floor():
		velocity.x = direction * (SPEED * 0.4)
	else:
		if direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Swap collision shapes for crouch vs stand
	var is_crouching = Input.is_action_pressed("crouch") and is_on_floor()
	crouch_collision.disabled = not is_crouching
	idle_collision.disabled = is_crouching

	move_and_slide()
	_update_animation(direction, delta)


func _update_animation(direction: float, delta: float) -> void:
	if not is_attacking:
		if direction > 0:
			facing = 1.0
			animated_sprite_2d.flip_h = false
		elif direction < 0:
			facing = -1.0
			animated_sprite_2d.flip_h = true

	if is_attacking:
		return

	if combo_timer > 0.0:
		combo_timer -= delta

	if Input.is_action_pressed("dash") and is_on_floor():
		animated_sprite_2d.play("dash")
		return

	if Input.is_action_pressed("shield") and is_on_floor():
		animated_sprite_2d.play("shield_walk" if direction != 0 else "shield_idle")
		return

	if Input.is_action_pressed("crouch") and is_on_floor():
		animated_sprite_2d.play("crouch_walk" if direction != 0 else "crouch_idle")
		return

	if not is_on_floor():
		was_in_air = true
		animated_sprite_2d.play("jump" if velocity.y < 0 else "fall")
		return

	was_in_air = false
	animated_sprite_2d.play("walk" if direction != 0 else "idle")



func _start_attack(step: int) -> void:
	combo_step = step
	is_attacking = true
	combo_timer = COMBO_WINDOW
	buffered_attack = false
	animated_sprite_2d.play(ATTACK_DATA[step]["anim"])
	attack_hitbox.disabled = false


func _reset_combo() -> void:
	is_attacking = false
	combo_step = 0
	combo_timer = 0.0
	buffered_attack = false
	attack_hitbox.disabled = true



func _on_animation_finished() -> void:
	if animated_sprite_2d.animation.begins_with("attack_"):
		attack_hitbox.disabled = true
		if buffered_attack and combo_step < 4:
			_start_attack(combo_step + 1)
			return
		_reset_combo()

	elif animated_sprite_2d.animation == "die":
		animated_sprite_2d.pause()



func take_damage(amount: int) -> void:
	_reset_combo()
	animated_sprite_2d.play("die")


func apply_hitstop(duration: float) -> void:
	hitstop_timer = duration
