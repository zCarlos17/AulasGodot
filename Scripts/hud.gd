extends CanvasLayer

@export var player: CharacterBody2D
@export var tamanho_barra: Vector2 = Vector2(220, 18)
@export var margem: int = 16
@export var cor_vida: Color = Color(0.85, 0.15, 0.2)
@export var cor_rastro: Color = Color(1.0, 0.85, 0.3)
@export var espera_rastro: float = 0.4 #Tempo parado antes de o rastro descer
@export var duracao_rastro: float = 0.4 #Tempo que o rastro alcançar

@onready var container: MarginContainer = $MarginContainer
@onready var barra_atraso: ProgressBar = $MarginContainer/BarraAtraso
@onready var barra_vida: ProgressBar = $MarginContainer/BarraVida

var _tween: Tween

func _ready() -> void:
	_montar_visual()
	
	if player == null:
		push_warning("HUD sem Player. Arraste o Player para o campo 'Player' no Inspetor.") 
		return
	#Vamos definir aqui o valor inicial ( o max_health já existe mesmo antes do _ready do player)
	_definir_maximo(player.max_health)
	barra_vida.value = player.max_health
	barra_atraso.value = player.max_health
	
	player.health_changed.connect(_on_health_changed)


func _montar_visual() -> void:
	for lado in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		container.add_theme_constant_override(lado, margem)

	for b: ProgressBar in [barra_vida, barra_atraso]:
		b.show_percentage = false
		b.custom_minimum_size = tamanho_barra

	# Barra de trás: fundo escuro + rastro amarelo
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	fundo.set_border_width_all(2)
	fundo.border_color = Color(0.1, 0.05, 0.1)
	var rastro := StyleBoxFlat.new()
	rastro.bg_color = cor_rastro
	barra_atraso.add_theme_stylebox_override("background", fundo)
	barra_atraso.add_theme_stylebox_override("fill", rastro)

	# Barra da frente: sem fundo, só a vida atual
	var vida := StyleBoxFlat.new()
	vida.bg_color = cor_vida
	barra_vida.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	barra_vida.add_theme_stylebox_override("fill", vida)


func _definir_maximo(maximo: int) -> void:
	barra_vida.max_value = maximo
	barra_atraso.max_value = maximo


func _on_health_changed(atual: int, maximo: int) -> void:
	_definir_maximo(maximo)
	barra_vida.value = atual

	if _tween:
		_tween.kill()

	# Cura: o rastro acompanha na hora
	if atual >= barra_atraso.value:
		barra_atraso.value = atual
		return

	# Dano: o rastro espera um pouco e depois desce até a vida atual
	_tween = create_tween()
	_tween.tween_interval(espera_rastro)
	_tween.tween_property(barra_atraso, "value", atual, duracao_rastro)
