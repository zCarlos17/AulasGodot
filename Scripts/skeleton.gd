extends CharacterBody2D

signal died

enum State { PATROL, PAUSE, CHASE, ATTACK, BLOCK, HURT, DEAD }

const ATTACK_ANIMS: Array[String] = ["Attack1", "Attack2"]
const BLOCK_ANIM := "Block"

@export_group("Movimentação")
@export var speed: float = 60.0
@export var chase_speed: float = 90.0
@export var pause_at_edge: float = 1.0
@export var start_direction: int = 1
@export var stop_distance: float = 22.0          # para de avançar nessa distância do player

@export_group("Percepção")
@export var lose_sight_time: float = 2.0
@export var ignore_after_giving_up: float = 3.0
@export var stuck_time: float = 0.4
@export var eye_height: float = -10.0

@export_group("Ataque")
@export var reaction_time: float = 0.5           # tempo no alcance antes do golpe
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.0
@export var attack_active_frames: Vector2i = Vector2i(6, 7)

@export_group("Escudo")
@export_range(0.0, 1.0) var block_chance: float = 0.5  # chance de levantar o escudo a cada golpe do player
@export var block_duration: float = 0.6                 # tempo com o escudo levantado, em segundos
@export var block_cooldown: float = 2.0                 # tempo mínimo entre dois bloqueios

@export_group("Vida")
@export var max_health: int = 50
@export var knockback_force: Vector2 = Vector2(150.0, -120.0)
@export var corpse_time: float = 2.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var ledge_check: RayCast2D = $LedgeCheck
@onready var detect_range: Area2D = $DetectedRange
@onready var attack_range: Area2D = $AttackRange
@onready var attack_range_shape: CollisionShape2D = $AttackRange/CollisionShape2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var health_bar: EnemyHealthBar = $HealthBar

var state: State = State.PATROL
var health: int = 0
var facing: int = 1
var pause_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var lost_sight_timer: float = 0.0
var ignore_player_timer: float = 0.0
var reaction_timer: float = 0.0
var stuck_timer: float = 0.0
var last_x: float = 0.0
var intended_vx: float = 0.0
var attack_range_base_x: float = 0.0
var hitbox_base_x: float = 0.0
var hit_targets: Array[Node] = []

# Escudo
var block_timer: float = 0.0
var block_cooldown_timer: float = 0.0
var player_was_attacking: bool = false


func _ready() -> void:
	health = max_health
	facing = start_direction
	attack_range_base_x = absf(attack_range_shape.position.x)
	hitbox_base_x = absf(hitbox_shape.position.x)
	last_x = global_position.x
	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_try_hit)
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	health_bar.set_values(health, max_health)
	_apply_facing()
	_set_state(State.PATROL)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	attack_cooldown_timer -= delta
	ignore_player_timer -= delta

	_atualizar_escudo(delta)

	match state:
		State.PATROL:
			if _see_player():
				_set_state(State.CHASE)
			elif _should_turn():
				_turn()
			else:
				velocity.x = facing * speed

		State.PAUSE:
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)
			pause_timer -= delta
			if _see_player():
				_set_state(State.CHASE)
			elif pause_timer <= 0.0:
				_set_state(State.PATROL)

		State.CHASE:
			var player := _find_player(detect_range)
			if player != null and _has_line_of_sight(player):
				lost_sight_timer = lose_sight_time
				_chase_player(player, delta)
			else:
				velocity.x = 0.0
				lost_sight_timer -= delta
				if lost_sight_timer <= 0.0:
					_give_up()

		State.BLOCK:
			# Escudo levantado: fica parado, sem avançar
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)

		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, speed * 4.0 * delta)

		State.HURT, State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)

	intended_vx = velocity.x
	move_and_slide()

	# Verifica quem já está dentro da hitbox (body_entered não dispara para eles)
	if state == State.ATTACK and attack_hitbox.monitoring:
		for body in attack_hitbox.get_overlapping_bodies():
			_try_hit(body)

	_check_stuck(delta)


#region Escudo
# Bloqueio por evento: a cada golpe do player (no início do ataque) o Skeleton
# rola uma chance. Se der certo, o escudo sobe por block_duration e depois entra em cooldown.
func _atualizar_escudo(delta: float) -> void:
	if state == State.DEAD:
		return
	block_cooldown_timer -= delta
	var atacando: bool = _player_atacando_de_frente()
	var comecou_agora: bool = atacando and not player_was_attacking
	player_was_attacking = atacando

	if state == State.BLOCK:
		block_timer -= delta
		if block_timer <= 0.0:
			_fim_bloqueio()
		return

	var pode_bloquear: bool = state in [State.PATROL, State.PAUSE, State.CHASE]
	if comecou_agora and pode_bloquear and block_cooldown_timer <= 0.0 and randf() < block_chance:
		block_timer = block_duration
		_set_state(State.BLOCK)


func _fim_bloqueio() -> void:
	block_cooldown_timer = block_cooldown
	_set_state(State.CHASE if _see_player() else State.PATROL)


func _player_atacando_de_frente() -> bool:
	var player := _find_player(detect_range)
	if player == null or not player.has_method("is_attacking"):
		return false
	if not player.is_attacking():
		return false
	return _is_attack_from_front(player.global_position) and _has_line_of_sight(player)


# Mesma lógica do player: o golpe vem da frente se a origem está do lado para onde o Skeleton olha
func _is_attack_from_front(source_position: Vector2) -> bool:
	return int(signf(source_position.x - global_position.x)) == facing


