extends CharacterBody2D

enum State { IDLE, PATROL, CHASE, STRAFE, ATTACK, DASH_ATTACK, HURT, STAGGER, DEATH }

@export_group("Movement")
@export var walk_speed:        float = 70.0
@export var chase_speed:       float = 95.0
@export var strafe_speed:      float = 50.0
@export var dash_speed:        float = 230.0

@export_group("Combat")
@export var health:            int   = 18
@export var attack_damage:     int   = 5
@export var dash_damage:       int   = 8
@export var knockback_force:   float = 140.0
@export var stagger_threshold: int   = 6

@export_group("Cooldowns")
@export var melee_cooldown:    float = 1.2
@export var dash_cooldown:     float = 2.8
@export var strafe_duration:   float = 1.0

@export_group("Ranges")
@export var detect_range:      float = 200.0
@export var attack_range:      float = 36.0
@export var dash_range:        float = 140.0

@onready var sprite:         AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D           = $DetectionArea
@onready var attack_area:    Area2D           = $AttackArea
@onready var attack_hitbox:  CollisionShape2D = $AttackArea/AttackHitbox
@onready var hurtbox:        Area2D           = $HurtboxArea
@onready var body_collider:  CollisionShape2D = $CollisionShape2D

var gravity:       float = ProjectSettings.get_setting("physics/2d/default_gravity")
var player:        CharacterBody2D = null

var state:         State = State.IDLE
var state_entered: bool  = false
var is_dead:       bool  = false
var facing:        float = 1.0

var melee_timer:   float = 0.0
var dash_timer:    float = 0.0
var hurt_timer:    float = 0.0
var stagger_timer: float = 0.0
var strafe_timer:  float = 0.0
var patrol_timer:  float = 0.0

var is_attacking:  bool  = false
var strafe_dir:    float = 1.0
var patrol_dir:    float = 1.0

const HIT_FRAME:     int = 2
const HIT_FRAME_END: int = 3

func _ready() -> void:
	add_to_group("enemies")
	attack_area.add_to_group("enemy_attack")
	hurtbox.add_to_group("enemy_hurtbox")
	attack_hitbox.disabled = true
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	sprite.play("idle")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D

var death_animation_played = false

func _process(delta):
	if is_dead:
		if not death_animation_played:
			sprite.play("dead")
			death_animation_played = true
		return
		
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		return

	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	_tick_timers(delta)

	if state not in [State.HURT, State.STAGGER, State.DEATH]:
		_decide()

	if not state_entered:
		_enter()
		state_entered = true

	_execute(delta)
	_apply_facing()
	move_and_slide()
	_update_animation()

func _tick_timers(delta: float) -> void:
	melee_timer   = maxf(0.0, melee_timer   - delta)
	dash_timer    = maxf(0.0, dash_timer    - delta)
	hurt_timer    = maxf(0.0, hurt_timer    - delta)
	stagger_timer = maxf(0.0, stagger_timer - delta)
	strafe_timer  = maxf(0.0, strafe_timer  - delta)
	patrol_timer  = maxf(0.0, patrol_timer  - delta)

func _decide() -> void:
	if is_attacking:
		return

	if not _can_see_player():
		_set_state(State.PATROL)
		return

	var dist:     float = _dist_to_player()
	var on_floor: bool  = is_on_floor()

	if melee_timer <= 0.0 and dist <= attack_range and on_floor:
		_set_state(State.ATTACK)
		return

	if dash_timer <= 0.0 and dist > attack_range and dist <= dash_range and on_floor:
		if strafe_timer <= 0.0:
			_set_state(State.DASH_ATTACK)
			return

	if dist > attack_range and dist <= dash_range:
		if state != State.STRAFE:
			_set_state(State.STRAFE)
		return

	_set_state(State.CHASE)
	
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state         = new_state
	state_entered = false

func _enter() -> void:
	match state:

		State.IDLE:
			velocity.x = 0.0

		State.PATROL:
			patrol_timer = randf_range(1.5, 3.0)
			patrol_dir   = 1.0 if randf() > 0.5 else -1.0

		State.CHASE:
			pass

		State.STRAFE:
			strafe_timer = strafe_duration
			strafe_dir   = -strafe_dir

		State.ATTACK:
			velocity.x             = 0.0
			is_attacking           = true
			melee_timer            = melee_cooldown
			attack_hitbox.disabled = true
			sprite.play("attack")

		State.DASH_ATTACK:
			is_attacking           = true
			dash_timer             = dash_cooldown
			attack_hitbox.disabled = true
			sprite.play("attack")

		State.HURT:
			is_attacking           = false
			attack_hitbox.disabled = true

		State.STAGGER:
			velocity.x             = 0.0
			is_attacking           = false
			attack_hitbox.disabled = true

		State.DEATH:
			is_attacking           = false
			attack_hitbox.disabled = true
			velocity               = Vector2.ZERO
			body_collider.set_deferred("disabled", true)
			detection_area.set_deferred("monitoring", false)
			sprite.play("dead")
			_die_async()

