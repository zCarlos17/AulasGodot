extends CharacterBody2D

signal died

enum State{ PATROL, PAUSE, HURT, DEAD}

@export_group("Movimentação")
@export var speed: float = 60.0
@export var pause_at_edge: float = 1.0
@export var start_direction: int = 1

@export_group("Vida")
@export var max_health: int = 50
@export var knockback_force: Vector2 = Vector2(150.0, -120.0)
@export var corpse_time: float = 2.0 #Tempo que o personagem fica antes de desaparecer quando eliminado

@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var ledge_check: RayCast2D = $LedgeCheck #Checar a borda

var state: State = State.PATROL
var health: int =0
var facing: int =1
var pause_timer: float =0.0


func _ready() -> void:
	health = max_health
	facing = start_direction
	_apply_facing()
	anim.animation_finished.connect(_on_animation_finished)
	_set_state(State.PATROL)
	
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	match state:
		State.PATROL:
			if _should_turn():
				_turn()
			else:
				velocity.x = facing * speed
		State.PAUSE:
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
			pause_timer -= delta
			if pause_timer <= 0.0:
				_set_state(State.PATROL)
		State.HURT, State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	move_and_slide()
	
func _should_turn()-> bool:
	if is_on_wall():
		return true
	return is_on_floor() and not ledge_check.is_colliding()

func _apply_facing() -> void:
	anim.flip_h = facing < 0
	ledge_check.position.x = absf(ledge_check.position.x) * facing
	
func _turn() -> void:
	facing = -facing
	_apply_facing()
	pause_timer = pause_at_edge
	_set_state(State.PAUSE)


func _set_state(new_state: State) -> void:
	state = new_state
	match state:
		State.PATROL:
			anim.play("Walk")
		State.PAUSE:
			anim.play("Idle")
		State.HURT:
			anim.play("Hurt")
		State.DEAD:
			anim.play("Death")

func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO, _can_be_blocked: bool = true) -> void:
	if state == State.DEAD or state == State.HURT:
		return

	health = maxi(health - amount, 0)
	if health == 0:
		_die()
		return

	# Empurrão para longe de quem causou o dano
	var push_dir: float = signf(global_position.x - source_position.x)
	if push_dir == 0.0:
		push_dir = -facing
	velocity = Vector2(push_dir * knockback_force.x, knockback_force.y)
	_set_state(State.HURT)
	
func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", true)   # para de ser atingido
	died.emit()
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)

func _on_animation_finished() -> void:
	# Terminou o Hurt: volta a patrulhar
	if state == State.HURT:
		_set_state(State.PATROL)
