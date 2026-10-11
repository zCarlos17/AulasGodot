extends Node2D

@export var alvo: Node2D
@export var marcador_inicio: Node2D
@export var marcador_fim: Node2D
# Camadas do chão (Colinas, Nuvens, Céu atual)
@export var camadas_chao: Array[Parallax2D] = []
# Camadas do céu novo (ainda não criadas)
@export var camadas_ceu: Array[Parallax2D] = []
@export var distancia_saida: float = 360.0
@export var distancia_entrada: float = 360.0

var _base: Dictionary = {}  # Scroll Offset y original de cada camada


func _ready() -> void:
	for camada in camadas_chao + camadas_ceu:
		_base[camada] = camada.scroll_offset.y


func _process(_delta: float) -> void:
	if alvo == null or marcador_inicio == null or marcador_fim == null:
		return

	var y_inicio: float = marcador_inicio.global_position.y
	var y_fim: float = marcador_fim.global_position.y
	var altura: float = y_inicio - y_fim
	if altura <= 0.0:
		return

	# 0 = embaixo, na marca de início. 1 = em cima, na marca de fim.
	var t: float = clampf((y_inicio - alvo.global_position.y) / altura, 0.0, 1.0)

	for camada in camadas_chao:
		camada.scroll_offset.y = _base[camada] + t * distancia_saida

	for camada in camadas_ceu:
		camada.scroll_offset.y = _base[camada] + (1.0 - t) * distancia_entrada
