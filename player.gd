extends CharacterBody2D

signal died

enum State{ IDLE, RUN, JUMP, FALL, CROUCH, ROLL, ATTACK, BLOCK, HURT, DEAD}

const ATTACK_ANIMS: Array[String] = ["Attack1", "Attack2", "Attack3"]

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var sword_hitbox: Area2D = $SwordHitbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var ceiling_check: RayCast2D = $CeilingCheck


@export_group("Movimento")
@export var speed: float = 290.0
@export var acceleration: float = 1800.0        #Quao rapido ele chega na velocidade
@export var friction: float = 2200.0
@export var air_acceleration: float = 1200.0    #Controle horizontal durante o ar
@export var air_friction: float = 600.0         #Desaleração sem input
@export var crouch_speed: float = 100.0

@export_group("Pulo")
@export var jump_velocity: float = -400.0
@export var jump_cut_multiplier: float = 0.5      # Corta o pulo ao soltar o botão
@export var fall_gravity_multiplier: float = 1.5  # cai mais rápido do que sobe
@export var max_fall_speed: float = 700.0
@export var coyote_time: float = 0.1              # Tempo para pular logo após sair da bordae
@export var jump_buffer_time: float = 0.1         # Tempo que o pulo fica "guardado"

@export_group("Rolar")
@export var roll_speed: float = 380.0
@export var roll_cooldown: float = 0.5

@export_group("Vida")
@export var max_health: int = 100
@export var knockback_force: Vector2 = Vector2(200.0 , -200.0)

@export_group("Ataque")
@export var attack_damage: int = 10
@export var attack_active_frames: Array[Vector2i] = [
	Vector2i(2, 3),   # Attack1
	Vector2i(1, 3),   # Attack2
	Vector2i(2, 4),   # Attack3
]

@export_group("Colisão")
@export_range(0.3, 1.0) var crouch_height_ratio: float = 0.6 # altura da cápsula agachado (fração da altura em pé)
@export_range(0.3, 1.0) var roll_height_ratio: float = 0.5 # altura da cápsula rolando

var state: State = State.IDLE
var facing: int = 1
var health: int = 0

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var roll_cooldown_timer: float = 0.0

var combo_index: int = 0
var attack_queued: bool = false

var hitbox_base_x: float = 0.0
var hit_targets:Array[Node] = []

var stand_height: float =0.0
var stand_pos_y: float = 0.0
func _ready() -> void:
	#Copia propria da forma, para nao alterar o recurso compartilhado
	body_shape.shape = body_shape.shape.duplicate()
	var capsule := body_shape.shape as CapsuleShape2D
	stand_height = capsule.height
	stand_pos_y = body_shape.position.y

	_setup_ceilling_check()
	
	
	health = max_health
	hitbox_base_x = absf(sword_hitbox.position.x)
	sword_hitbox.monitoring = false
	sword_hitbox.body_entered.connect(_on_sword_hit)
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)
	_change_state(State.IDLE)

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("left", "right")
	_update_timers(delta)
	_apply_gravity(delta)
	
	match state:
		State.IDLE, State.RUN, State.JUMP, State.FALL:
			_process_free(direction, delta)
		State.CROUCH:
			_process_crouch(delta)
		State.ROLL:
			_process_roll()
		State.ATTACK:
			_process_attack(delta)
		State.BLOCK:
			_process_block(delta)
		State.HURT, State.DEAD:
			_process_stunned(delta)
			
	#_handle_jump()	
	#_handle_horizontal(direction,delta)

	move_and_slide()
	if _is_locomotion():
		_update_locomotion_state()

'''================================================================
                   Fisica Basica de Movimentação / Pulo
================================================================'''
func _update_timers(delta: float) -> void:
	#No *Coyote_time* sera renovada cada vez q tocar no chao, ssendo gasta no ar
	if is_on_floor():
		coyote_timer = coyote_time
	else :
		coyote_timer -= delta
	# No *Jump_bugger* vai guardar o aperto do botao por um instante
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta
	roll_cooldown_timer -= delta

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	
	var gravity := get_gravity()
	if velocity.y > 0.0:
		gravity *= fall_gravity_multiplier
	velocity += gravity * delta
	velocity.y = min(velocity.y, max_fall_speed)

