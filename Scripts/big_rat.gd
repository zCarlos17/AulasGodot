extends CharacterBody2D

#PATROL: anda em patrol_speed. Se _see_player() for verdadeiro (está no DetectedRange e há visão livre), vai para CHASE.
#CHASE: rush_timer começa em rush_time, então nos primeiros 0,5 s ele usa rush_speed (160). Depois segue em chase_speed (80).
#Obstáculo ou player fora da área: o lost_sight_timer conta e, depois de lose_sight_time, o rato desiste e volta a patrulhar.
#Dentro do AttackRange e perto do centro: para e espera reaction_time antes de atacar.

signal died

enum State { PATROL, PAUSE, CHASE, ATTACK, HURT, DEAD }

const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const ANIM_ATTACK := &"Attack"
const ANIM_HURT := &"Hurt"

@export_group("Movimentação")
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 80.0
@export var pause_at_edge: float = 1.0
@export var start_direction: int = 1
@export var rush_speed: float = 160.0   # velocidade do impulso ao avistar o player
@export var rush_time: float = 0.5      # duração do impulso, em segundos

@export_group("Percepção")
@export var lose_sight_time: float = 2.0
@export var ignore_after_giving_up: float = 3.0
@export var stuck_time: float = 0.4
@export var eye_height: float = -10.0

@export_group("Ataque")
@export var reaction_time: float = 0.3
@export var attack_damage: int = 8
@export var attack_cooldown: float = 1.0
@export var attack_active_frames: Vector2i = Vector2i(6, 10)
@export var attack_center_distance: float = 16.0  # distância horizontal máxima do centro do rato para atacar

@export_group("Vida")
@export var max_health: int = 20
@export var knockback_force: Vector2 = Vector2(150.0, -120.0)
@export var corpse_time: float = 1.5

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

# Timers
var pause_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var lost_sight_timer: float = 0.0
var ignore_player_timer: float = 0.0
var reaction_timer: float = 0.0
var hurt_timer: float = 0.0
var stuck_timer: float = 0.0
var rushing: bool = false  # True enquanto o rato corre até o centro do player

# Posições e dados
var last_x: float = 0.0
var intended_vx: float = 0.0
var hitbox_base_x: float = 0.0
var attack_range_base_x: float = 0.0
var hurt_duration: float = 0.0
var hit_targets: Array[Node] = []


func _ready() -> void:
	health = max_health
	facing = start_direction
	hitbox_base_x = absf(hitbox_shape.position.x)
	attack_range_base_x = absf(attack_range_shape.position.x)
	hurt_duration = _anim_duration(ANIM_HURT)
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
	
	match state:
		State.PATROL:
			if _see_player():
				_set_state(State.CHASE)
			elif _should_turn():
				_turn()
			else:
				velocity.x = facing * patrol_speed

		State.PAUSE:
			velocity.x = move_toward(velocity.x, 0.0, patrol_speed * 4.0 * delta)
			pause_timer -= delta
			if _see_player():
				_set_state(State.CHASE)
			elif pause_timer <= 0.0:
				_set_state(State.PATROL)

		State.CHASE:
			var player := _find_player(detect_range)
			if player != null and _has_line_of_sight(player):
				lost_sight_timer = lose_sight_time
				_chase_player(player)
			else:
				velocity.x = 0.0
				lost_sight_timer -= delta
				if lost_sight_timer <= 0.0:
					_give_up()

		State.ATTACK:
			velocity.x = move_toward(velocity.x, 0.0, patrol_speed * 4.0 * delta)

		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
			hurt_timer -= delta
			if hurt_timer <= 0.0:
				_set_state(State.CHASE if _see_player() else State.PATROL)

		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)

	intended_vx = velocity.x
	move_and_slide()

	if state == State.CHASE:
		_update_chase_anim()

	# Quem já está dentro da hitbox não dispara body_entered, então confere a cada frame de ataque
	if state == State.ATTACK and attack_hitbox.monitoring:
		for body in attack_hitbox.get_overlapping_bodies():
			_try_hit(body)

	_check_stuck(delta)
	if Engine.get_physics_frames() % 30 == 0:
		var p := _find_player(detect_range)
		print(name, " | estado=", State.keys()[state], " | facing=", facing, " | vx=", snappedf(velocity.x, 0.1), " | parede=", is_on_wall(), " | chao=", is_on_floor(), " | player_na_area=", p != null, " | visao=", p != null and _has_line_of_sight(p))

#region Perseguição
func _chase_player(player: Node2D) -> void:
	var dx: float = player.global_position.x - global_position.x
	var dir: int = int(signf(dx))
	if dir != 0 and dir != facing:
		facing = dir
		_apply_facing()

	var no_alcance: bool = _find_player(attack_range) != null
	var perto_do_centro: bool = absf(dx) <= attack_center_distance

	if perto_do_centro:
		rushing = false  # chegou perto: para de correr

	if no_alcance and perto_do_centro:
		# Perto do centro: ataca na hora, se o cooldown já tiver acabado
		velocity.x = 0.0
		if attack_cooldown_timer <= 0.0 and is_on_floor():
			_set_state(State.ATTACK)
	else:
		_chase_step()
		
