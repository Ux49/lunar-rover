

extends CharacterBody2D


const SPEED:             float = 125.0
const JUMP_VELOCITY:     float = -270.0
const GRAVITY_SCALE:     float = 1.0

const MAX_JUMPS:         int   = 2
const COYOTE_TIME:       float = 0.12
const JUMP_BUFFER_TIME:  float = 0.10

const DASH_SPEED:        float = 300.0
const DASH_DURATION:     float = 0.18
const DASH_COOLDOWN:     float = 0.75
const DASH_INVINCIBLE:   float = 0.18

const COMBO_WINDOW:      float = 0.55
const COMBO_STEPS:       int   = 4

const HURT_INVINCIBLE:   float = 1.3
const HURT_STUN:         float = 0.35
const SHIELD_ABSORB:     float = 0.4

const HITSTOP_DURATION:  float = 0.06


class AttackStep:
	var damage: int
	var lunge:  float
	var anim:   String
	func _init(d: int, l: float, a: String) -> void:
		damage = d
		lunge  = l
		anim   = a

var ATTACKS: Array[AttackStep] = []  


@export var max_health: int = 20

@onready var anim:          AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area:   Area2D           = $AttackHitboxArea
@onready var attack_hitbox: CollisionShape2D = $AttackHitboxArea/AttackHitbox
@onready var hurtbox_area:  Area2D           = $HurtboxArea
@onready var hurtbox:       CollisionShape2D = $HurtboxArea/Hurtbox
@onready var body_col:      CollisionShape2D = $idle_collision


var health:           int   = 20


var facing:           float = 1.0
var jump_count:       int   = 0
var coyote_timer:     float = 0.0
var jump_buffer:      float = 0.0
var was_on_floor:     bool  = true

var is_dashing:       bool  = false
var dash_timer:       float = 0.0
var dash_cooldown:    float = 0.0
var dash_dir:         float = 1.0
var dash_invincible:  float = 0.0

var is_attacking:     bool  = false
var combo_step:       int   = 0
var combo_timer:      float = 0.0
var attack_buffered:  bool  = false
var attacked_enemies: Array = []

var is_shielding:     bool  = false

var hitstop_timer:    float = 0.0

var is_hurt:          bool  = false
var hurt_stun_timer:  float = 0.0
var invincible_timer: float = 0.0
var is_dead:          bool  = false
var flash_timer:      float = 0.0

func _ready() -> void:
	add_to_group("player")
	health = max_health

	ATTACKS.resize(5)
	ATTACKS[0] = AttackStep.new(0,  0.0,  "idle")
	ATTACKS[1] = AttackStep.new(5,  55.0, "attack_1")
	ATTACKS[2] = AttackStep.new(7,  35.0, "attack_2")
	ATTACKS[3] = AttackStep.new(10, 70.0, "attack_3")
	ATTACKS[4] = AttackStep.new(18, 110.0,"attack_4")

	anim.animation_finished.connect(_on_anim_finished)
	hurtbox_area.area_entered.connect(_on_hurtbox_entered)
	_set_hitbox(false)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		anim.pause()
		return
	elif not anim.is_playing():
		anim.play()

	_tick_timers(delta)


	if not is_on_floor():
		velocity += get_gravity() * GRAVITY_SCALE * delta
	else:
		if not was_on_floor:
			jump_count = 0
		coyote_timer = COYOTE_TIME

	was_on_floor = is_on_floor()

	_handle_input(delta)

	if is_attacking:
		_check_hits()

	move_and_slide()
	_update_animation()

func _tick_timers(delta: float) -> void:
	dash_cooldown    = maxf(0.0, dash_cooldown    - delta)
	dash_timer       = maxf(0.0, dash_timer       - delta)
	dash_invincible  = maxf(0.0, dash_invincible  - delta)
	combo_timer      = maxf(0.0, combo_timer      - delta)
	hurt_stun_timer  = maxf(0.0, hurt_stun_timer  - delta)
	invincible_timer = maxf(0.0, invincible_timer - delta)
	flash_timer      = maxf(0.0, flash_timer      - delta)
	coyote_timer     = maxf(0.0, coyote_timer     - delta)
	jump_buffer      = maxf(0.0, jump_buffer      - delta)

	if is_attacking and combo_timer <= 0.0 and not attack_buffered:
		_reset_combo()

	if is_hurt and hurt_stun_timer <= 0.0:
		is_hurt = false

	if flash_timer > 0.0:
		anim.modulate.a = 0.25 if fmod(flash_timer, 0.14) < 0.07 else 1.0
	else:
		anim.modulate.a = 1.0