func _handle_jump() -> void:
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
	
	#Pulo variavel: soltar o pulo = pulo mais baixo
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier
	
func _handle_horizontal(direction: float, delta: float) ->void:
	var accel := acceleration if is_on_floor() else air_acceleration
	var fricc := friction if is_on_floor() else air_friction
	
	if direction != 0.0:
		velocity.x =move_toward(velocity.x, direction * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fricc * delta)
	
func _stop_horizontal(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction*delta)

'''================================================================
                   Lógica de cada Estado
================================================================'''
func _process_free(direction: float,  delta: float) -> void:
	#Direção do player
	if  direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		anim.flip_h = facing < 0

	if is_on_floor():	#Ações que valem somente no chao
		if Input.is_action_just_pressed("attack"):
			combo_index = 0
			_change_state(State.ATTACK)
			return
		if Input.is_action_just_pressed("roll") and roll_cooldown_timer <= 0.0:
			_change_state(State.ROLL)
			return
		if Input.is_action_pressed("block"):
			_change_state(State.BLOCK)
			return
		if Input.is_action_pressed("crouch"):
			_change_state(State.CROUCH)
			return
	_handle_jump()
	_handle_horizontal(direction, delta)

func _process_crouch(delta: float) -> void:
	var direction := Input.get_axis("left", "right")
	
	if direction!= 0.0:
		facing = 1 if direction > 0.0 else -1
		anim.flip_h = facing <0 
		velocity.x = move_toward(velocity.x, direction* crouch_speed, acceleration * delta)
	else:
		_stop_horizontal(delta)
	#Caso precise rolar para sair de baixo do teto
	if Input.is_action_just_pressed("roll") and roll_cooldown_timer <= 0.0:
		_change_state(State.ROLL)
		return
	
	var wants_up: bool = not Input.is_action_pressed("crouch") or not is_on_floor()
	if wants_up and (_can_stand() or not is_on_floor()):
		_update_locomotion_state()

func _process_roll() -> void:
	if not is_on_floor():
		_change_state(State.FALL)
		return
	velocity.x = facing * roll_speed
	# O final da rolagem vai ser tratado no _on_animation_finished
func _process_attack(delta: float) -> void:
	_stop_horizontal(delta)
	#Apertando atacar durante uum golpe guarda o proximo golpe do combo
	if Input.is_action_just_pressed("attack"):
		attack_queued = true

func _process_block(delta: float) -> void:
	_stop_horizontal(delta)
	if not Input.is_action_pressed("block") or not is_on_floor():
			_update_locomotion_state()

func _process_stunned(delta: float) -> void:
	# Usado em HURT e DEAD desliza ate parar
	_stop_horizontal(delta)

'''================================================================
                       Troca de Estados
================================================================'''
func _is_locomotion() -> bool:
	return state in [State.IDLE, State.RUN, State.JUMP, State.FALL]

func _update_locomotion_state() -> void:
	var new_state: State
	
	if is_on_floor():
		new_state = State.RUN if abs(velocity.x) > 10.0 else State.IDLE
	elif velocity.y <0.0:
		new_state = State.JUMP
	else:
		new_state = State.FALL
	if new_state != state:
		_change_state(new_state)

func _change_state(new_state: State) -> void:
	state= new_state
	_update_body_shape()
	sword_hitbox.set_deferred("monitoring", false)
	
	match state:
		State.IDLE:
			anim.play("Idle")
		State.RUN:
			anim.play("Run")
		State.JUMP:
			anim.play("Jump")
		State.FALL:
			anim.play("Fall")
		State.CROUCH:
			anim.play("Crouch")
		State.ROLL:
			anim.play("Roll")
			roll_cooldown_timer = roll_cooldown
			velocity.x = facing * roll_speed
		State.ATTACK:
			attack_queued = false
			hit_targets.clear()
			sword_hitbox.position.x = hitbox_base_x * facing   # espelha para o lado certo
			anim.play(ATTACK_ANIMS[combo_index])
		State.BLOCK:
			anim.play("Blocking")
		State.HURT:
			combo_index = 0
			attack_queued = false
			anim.play("Hurt")
		State.DEAD:
			combo_index=0
			attack_queued = false
			anim.play("DeathBlood")

