extends CharacterBody2D

const SPEED = 200.0
const JUMP_VELOCITY = -400.0
const COMBO_WINDOW = 0.5
const DASH_SPEED = 500.0
const DASH_DURATION = 0.2
const DASH_COOLDOWN = 0.8
const HURT_INVINCIBLE_DURATION = 1.2

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackHitboxArea
@onready var attack_hitbox: CollisionShape2D = $AttackHitboxArea/AttackHitbox
@onready var hurtbox: CollisionShape2D = $HurtboxArea/Hurtbox
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

var is_dashing := false
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := 1.0

var facing := 1.0
var jump_count := 0
const MAX_JUMPS = 2

var is_shielding := false      # blocks damage when true
var is_hurt := false
var is_dead := false
var hurt_flash_timer := 0.0


func _ready() -> void:
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	_set_standing()


func _set_standing() -> void:
	idle_collision.disabled = false
	hurtbox.disabled = false
	attack_hitbox.disabled = true
	attack_area.scale.x = 1


func _set_attacking() -> void:
	idle_collision.disabled = false
	hurtbox.disabled = false
	attack_hitbox.disabled = false
	attack_area.scale.x = facing


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		animated_sprite_2d.pause()
		return
	elif not animated_sprite_2d.is_playing():
		animated_sprite_2d.play()

	if hurt_flash_timer > 0.0:
		hurt_flash_timer -= delta
		animated_sprite_2d.modulate.a = 0.3 if fmod(hurt_flash_timer, 0.15) < 0.075 else 1.0
	else:
		animated_sprite_2d.modulate.a = 1.0

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		jump_count = 0

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	_handle_input(delta)
	move_and_slide()
	_update_animation()


func _handle_input(delta: float) -> void:
	if is_hurt or is_dead:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		return

	# Dash
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0 and not is_dashing:
		is_dashing = true
		dash_timer = DASH_DURATION
		dash_direction = facing
		if is_attacking:
			_reset_combo()
		else:
			_set_standing()

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction * DASH_SPEED
		if dash_timer <= 0.0:
			is_dashing = false
			dash_cooldown_timer = DASH_COOLDOWN
			_set_standing()
		return

	var want_shield = Input.is_action_pressed("shield") and is_on_floor()
	if want_shield != is_shielding:
		is_shielding = want_shield
		if is_shielding and is_attacking:
			_reset_combo()

	if is_shielding:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		return

	# Jump
	if Input.is_action_just_pressed("jump") and jump_count < MAX_JUMPS:
		velocity.y = JUMP_VELOCITY
		jump_count += 1
		if is_attacking:
			_reset_combo()

	# Attack
	if Input.is_action_just_pressed("attack") and not is_dashing:
		if is_attacking:
			buffered_attack = true
		else:
			_start_attack(1)

	# Movement
	var direction := Input.get_axis("left", "right")
	if is_attacking:
		var lunge = ATTACK_DATA[combo_step]["lunge"] * facing
		velocity.x = move_toward(velocity.x, lunge, SPEED * delta * 10)
	else:
		if direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Facing
	if not is_attacking and not is_dashing:
		if direction > 0:
			facing = 1.0
			animated_sprite_2d.flip_h = false
		elif direction < 0:
			facing = -1.0
			animated_sprite_2d.flip_h = true


func _start_attack(step: int) -> void:
	combo_step = step
	is_attacking = true
	combo_timer = COMBO_WINDOW
	buffered_attack = false
	animated_sprite_2d.play(ATTACK_DATA[step]["anim"])
	_set_attacking()


func _reset_combo() -> void:
	is_attacking = false
	combo_step = 0
	combo_timer = 0.0
	buffered_attack = false
	_set_standing()


func take_damage(_amount: int) -> void:
	# Damage is completely ignored if shielding, dashing, invincible, or dead
	if is_shielding or is_dashing or hurt_flash_timer > 0.0 or is_dead:
		return
	_reset_combo()
	is_hurt = true
	hurt_flash_timer = HURT_INVINCIBLE_DURATION
	velocity.x = -facing * 200.0
	velocity.y = -150.0
	_set_standing()
	animated_sprite_2d.play("hurt")


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_reset_combo()
	is_dashing = false
	velocity = Vector2.ZERO
	_set_standing()
	animated_sprite_2d.play("die")


func apply_hitstop(duration: float) -> void:
	hitstop_timer = duration


func _on_animation_finished() -> void:
	var anim := animated_sprite_2d.animation
	match anim:
		"hurt":
			is_hurt = false
			_set_standing()
		"die":
			get_tree().reload_current_scene()
		_:
			if anim.begins_with("attack_"):
				if buffered_attack and combo_step < 4:
					_start_attack(combo_step + 1)
				else:
					_reset_combo()


func _update_animation() -> void:
	if is_dead or is_hurt:
		return
	if is_dashing:
		animated_sprite_2d.play("dash")
		return
	if is_attacking:
		return
	if is_shielding:
		animated_sprite_2d.play("shield_idle")
		return
	if not is_on_floor():
		animated_sprite_2d.play("jump" if velocity.y < 0 else "fall")
		return
	var direction := Input.get_axis("left", "right")
	animated_sprite_2d.play("walk" if direction != 0 else "idle")
