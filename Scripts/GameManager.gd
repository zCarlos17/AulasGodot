extends Node

var checkpoint_position: Vector2 = Vector2.ZERO
var tem_checkpoint: bool = false

var _player:CharacterBody2D
var _fade: ColorRect
var _respawnando: bool = false

func _ready() -> void:
	#Tela preta das transições 
	var camada:= CanvasLayer.new()
	camada.layer = 100
	add_child(camada)
	
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	camada.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func registrar_player(player: CharacterBody2D)-> void:
	_player = player
	if not tem_checkpoint:
		checkpoint_position = player.global_position #ponto que o player surge
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
		
func set_checkpoint(posicao: Vector2) -> void:
	checkpoint_position = posicao
	tem_checkpoint = true

func resetar()-> void:          #Chamar quando começar uma faase nova para esquecer o checkpoint anterior
	tem_checkpoint = false
	_respawnando = false
	
func _on_player_died()-> void:
	if _respawnando:
		return
	_respawnando = true
	
	await get_tree().create_timer(0.4).timeout # Pausa rapida depois que o player morre

	var escurecer := create_tween()
	escurecer.tween_property(_fade, "modulate:a", 1.0, 0.4)
	await escurecer.finished
	
	_player.respawn(checkpoint_position)
	await  get_tree().create_timer(0.2).timeout
	
	var clarear := create_tween()
	clarear.tween_property(_fade, "modulate:a", 0.0,0.4)
	await  clarear.finished
	_respawnando = false