func  _on_animation_finished() -> void:
	match state:
		State.ROLL:
			#Terminando a rolagem de baixo de um teto baixo: fica agachado
			if _can_stand():
				_update_locomotion_state()
			else:
				_change_state(State.CROUCH)
		State.HURT:
			_update_locomotion_state()
		State.ATTACK:
			if attack_queued and combo_index < ATTACK_ANIMS.size() -1:
				combo_index += 1
				_change_state(State.ATTACK)
			else:
				combo_index = 0
				_update_locomotion_state()
		State.BLOCK:
			#Terminando de levantar o escudo, ele fica na posição de guarda
			if anim.animation == "Blocking":
				anim.play("BlockIdle")
		State.DEAD:
			died.emit()

'''================================================================
                       Logica de Dano
================================================================'''
func take_damage(amount:int , source_position: Vector2 = Vector2.ZERO) -> void:
	#Morto ou rolando (invulneravel) nao toma dano
	if state == State.DEAD or state == State.ROLL:
		return
	
	#bloqueando ignora o dano / E se o player tentar bloquear quando ele cair em armadilha? provaavelmnte vai dar bug
	if state == State.BLOCK:
		return
	
	health -= amount
	
	if health <= 0:
		_change_state(State.DEAD)
		return
	
	#Empurrao para longe  de quem causou o dano 
	var push_dir: float = signf(global_position.x - source_position.x)
	if push_dir == 0.0:
		push_dir = -facing
	velocity = Vector2 (push_dir * knockback_force.x, knockback_force.y)
	
	_change_state(State.HURT)

func _is_attack_from_front(source_position: Vector2) ->bool:
	var dir_to_source: int = int(signf(source_position.x - global_position.x))
	return dir_to_source == facing
	
func _on_frame_changed() -> void:
	if state != State.ATTACK:
		return
	var frames: Vector2i = attack_active_frames[combo_index]
	var active: bool = anim.frame >= frames.x and anim.frame <= frames.y
	sword_hitbox.set_deferred("monitoring", active)
	
func _on_sword_hit(body: Node2D) -> void:
	if body == self or body in hit_targets:
		return
	if body.has_method("take_damage"):
		hit_targets.append(body)
		body.take_damage(attack_damage, global_position)
		
'''================================================================
                       Hitbox Colisao
================================================================'''
func _set_body_height(ratio: float) -> void:
	var capsule:= body_shape.shape as CapsuleShape2D
	var new_height: float = maxf(stand_height*ratio, capsule.radius * 2.0)
	capsule.height = new_height
	body_shape.position.y = stand_pos_y + (stand_height - new_height) / 2.0

func _update_body_shape() -> void:
	match state:
		State.CROUCH:
			_set_body_height(crouch_height_ratio)
		State.ROLL:
			_set_body_height(roll_height_ratio)
		_:
			_set_body_height(1.0)

#Função para verificar se tem espaço para poder levantar
func _can_stand()-> bool:
	if ceiling_check == null:
		return true
	ceiling_check.force_raycast_update()
	return not ceiling_check.is_colliding()
	
func _setup_ceilling_check() -> void:
	if ceiling_check == null:
		return
	var capsule:= body_shape.shape as CapsuleShape2D
	var min_height: float = maxf(stand_height * minf(crouch_height_ratio, roll_height_ratio), capsule.radius * 2.0)
	var feet_y: float = stand_pos_y + stand_height /2.0
	#O raio começa no topo da capsula agachada e vai ate o topo da capsula em pe 
	ceiling_check.position = Vector2(body_shape.position.x, feet_y - min_height)
	ceiling_check.target_position = Vector2(0.0, -(stand_height - min_height))
	ceiling_check.collision_mask = 1  #Terrain
