extends Node2D
## NPC com estados. Agora só o estado PARADO (Idle) está ativo.
## Os blocos marcados com FUTURO estão comentados. Para ativar um deles,
## selecione o bloco e pressione Ctrl+K.

enum Estado { PARADO }

@export_group("Aparência")
@export var anim_parado: StringName = &"idle"

@onready var sprite: AnimatedSprite2D = $Sprite

var estado: Estado = Estado.PARADO


func _ready() -> void:
	trocar_estado(Estado.PARADO)


#region Troca de estados
# Único ponto que muda de estado
func trocar_estado(novo: Estado) -> void:
	_sair_estado(estado)
	estado = novo
	_entrar_estado(novo)


func _entrar_estado(novo: Estado) -> void:
	match novo:
		Estado.PARADO:
			_tocar(anim_parado)
		# FUTURO: casos ANDANDO e CONVERSANDO entram aqui (ver os blocos abaixo)


func _sair_estado(antigo: Estado) -> void:
	match antigo:
		Estado.PARADO:
			pass
		# FUTURO: o caso CONVERSANDO sai aqui (ver o bloco de conversa)
#endregion


#region Animação
# Toca a animação só se ela existir e se ainda não estiver tocando
func _tocar(nome: StringName) -> void:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(nome):
		push_warning("NPC '%s': animação '%s' não existe no SpriteFrames." % [name, nome])
		return
	if sprite.animation != nome:
		sprite.play(nome)
#endregion


# ============================================================
# FUTURO 1: ANDAR
# Para ativar, além de descomentar este bloco:
#   - no enum, adicione ANDANDO: enum Estado { PARADO, ANDANDO }
#   - em _entrar_estado, adicione: Estado.ANDANDO: _tocar(anim_andando)
#   - no SpriteFrames, crie a animação "walk" com Loop ligado
# ============================================================
# @export_group("Movimento")
# @export var velocidade: float = 40.0
# @export var anim_andando: StringName = &"walk"
#
# var direcao: int = 0
#
# func _physics_process(delta: float) -> void:
# 	match estado:
# 		Estado.ANDANDO:
# 			_processar_andando(delta)
#
# func _processar_andando(delta: float) -> void:
# 	position.x += direcao * velocidade * delta
# 	sprite.flip_h = direcao < 0
#
# # Pedido público: outro script ou um timer manda o NPC andar
# func andar(sentido: int) -> void:
# 	direcao = clampi(sentido, -1, 1)
# 	if direcao == 0:
# 		return
# 	trocar_estado(Estado.ANDANDO)
#
# # Pedido público: para de andar e volta ao parado
# func parar() -> void:
# 	if estado == Estado.ANDANDO:
# 		trocar_estado(Estado.PARADO)


# ============================================================
# FUTURO 2: CONVERSAR
# Para ativar, além de descomentar este bloco:
#   - no enum, adicione CONVERSANDO: enum Estado { PARADO, CONVERSANDO }
#     (se o andar também estiver ativo, use { PARADO, ANDANDO, CONVERSANDO })
#   - em _entrar_estado, adicione:
#       Estado.CONVERSANDO:
#           _tocar(anim_parado)
#           conversa_iniciada.emit()
#   - em _sair_estado, adicione:
#       Estado.CONVERSANDO:
#           conversa_terminada.emit()
#   - na cena, crie os nós AreaInteracao (Area2D) e Balao (Label)
#   - no _ready, chame _preparar_conversa()
#   - se o andar estiver ativo, no início de andar() adicione:
#       if estado == Estado.CONVERSANDO: return
# ============================================================
# signal conversa_iniciada
# signal conversa_terminada
#
# @export_group("Diálogo")
# @export var falas: Array[String] = ["Olá, viajante!"]
#
# @onready var area: Area2D = $AreaInteracao
# @onready var balao: Label = $Balao
#
# var jogador_perto: bool = false
# var _indice_fala: int = 0
#
# func _preparar_conversa() -> void:
# 	area.body_entered.connect(_on_body_entered)
# 	area.body_exited.connect(_on_body_exited)
# 	balao.visible = false
#
# func _unhandled_input(event: InputEvent) -> void:
# 	if not jogador_perto or not event.is_action_pressed("interact"):
# 		return
# 	get_viewport().set_input_as_handled()
# 	_interagir()
#
# func _interagir() -> void:
# 	if estado == Estado.CONVERSANDO:
# 		_indice_fala += 1
# 		if _indice_fala >= falas.size():
# 			trocar_estado(Estado.PARADO)
# 		_atualizar_balao()
# 	else:
# 		if falas.is_empty():
# 			return
# 		_indice_fala = 0
# 		trocar_estado(Estado.CONVERSANDO)
# 		_atualizar_balao()
#
# func _atualizar_balao() -> void:
# 	if estado == Estado.CONVERSANDO:
# 		balao.text = falas[_indice_fala]
# 		balao.visible = true
# 	elif jogador_perto:
# 		balao.text = "E: falar"
# 		balao.visible = true
# 	else:
# 		balao.visible = false
#
# func _on_body_entered(body: Node2D) -> void:
# 	if body.is_in_group("player"):
# 		jogador_perto = true
# 		_atualizar_balao()
#
# func _on_body_exited(body: Node2D) -> void:
# 	if body.is_in_group("player"):
# 		jogador_perto = false
# 		if estado == Estado.CONVERSANDO:
# 			trocar_estado(Estado.PARADO)
# 		_atualizar_balao()
