extends CharacterBody2D

signal died

enum State { PATROL, PAUSE, CHASE, ATTACK, HURT, DEAD }
enum AttackPhase { HOP, WAIT, DASH, STOP }

const ATTACK_ANIMS: Array[String] = ["Attack1", "Attack2"]

# Caixa de dano de cada golpe: pos (x para a frente do Goblin, y) e tamanho
const ATTACK_HITBOX := {
	"Attack1": {"pos": Vector2(29.0, 11.0), "size": Vector2(44.0, 30.0)},
	"Attack2": {"pos": Vector2(40.0, -8.0), "size": Vector2(80.0, 30.0)},
}
# Ajuste de posição por frame: { "Attack2": { frame: Vector2(x, y) } }
const FRAME_OFFSETS := {
	"Attack2": {
		0:Vector2(-21.0, 0.0),
		1:Vector2(-21.0, 0.0),
		2:Vector2(-40.0, 0.0),
		3: Vector2(-40.0, 0.0),
		4: Vector2(-10.0, 0.0),
	},
}

@export_group("Movimentação")
@export var patrol_speed: float = 50.0
@export var chase_speed: float = 110.0
@export var pause_at_edge: float = 1.0
@export var start_direction: int = 1
@export var stop_distance: float = 22.0

@export_group("Ataque 2 (pulo e dash)")
@export var hop_distance: float = 50.0        # quanto recua no pulo
@export var hop_time: float = 0.35            # duração do pulo (deve terminar antes do dash_start_frame)
@export var dash_start_frame: int = 3         # frame em que o dash pode começar (depois de pousar)
@export var dash_hit_frame: int = 6           # frame em que o golpe deve alcançar o player
@export var dash_contact_gap: float = 14.0    # distância do centro do player em que o dash para
@export var dash_max_speed: float = 600.0     # limite de velocidade do dash

@export_group("Percepção")
@export var lose_sight_time: float = 2.0
@export var ignore_after_giving_up: float = 3.0
@export var stuck_time: float = 0.4
@export var eye_height: float = -10.0

@export_group("Ataque")
@export var reaction_time: float = 0.4
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.2
@export var attack_active_frames: Vector2i = Vector2i(6, 7)
@export var attack_spacing: float = 10.0   # folga para o player poder reagir antes do golpe
@export var dash_end_frame: int = 5          # último frame do avanço visual
@export var wall_stop_distance: float = 30.0  # distância da parede em que o avanço para (ajuste medindo o alcance da arma)

@export_group("Vida")
@export var max_health: int = 30
@export var knockback_force: Vector2 = Vector2(180.0, -160.0)
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
var attack_phase: AttackPhase = AttackPhase.HOP

var health: int = 0
var facing: int = 1
#Timersd
var pause_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var lost_sight_timer: float = 0.0
var ignore_player_timer: float = 0.0
var reaction_timer: float = 0.0
var hop_timer: float = 0.0
var stuck_timer: float = 0.0
var hurt_timer: float = 0.0
#Posições
var last_x: float = 0.0
var intended_vx: float = 0.0
var attack_range_base_x: float = 0.0
var hitbox_pos: Vector2 = Vector2.ZERO
var hit_targets: Array[Node] = []


func _ready() -> void:
	health = max_health
	facing = start_direction
	attack_range_base_x = absf(attack_range_shape.position.x)
	hitbox_shape.shape = hitbox_shape.shape.duplicate()
	last_x = global_position.x
	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_on_hitbox_body_entered)
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	health_bar.set_values(health, max_health)
	_apply_attack_hitbox("Attack1")
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
				_chase_player(player, delta)
			else:
				velocity.x = 0.0
				lost_sight_timer -= delta
				if lost_sight_timer <= 0.0:
					_give_up()

		State.ATTACK:
			_attack_movement(delta)

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
		
	# Acerta quem já está dentro da hitbox (body_entered não dispara para eles)
	if state == State.ATTACK and attack_hitbox.monitoring:
		for body in attack_hitbox.get_overlapping_bodies():
			_on_hitbox_body_entered(body)

	_check_stuck(delta)


#region Movimento dos golpes
# Controla o movimento de cada golpe, em fases
func _attack_movement(delta: float) -> void:
	if str(anim.animation) != "Attack2":
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		return

	match attack_phase:
		AttackPhase.HOP:
			hop_timer += delta
			if hop_timer > 0.1 and is_on_floor():
				attack_phase = AttackPhase.WAIT
		AttackPhase.WAIT:
			velocity.x = 0.0
			if anim.frame >= dash_start_frame:
				attack_phase = AttackPhase.DASH
		AttackPhase.DASH:
			var parede: float = _distance_to_wall()
			var parede_perto: bool = parede >= 0.0 and parede <= wall_stop_distance
			if is_on_wall() or parede_perto or anim.frame > dash_end_frame:
				attack_phase = AttackPhase.STOP
				velocity.x = 0.0
			else:
				velocity.x = _dash_speed()
		AttackPhase.STOP:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)

func _start_hop() -> void:
	var g: float = get_gravity().y
	velocity.x = -facing * hop_distance / hop_time
	# Velocidade vertical que faz o pulo durar hop_time (sobe e desce)
	velocity.y = -g * hop_time * 0.5