# Golpe bloqueado: sem dano e sem empurrão, só um flash no escudo
func _feedback_bloqueio() -> void:
	anim.self_modulate = Color(1.8, 1.8, 1.8)
	var t := create_tween()
	t.tween_property(anim, "self_modulate", Color.WHITE, 0.15)
#endregion


#region Perseguição
func _chase_player(player: Node2D, delta: float) -> void:
	var dx: float = player.global_position.x - global_position.x
	var dir: int = int(signf(dx))
	if dir != 0 and dir != facing:
		facing = dir
		_apply_facing()

	# Chegou perto: para de avançar para não atravessar o player
	if absf(dx) <= stop_distance:
		velocity.x = 0.0
		if attack_cooldown_timer <= 0.0:
			reaction_timer -= delta
			if reaction_timer <= 0.0:
				_set_state(State.ATTACK)
		else:
			reaction_timer = reaction_time
	elif _find_player(attack_range) and attack_cooldown_timer <= 0.0:
		velocity.x = 0.0
		reaction_timer -= delta
		if reaction_timer <= 0.0:
			_set_state(State.ATTACK)
	else:
		reaction_timer = reaction_time
		_chase_step()


func _chase_step() -> void:
	if is_on_floor() and not ledge_check.is_colliding():
		velocity.x = 0.0
	else:
		velocity.x = facing * chase_speed


func _apply_facing() -> void:
	anim.flip_h = facing < 0
	ledge_check.position.x = absf(ledge_check.position.x) * facing
	attack_range_shape.position.x = attack_range_base_x * facing
	hitbox_shape.position.x = hitbox_base_x * facing
#endregion


#region Percepção
func _see_player() -> bool:
	if ignore_player_timer > 0.0:
		return false
	var player := _find_player(detect_range)
	return player != null and _has_line_of_sight(player)


func _find_player(area: Area2D) -> Node2D:
	if not area.monitoring:
		return null
	for body in area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return body
	return null

func _has_line_of_sight(player: Node2D) -> bool:
	var origem := global_position + Vector2(0.0, eye_height)
	var destino := player.global_position + Vector2(0.0, eye_height)
	var query := PhysicsRayQueryParameters2D.create(origem, destino, 1)  # 1 = Terrain
	query.exclude = [self]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _give_up() -> void:
	ignore_player_timer = ignore_after_giving_up
	_set_state(State.PATROL)


# Tentou andar e não saiu do lugar: pode ser parede ou borda
func _check_stuck(delta: float) -> void:
	var tentando_andar := (state == State.CHASE or state == State.PATROL) and absf(intended_vx) > 1.0
	if tentando_andar and absf(global_position.x - last_x) < 0.5:
		stuck_timer += delta
	else:
		stuck_timer = 0.0
	last_x = global_position.x

	if stuck_timer >= stuck_time:
		stuck_timer = 0.0
		if state == State.CHASE:
			_give_up()
		else:
			_turn()
#endregion


#region Patrulha
func _should_turn() -> bool:
	if is_on_wall():
		return true
	return is_on_floor() and not ledge_check.is_colliding()


func _turn() -> void:
	facing = -facing
	_apply_facing()
	pause_timer = pause_at_edge
	_set_state(State.PAUSE)
#endregion


#region Estados
func _set_state(new_state: State) -> void:
	state = new_state
	attack_hitbox.set_deferred("monitoring", false)

	if new_state == State.CHASE:
		lost_sight_timer = lose_sight_time
		reaction_timer = reaction_time

	match state:
		State.PATROL, State.CHASE:
			anim.play("Walk")
		State.PAUSE:
			anim.play("Idle")
		State.BLOCK:
			anim.play(BLOCK_ANIM)
		State.ATTACK:
			hit_targets.clear()
			attack_cooldown_timer = attack_cooldown
			reaction_timer = reaction_time
			anim.play(ATTACK_ANIMS.pick_random())
		State.HURT:
			anim.play("Hurt")
		State.DEAD:
			anim.play("Death")


func _on_animation_finished() -> void:
	match state:
		State.HURT, State.ATTACK:
			_set_state(State.CHASE if _see_player() else State.PATROL)


func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return
	var active := anim.frame >= attack_active_frames.x and anim.frame <= attack_active_frames.y
	attack_hitbox.set_deferred("monitoring", active)


# Único ponto que causa dano ao player: só a hitbox da animação de ataque
func _try_hit(body: Node2D) -> void:
	if state != State.ATTACK or body in hit_targets:
		return
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return
	if not _has_line_of_sight(body):
		return
	hit_targets.append(body)
	body.take_damage(attack_damage, global_position, true)
#endregion


#region Vida e morte
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO, can_be_blocked: bool = true) -> void:
	if state == State.DEAD or state == State.HURT:
		return

	# Escudo levantado: golpe de frente é bloqueado, sem dano e sem empurrão
	if state == State.BLOCK and can_be_blocked and _is_attack_from_front(source_position):
		_feedback_bloqueio()
		return

	health = maxi(health - amount, 0)
	health_bar.set_values(health, max_health)

	if health == 0:
		_die()
		return

	var push_dir: float = signf(global_position.x - source_position.x)
	if push_dir == 0.0:
		push_dir = -facing
	velocity = Vector2(push_dir * knockback_force.x, knockback_force.y)
	_set_state(State.HURT)


func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector2.ZERO
	health_bar.ocultar()
	detect_range.set_deferred("monitoring", false)
	attack_range.set_deferred("monitoring", false)
	body_shape.set_deferred("disabled", true)
	died.emit()
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)
#endregion