func _handle_input(delta: float) -> void:
	if is_hurt or is_dead:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 4.0 * delta)
		return

	var dir: float = Input.get_axis("left", "right")


	if not is_attacking and not is_dashing:
		if dir > 0.0:
			facing      = 1.0
			anim.flip_h = false
		elif dir < 0.0:
			facing      = -1.0
			anim.flip_h = true

	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER_TIME


	var can_coyote: bool = coyote_timer > 0.0 and jump_count == 0
	var can_air:    bool = jump_count < MAX_JUMPS and jump_count > 0
	if jump_buffer > 0.0 and (can_coyote or can_air):
		velocity.y   = JUMP_VELOCITY
		jump_count  += 1
		jump_buffer  = 0.0
		coyote_timer = 0.0
		if is_attacking:
			_reset_combo()


	if Input.is_action_just_released("jump") and velocity.y < -60.0:
		velocity.y *= 0.5


	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0 and not is_dashing:
		_start_dash()

	if is_dashing:
		velocity.x = dash_dir * DASH_SPEED
		if dash_timer <= 0.0:
			is_dashing    = false
			dash_cooldown = DASH_COOLDOWN
			_set_hitbox(false)
		return

	# Shield
	var want_shield: bool = Input.is_action_pressed("shield") and is_on_floor()
	if want_shield != is_shielding:
		is_shielding = want_shield
		if is_shielding and is_attacking:
			_reset_combo()

	if is_shielding:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 5.0 * delta)
		return

	# Attack input
	if Input.is_action_just_pressed("attack") and not is_dashing:
		if is_attacking:
			attack_buffered = true
		else:
			_start_attack(1)

	# Horizontal movement
	if is_attacking:
		var step:  AttackStep = ATTACKS[combo_step]
		var lunge: float      = step.lunge * facing
		velocity.x = move_toward(velocity.x, lunge, SPEED * delta * 12.0)
	else:
		if dir != 0.0:
			velocity.x = dir * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED * 5.0 * delta)

func _start_dash() -> void:
	is_dashing      = true
	dash_timer      = DASH_DURATION
	dash_invincible = DASH_INVINCIBLE
	dash_dir        = facing
	velocity.y      = 0.0
	if is_attacking:
		_reset_combo()
	anim.play("dash")


func _start_attack(step: int) -> void:
	combo_step      = step
	is_attacking    = true
	combo_timer     = COMBO_WINDOW
	attack_buffered = false
	attacked_enemies.clear()
	var s: AttackStep = ATTACKS[step]
	anim.play(s.anim)
	_set_hitbox(true)


func _reset_combo() -> void:
	is_attacking    = false
	combo_step      = 0
	combo_timer     = 0.0
	attack_buffered = false
	attacked_enemies.clear()
	_set_hitbox(false)


func _set_hitbox(active: bool) -> void:
	attack_hitbox.set_deferred("disabled", not active)
	if active:
		attack_area.scale.x = facing


func _check_hits() -> void:
	for area: Area2D in attack_area.get_overlapping_areas():
		if area.is_in_group("enemy_hurtbox"):
			var enemy: Node = area.get_parent()
			if enemy in attacked_enemies:
				continue
			attacked_enemies.append(enemy)
			var knock_dir: float = sign(enemy.global_position.x - global_position.x)
			if enemy.has_method("take_damage"):
				var step: AttackStep = ATTACKS[combo_step]
				enemy.take_damage(step.damage, knock_dir)
			_apply_hitstop(HITSTOP_DURATION)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	if dash_invincible > 0.0:
		return
	if invincible_timer > 0.0:
		return

	var actual_damage: int = amount
	if is_shielding:
		actual_damage = int(float(amount) * (1.0 - SHIELD_ABSORB))

	health -= actual_damage
	_reset_combo()
	is_shielding     = false
	is_hurt          = true
	hurt_stun_timer  = HURT_STUN
	invincible_timer = HURT_INVINCIBLE
	flash_timer      = HURT_INVINCIBLE
	velocity.x       = -facing * 210.0
	velocity.y       = -160.0
	anim.play("hurt")

	if health <= 0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead  = true
	velocity = Vector2.ZERO
	_reset_combo()
	anim.play("die")

func _apply_hitstop(duration: float) -> void:
	hitstop_timer = maxf(hitstop_timer, duration)

func _on_anim_finished() -> void:
	var current: String = anim.animation
	match current:
		"hurt":
			pass   # is_hurt cleared by timer already
		"die":
			get_tree().reload_current_scene()
		_:
			if current.begins_with("attack_"):
				if attack_buffered and combo_step < COMBO_STEPS:
					_start_attack(combo_step + 1)
				else:
					_reset_combo()


func _on_hurtbox_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_attack"):
		take_damage(5)


func _update_animation() -> void:
	if is_dead or is_hurt:
		return
	if is_dashing:
		anim.play("dash")
		return
	if is_attacking:
		return
	if is_shielding:
		anim.play("shield_idle")
		return
	if not is_on_floor():
		anim.play("jump" if velocity.y < 0.0 else "fall")
		return
	var dir: float = Input.get_axis("left", "right")
	anim.play("walk" if dir != 0.0 else "idle")