# Velocidade que faz o Goblin chegar ao player exatamente no frame do golpe
func _dash_speed() -> float:
	var player := _find_player(detect_range)
	var tempo: float = _time_until_frame(dash_hit_frame)
	if player == null or tempo <= 0.0:
		return 0.0

	var alvo_x: float = player.global_position.x - facing * dash_contact_gap
	var distancia: float = alvo_x - global_position.x
	var vel: float = clampf(distancia / tempo, -dash_max_speed, dash_max_speed)
	return vel
	
# Distância até uma parede na frente do Goblin, ou -1 se não houver
func _distance_to_wall() -> float:
	var origem := global_position + Vector2(0.0, -10.0)
	var destino := origem + Vector2(facing * 200.0, 0.0)
	var query := PhysicsRayQueryParameters2D.create(origem, destino, 1)  # 1 = Terrain
	query.exclude = [self]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return origem.distance_to(hit.position)

# Tempo (em segundos) até o início de um quadro, considerando a animação atual
func _time_until_frame(target: int) -> float:
	var nome: String = str(anim.animation)
	var frames: SpriteFrames = anim.sprite_frames
	var fps: float = frames.get_animation_speed(nome)
	if fps <= 0.0:
		return 0.0

	var total: float = 0.0
	for i in range(anim.frame, target):
		total += frames.get_frame_duration(nome, i) / fps

	# Desconta o quanto o quadro atual já passou
	total -= anim.frame_progress * frames.get_frame_duration(nome, anim.frame) / fps
	return maxf(total, 0.0)
#endregion


#region Perseguição
func _chase_player(player: Node2D, delta: float) -> void:
	var dx: float = player.global_position.x - global_position.x
	var dir: int = int(signf(dx))
	if dir != 0 and dir != facing:
		facing = dir
		_apply_facing()

	var distancia: float = absf(dx)
	var ideal: float = _ideal_distance()
	var no_alcance: bool = distancia <= ideal + 4.0

	if no_alcance and attack_cooldown_timer <= 0.0 and is_on_floor():
		velocity.x = 0.0
		reaction_timer -= delta
		if reaction_timer <= 0.0:
			_set_state(State.ATTACK)
	elif distancia <= ideal:
		# Chegou na distância: para e espera o cooldown, sem avançar
		velocity.x = 0.0
		reaction_timer = reaction_time
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
	hitbox_shape.position = Vector2(hitbox_pos.x * facing, hitbox_pos.y)


# Ajusta a caixa de dano para o golpe que está tocando
func _apply_attack_hitbox(nome: String) -> void:
	var cfg: Dictionary = ATTACK_HITBOX.get(nome, ATTACK_HITBOX["Attack1"])
	hitbox_pos = cfg["pos"]
	(hitbox_shape.shape as RectangleShape2D).size = cfg["size"]
	_apply_facing()
	
# Distância ideal: a borda do golpe mais curto, menos uma folga para o player reagir
func _ideal_distance() -> float:
	var cfg: Dictionary = ATTACK_HITBOX["Attack1"]
	var alcance: float = cfg["pos"].x + cfg["size"].x / 2.0
	return alcance - attack_spacing
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

	if new_state == State.CHASE:
		lost_sight_timer = lose_sight_time
		reaction_timer = reaction_time

	match state:
		State.PATROL, State.CHASE:
			anim.play("Run")
		State.PAUSE:
			anim.play("Idle")
		State.ATTACK:
			hit_targets.clear()
			attack_cooldown_timer = attack_cooldown
			reaction_timer = reaction_time
			var nome: String = ATTACK_ANIMS.pick_random()
			anim.play(nome)
			_apply_attack_hitbox(nome)
			attack_phase = AttackPhase.HOP
			hop_timer = 0.0
			if nome == "Attack2":
				_start_hop()
		State.HURT:
			anim.play("Take_Hit")
			hurt_timer = _anim_duration("Take_Hit") + 0.1
		State.DEAD:
			anim.play("Death")

# Duração total (em segundos) de uma animação do SpriteFrames
func _anim_duration(nome: String) -> float:
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

func _on_animation_finished() -> void:
	match state:
		State.HURT, State.ATTACK:
			_set_state(State.CHASE if _see_player() else State.PATROL)

func _apply_frame_offset() -> void:
	var tabela: Dictionary = FRAME_OFFSETS.get(str(anim.animation), {})
	anim.offset = tabela.get(anim.frame, Vector2.ZERO)

func _on_frame_changed() -> void:
	_apply_frame_offset()
	if state != State.ATTACK:
		return
	var active: bool = anim.frame >= attack_active_frames.x and anim.frame <= attack_active_frames.y
	attack_hitbox.set_deferred("monitoring", active)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if state != State.ATTACK or body in hit_targets:
		return
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return
	if not _has_line_of_sight(body):
		return
	hit_targets.append(body)
	body.take_damage(attack_damage, global_position, true)

# Toca Run só quando está se movendo; parado durante a perseguição vira Idle
func _update_chase_anim() -> void:
	var parado: bool = absf(velocity.x) < 5.0
	var nome: String = "Idle" if parado else "Run"
	if anim.animation != nome:
		anim.play(nome)
#endregion


#region Vida e morte
func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO, _can_be_blocked: bool = true) -> void:
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
	health_bar.ocultar()
	detect_range.set_deferred("monitoring", false)
	attack_range.set_deferred("monitoring", false)
	body_shape.set_deferred("disabled", true)
	died.emit()
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)
#endregion