func _chase_step() -> void:
	var velocidade: float = rush_speed if rushing else chase_speed
	if is_on_floor() and not ledge_check.is_colliding():
		velocity.x = 0.0
	else:
		velocity.x = facing * velocidade

func _apply_facing() -> void:
	anim.flip_h = facing < 0
	ledge_check.position.x = absf(ledge_check.position.x) * facing
	attack_range_shape.position.x = attack_range_base_x * facing
	hitbox_shape.position.x = hitbox_base_x * facing


# Toca Walk só quando anda; parado durante a perseguição vira Idle
func _update_chase_anim() -> void:
	var parado: bool = absf(velocity.x) < 5.0
	anim.speed_scale = 1.5 if rushing else 1.0
	var nome: StringName = ANIM_IDLE if parado else ANIM_WALK
	if anim.animation != nome:
		anim.play(nome)
#endregion


#region Percepção
func _see_player() -> bool:
	if ignore_player_timer > 0.0:
		return false
	var player := _find_player(detect_range)
	return player != null and _has_line_of_sight(player)

func _find_player(area: Area2D) -> Node2D:
	if not area.monitoring:
		return null  # área desligada (ex.: rato morto): não há o que procurar
	for body in area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return body
	return null


# Confere se há terreno entre o rato e o player, na altura da cabeça e do corpo
func _has_line_of_sight(player: Node2D) -> bool:
	var cabeca_ok: bool = _ray_clear(
		global_position + Vector2(0.0, eye_height),
		player.global_position + Vector2(0.0, eye_height))
	var corpo_ok: bool = _ray_clear(
		global_position + Vector2(0.0, -4.0),
		player.global_position + Vector2(0.0, -4.0))
	return cabeca_ok and corpo_ok


func _ray_clear(origem: Vector2, destino: Vector2) -> bool:
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
	# Só vira se a parede estiver na frente, na direção em que anda
	if is_on_wall() and signf(get_wall_normal().x) == -facing:
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
	anim.speed_scale = 1.0
	rushing = false  # sai de qualquer estado com a corrida desligada

	match state:
		State.PATROL:
			anim.play(ANIM_WALK)
		State.CHASE:
			anim.play(ANIM_WALK)
			rushing = true  # corre até o player chegar perto do centro
		State.PAUSE:
			anim.play(ANIM_IDLE)
		State.ATTACK:
			hit_targets.clear()
			attack_cooldown_timer = attack_cooldown
			reaction_timer = reaction_time
			anim.play(ANIM_ATTACK)
		State.HURT:
			anim.play(ANIM_HURT)
			hurt_timer = hurt_duration + 0.1  # rede de segurança caso animation_finished falhe
		State.DEAD:
			pass  # sem animação de morte: fica no último quadro e some aos poucos

func _on_animation_finished() -> void:
	if state == State.ATTACK or state == State.HURT:
		_set_state(State.CHASE if _see_player() else State.PATROL)


# Liga a hitbox só nos quadros de golpe
func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return
	var active: bool = anim.frame >= attack_active_frames.x and anim.frame <= attack_active_frames.y
	attack_hitbox.set_deferred("monitoring", active)


# Único ponto que causa dano ao player: só a hitbox do ataque
func _try_hit(body: Node2D) -> void:
	if state != State.ATTACK or body in hit_targets:
		return
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return
	if not _has_line_of_sight(body):
		return
	hit_targets.append(body)
	body.take_damage(attack_damage, global_position, true)


# Duração total (segundos) de uma animação do SpriteFrames
func _anim_duration(nome: StringName) -> float:
	var frames: SpriteFrames = anim.sprite_frames
	if frames == null or not frames.has_animation(nome):
		return 0.0
	var fps: float = frames.get_animation_speed(nome)
	if fps <= 0.0:
		return 0.0
	var total: float = 0.0
	for i in frames.get_frame_count(nome):
		total += frames.get_frame_duration(nome, i)
	return total / fps
#endregion


#region Vida e morte
# Mesma assinatura do player, para a espada funcionar no rato
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO, _can_be_blocked: bool = true, _ignores_roll: bool = false) -> void:
	if state == State.DEAD or state == State.HURT:
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
	anim.pause()  # congela no quadro atual, pois não há animação de morte
	health_bar.ocultar()
	detect_range.set_deferred("monitoring", false)
	attack_range.set_deferred("monitoring", false)
	body_shape.set_deferred("disabled", true)
	died.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, corpse_time)
	tween.finished.connect(queue_free)
#endregion
