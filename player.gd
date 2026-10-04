extends CharacterBody2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@export_group("Movimento")
@export var speed: float = 290.0
@export var acceleration: float = 1800.0        #Quao rapido ele chega na velocidade
@export var friction: float = 2200.0
@export var jump_acceleration: float = 2200.0   #Quao rapido para
@export var air_acceleration: float = 1200.0    #Controle horizontal durante o ar
@export var air_friction: float = 600.0         #Desaleração sem input

@export_group("Pulo")
@export var jump_velocity: float = 2200.0
@export var jump_cut_multiplier: float = 0.5      # Corta o pulo ao soltar o botão
@export var fall_gravity_multiplier: float = 1.5  # cai mais rápido do que sobe
@export var max_fall_speed: float = 700.0
@export var coyote_time: float = 0.1              # Tempo para pular logo após sair da bordae
@export var jump_buffer_time: float = 0.1         # Tempo que o pulo fica "guardado"

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("left", "right")
	_update_timers(delta)
	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal(direction,delta)
	
	move_and_slide()
	
	_update_animation(direction)

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
	
	
func _update_animation(direction: float) -> void:
	if  direction != 0.0:
		anim.flip_h = direction < 0.0
	if is_on_floor():
		if abs(velocity.x) > 10.0:
			anim.play("Run")
		else:
			anim.play("Idle")
	else:#como temos animação de queda, vamos usar ela na descida
		if velocity.y> 0.0 and anim.sprite_frames.has_animation("Fall"):
			anim.play("Fall")
		else:
			anim.play("Jump")
		
	pass
