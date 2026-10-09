class_name EnemyHealthBar
extends Node2D

#A fonte da quantidade de vida, esta muito feia, essa parte de "decoração" devera ser arrumada posteriormente

@export var largura: float = 40.0
@export var altura: float = 9.0
@export var cor_vida: Color = Color(0.85, 0.15, 0.2)
@export var cor_rastro: Color = Color(1.0, 0.85, 0.3)
@export var cor_fundo: Color = Color(0.0, 0.0, 0.0, 0.7)
@export var cor_borda: Color = Color(0.1, 0.05, 0.1)
@export var mostrar_texto: bool = true
@export var cor_texto: Color = Color(1.0, 1.0, 1.0)
@export var cor_contorno: Color = Color(0.0, 0.0, 0.0, 0.9)
@export var tamanho_texto: int = 7
@export var fonte: Font                      # opcional: fonte pixel importada
@export var velocidade_rastro: float = 0.8   # fração do máximo por segundo
@export var mostrar_cheia: bool = false

var _maximo: float = 1.0
var _atual: float = 1.0
var _exibido: float = 1.0
var _iniciada: bool = false


func _ready() -> void:
	z_index = 1
	visible = true
	if fonte == null:
		fonte = ThemeDB.fallback_font


# Chame sempre que a vida do inimigo mudar
func set_values(atual: int, maximo: int) -> void:
	_maximo = maxf(float(maximo), 1.0)
	_atual = clampf(float(atual), 0.0, _maximo)
	if not _iniciada:
		_exibido = _atual
		_iniciada = true
	queue_redraw()


func ocultar() -> void:
	visible = false


func _process(delta: float) -> void:
	if not is_equal_approx(_exibido, _atual):
		_exibido = move_toward(_exibido, _atual, _maximo * velocidade_rastro * delta)
		queue_redraw()


func _draw() -> void:
	# Posições e larguras arredondadas em pixels inteiros, para a barra ficar nítida
	var x: float = roundf(-largura / 2.0)
	var w: float = roundf(largura)
	var h: float = roundf(altura)

	draw_rect(Rect2(x - 1.0, -1.0, w + 2.0, h + 2.0), cor_borda)
	draw_rect(Rect2(x, 0.0, w, h), cor_fundo)
	draw_rect(Rect2(x, 0.0, roundf(w * _exibido / _maximo), h), cor_rastro)
	draw_rect(Rect2(x, 0.0, roundf(w * _atual / _maximo), h), cor_vida)

	if mostrar_texto:
		_draw_texto(x, w, h)


func _draw_texto(x: float, w: float, h: float) -> void:
	var porcentagem: int = roundi(_atual / _maximo * 100.0)
	var texto := "%d%% (%d/%d)" % [porcentagem, roundi(_atual), roundi(_maximo)]

	var largura_texto: float = fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho_texto).x
	var ascent: float = fonte.get_ascent(tamanho_texto)
	var descent: float = fonte.get_descent(tamanho_texto)

	# Centraliza na horizontal e na vertical dentro da barra, em pixels inteiros
	var pos := Vector2(
		roundf(x + (w - largura_texto) / 2.0),
		roundf((h - (ascent + descent)) / 2.0 + ascent)
	)

	# Contorno escuro em volta do texto, para ler bem em cima da barra vermelha
	draw_string_outline(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho_texto, 1, cor_contorno)
	draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho_texto, cor_texto)