func _execute(delta: float) -> void:
	match state:

		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, chase_speed * 6.0 * delta)

		State.PATROL:
			if patrol_timer <= 0.0:
				patrol_dir   = -patrol_dir
				patrol_timer = randf_range(1.2, 2.5)
			if is_on_wall():
				patrol_dir   = -patrol_dir
				patrol_timer = randf_range(0.8, 1.5)
			velocity.x = patrol_dir * walk_speed * 0.55
			facing     = patrol_dir

		State.CHASE:
			var dir: float = _dir_to_player()
			velocity.x     = dir * chase_speed
			facing         = dir

		State.STRAFE:
			facing = _dir_to_player()
			if strafe_timer <= 0.0 or is_on_wall():
				strafe_dir   = -strafe_dir
				strafe_timer = strafe_duration * 0.8
			velocity.x = strafe_dir * strafe_speed

		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, chase_speed * 8.0 * delta)

		State.DASH_ATTACK:
			if not attack_hitbox.disabled:
				velocity.x = facing * dash_speed
			else:
				velocity.x = move_toward(velocity.x, 0.0, dash_speed * 4.0 * delta)

		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, knockback_force * 4.0 * delta)
			if hurt_timer <= 0.0:
				is_attacking = false
				_set_state(State.CHASE if _can_see_player() else State.PATROL)

		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, knockback_force * 2.5 * delta)
			if stagger_timer <= 0.0:
				is_attacking = false
				_set_state(State.CHASE if _can_see_player() else State.PATROL)

		State.DEATH:
			velocity.x = move_toward(velocity.x, 0.0, 80.0 * delta)

func _on_frame_changed() -> void:
	if not is_attacking:
		attack_hitbox.disabled = true
		return
	if sprite.animation != "attack":
		return
	var f: int = sprite.frame
	attack_hitbox.disabled = not (f >= HIT_FRAME and f < HIT_FRAME_END)

func _on_animation_finished() -> void:
	match sprite.animation:
		"attack":
			attack_hitbox.disabled = true
			is_attacking           = false
			if _can_see_player():
				_set_state(State.STRAFE)
			else:
				_set_state(State.IDLE)
		"dead":
			pass

func _apply_facing() -> void:
	if facing > 0.0:
		facing = 1.0
	elif facing < 0.0:
		facing = -1.0
	else:
		return
	sprite.flip_h          = facing < 0.0
	attack_area.position.x = abs(attack_area.position.x) * facing

func _update_animation() -> void:
	if state in [State.ATTACK, State.DASH_ATTACK, State.DEATH]:
		return
	if is_attacking:
		return

	if not is_on_floor():
		sprite.play("walk")
		return
	match state:
		State.IDLE:   sprite.play("idle")
		State.PATROL: sprite.play("walk")
		State.CHASE:  sprite.play("walk")
		State.STRAFE: sprite.play("walk")
		State.HURT:   sprite.play("idle")
		State.STAGGER:sprite.play("idle")
		_:            sprite.play("idle")

func take_damage(amount: int, knockback_dir: float) -> void:
	if is_dead or state == State.DEATH:
		return

	health -= amount
	_flash_red()

	if health <= 0:
		is_dead = true
		_set_state(State.DEATH)
		return

	if amount >= stagger_threshold:
		velocity.x = knockback_dir * knockback_force * 1.6
		velocity.y = -110.0
		_set_state(State.STAGGER)
		stagger_timer = 0.7
	else:
		velocity.x = knockback_dir * knockback_force
		velocity.y = -70.0
		_set_state(State.HURT)
		hurt_timer = 0.3


func _flash_red() -> void:
	var tween: Tween = create_tween()
	sprite.modulate  = Color.RED
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.35)


func _die_async() -> void:
	await sprite.animation_finished
	queue_free()

func _dist_to_player() -> float:
	return global_position.distance_to(player.global_position)

func _dir_to_player() -> float:
	return sign(player.global_position.x - global_position.x)

func _can_see_player() -> bool:
	return _dist_to_player() < detect_range

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player = body as CharacterBody2D

func _on_body_exited(_body: Node2D) -> void:
	pass
