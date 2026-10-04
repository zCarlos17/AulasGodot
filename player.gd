extends CharacterBody2D

signal died

enum State{ IDLE, RUN, JUMP, FALL, CROUNCH, ROLL, ATTACK, BLOCK, HURT, DEAD}

const ATTACK_ANIMS: Array[String] = ["Attack1", "Attack2", "Attack3"]

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

@export_group("Movimento")
@export var speed: float = 290.0
@export var acceleration: float = 1800.0        #Quao rapido ele chega na velocidade
@export var friction: float = 2200.0
@export var air_acceleration: float = 1200.0    #Controle horizontal durante o ar
@export var air_friction: float = 600.0         #Desaleração sem input

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

var state: State = State.IDLE
var facing: int = 1
var health: int = 0

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var roll_cooldown_timer: float = 0.0

var combo_index: int = 0
var attack_queued: bool = false

func _ready() -> void:
	health = max_health
	anim.animation_finished.connect(_on_animation_finished)
	_change_state(State.IDLE)

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("left", "right")
	_update_timers(delta)
	_apply_gravity(delta)
	
	match state:
		State.IDLE, State.RUN, State.JUMP, State.FALL:
			_process_free(direction, delta)
		State.CROUNCH:
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
			
		if Input.is_action_just_pressed("block"):
			_change_state(State.BLOCK)
			return
		if Input.is_action_pressed("crouch"):
			_change_state(State.CROUNCH)
			return
	_handle_jump()
	_handle_horizontal(direction, delta)

func _process_crouch(delta: float) -> void:
	_stop_horizontal(delta)
	if not Input.is_action_pressed("crouch") or not is_on_floor():
			_update_locomotion_state()

func _process_roll() -> void:
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
	
	match state:
		State.IDLE:
			anim.play("Idle")
		State.RUN:
			anim.play("Run")
		State.JUMP:
			anim.play("Jump")
		State.FALL:
			anim.play("Fall")
		State.CROUNCH:
			anim.play("Crouch")
		State.ROLL:
			anim.play("Roll")
			roll_cooldown_timer = roll_cooldown
			velocity.x = facing * roll_speed
		State.ATTACK:
			attack_queued = false
			anim.play(ATTACK_ANIMS[combo_index])
			#vamos ativar a hitbox da espada aqui
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
		State.ROLL, State.HURT:
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
