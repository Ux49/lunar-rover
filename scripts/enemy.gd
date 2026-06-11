extends CharacterBody2D

enum State {
	IDLE,
	WALK,
	ATTACK
}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var player: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
@onready var detection_area: Area2D = $DetectionArea

const SPEED: float = 50.0
const ATTACK_DISTANCE: float = 25.0
const ATTACK_COOLDOWN: float = 1.0

var gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity"))

var state: State = State.IDLE
var player_detected: bool = false
var attack_timer: float = 0.0


func _ready() -> void:
	sprite.play("idle")

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if player == null:
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	if attack_timer > 0.0:
		attack_timer -= delta

	var distance: float = global_position.distance_to(player.global_position)

	if player_detected:
		if distance <= ATTACK_DISTANCE:
			state = State.ATTACK
		else:
			state = State.WALK
	else:
		state = State.IDLE

	# Execute state
	match state:

		State.IDLE:
			velocity.x = 0.0

		State.WALK:
			var direction: float = sign(
				player.global_position.x - global_position.x
			)

			velocity.x = direction * SPEED

			if direction > 0.0:
				sprite.flip_h = false
			elif direction < 0.0:
				sprite.flip_h = true

		State.ATTACK:
			velocity.x = 0.0

			var direction: float = sign(
				player.global_position.x - global_position.x
			)

			if direction > 0.0:
				sprite.flip_h = false
			elif direction < 0.0:
				sprite.flip_h = true

			if attack_timer <= 0.0:
				sprite.play("attack")
				attack_timer = ATTACK_COOLDOWN

	move_and_slide()

	update_animation()


func update_animation() -> void:
	if state == State.ATTACK:
		return

	var anim: StringName

	if not is_on_floor():
		anim = &"jump"
	else:
		match state:
			State.IDLE:
				anim = &"idle"

			State.WALK:
				anim = &"walk"

			_:
				anim = &"idle"

	if sprite.animation != anim:
		sprite.play(anim)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_detected = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_detected = false
