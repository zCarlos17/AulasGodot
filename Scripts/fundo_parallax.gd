extends Node2D

@export var camera: Camera2D
@export var alvo: Node2D
@export var horizonte: Node2D
@export var ceu: Node2D
@export var montanhas: Node2D
@export var colinas: Node2D

@export var altura_imagem: float = 192.0
@export var zona_morta: float = 30.0
@export var max_deslocamento: float = 60.0
@export var fator_ceu: float = 0.05  # quanto o céu acompanha a altura do player
@export var fator_montanhas: float = 0.1
@export var fator_colinas: float = 0.2
@export var ajuste_vertical: float = 0.0
@export var ajuste_nuvens: float = 8.0   # negativo sobe as nuvens/montanhas (BG2)
@export var ajuste_colinas: float = 78.0  # negativo sobe as colinas, positivo desce
@export var margem_copias: int = 2
@export_range(0.0, 1.0) var proporcao_ceu: float = 0.4    # fração da tela ocupada pelo céu
@export_range(0.0, 1.0) var proporcao_montanhas: float = 0.35  # fração ocupada pelas nuvens/montanhas

var _larguras: Dictionary = {}   # camada -> largura de um sprite
var _tela_anterior: Vector2 = Vector2.ZERO
var _origem_y: Dictionary = {}   # posição original de cada camada, guardada uma vez

func _ready() -> void:
	process_priority = 1000
	for camada in [ceu, montanhas, colinas]:
		if camada != null:
			_montar_camada(camada)
	_tela_anterior = Vector2.ZERO  # força o cálculo da repetição no primeiro frame


# Cria o espelho ao lado do original e guarda a largura da imagem
func _montar_camada(camada: Node2D) -> void:
	var sprite: Sprite2D = null
	for filho in camada.get_children():
		if filho is Sprite2D:
			sprite = filho
			break
	if sprite == null or sprite.texture == null:
		push_warning("Camada '%s' sem Sprite2D com textura." % camada.name)
		return

	var largura: float = sprite.texture.get_width()
	_larguras[camada] = largura

	var espelhado := sprite.duplicate() as Sprite2D
	# duplicate() copia também os filhos (ColorRect); o espelho só precisa da imagem
	for filho in espelhado.get_children():
		filho.queue_free()
	espelhado.name = "Espelhado"
	espelhado.position.x = sprite.position.x + largura
	espelhado.flip_h = true
	camada.add_child(espelhado)
	camada.repeat_size = Vector2(largura * 2.0, 0.0)
	
# Recalcula quantos pares cobrem a tela atual. Roda de novo se a janela mudar de tamanho
func _ajustar_repeticao() -> void:
	var tela: Vector2 = get_viewport().get_visible_rect().size / camera.zoom
	# Cobre o nível inteiro (limites da câmera) mais uma tela de folga
	var mundo_w: float = float(camera.limit_right - camera.limit_left)
	var cobertura: float = maxf(mundo_w, tela.x) + tela.x
	var assinatura := Vector2(cobertura, tela.y)
	if assinatura == _tela_anterior:
		return
	_tela_anterior = assinatura

	for camada in _larguras.keys():
		var par: float = _larguras[camada] * 2.0
		camada.repeat_times = int(ceil(cobertura / par)) + margem_copias
	
func _process(_delta: float) -> void:
	if camera == null or alvo == null or horizonte == null:
		return

	_ajustar_repeticao()

	var tela: Vector2 = get_viewport().get_visible_rect().size / camera.zoom
	var topo_tela: float = camera.get_screen_center_position().y - tela.y / 2.0

	# Linhas de corte: céu 50%, montanhas 30%, colinas 20%
	var linha_ceu: float = topo_tela + tela.y * proporcao_ceu
	var linha_montanhas: float = linha_ceu + tela.y * proporcao_montanhas

	# Desejado: topo de cada imagem em sua faixa
	_deslocar(ceu, topo_tela + altura_imagem / 2.0 + ajuste_vertical)
	_deslocar(montanhas, linha_ceu - altura_imagem / 2.0 + ajuste_nuvens)
	_deslocar(colinas, linha_montanhas - altura_imagem / 2.0 + ajuste_colinas)


# Move a imagem usando scroll_offset, sem mexer na posição do nó
func _deslocar(camada: Node2D, y_desejado: float) -> void:
	var origem_y: float = _origem_y.get(camada, camada.global_position.y)
	_origem_y[camada] = origem_y
	camada.scroll_offset.y = y_desejado - origem_y
