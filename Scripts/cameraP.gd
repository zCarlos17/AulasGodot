extends Camera2D

@export var alvo: Node2D
@export var suavizacao: float = 6.0

@export_group("Limites")
@export var usar_limites: bool = true
# Tiles extras permitidos além da área pintada (útil para mostrar o céu acima do terreno)
@export var margem_cima: int = 6
@export var margem_baixo: int = 0
@export var margem_esquerda: int = 0
@export var margem_direita: int = 0


func _ready() -> void:
	if alvo:
		global_position = alvo.global_position
		if alvo.has_signal("respawned"):
			alvo.respawned.connect(_on_alvo_respawned)
	if usar_limites:
		_aplicar_limites()
	reset_smoothing()


func _process(delta: float) -> void:
	if alvo:
		global_position = global_position.lerp(alvo.global_position, suavizacao * delta)

func _on_alvo_respawned()-> void:
	global_position = alvo.global_position

func _aplicar_limites() -> void:
	var mapa := get_tree().get_first_node_in_group("limites_camera") as TileMapLayer
	if mapa == null:
		push_warning("Nenhum TileMapLayer no grupo 'limites_camera'. A câmera ficará sem limites.")
		return

	var area := mapa.get_used_rect()
	var tam := Vector2(mapa.tile_set.tile_size)

	var canto_cima_esq := mapa.to_global(Vector2(area.position) * tam)
	var canto_baixo_dir := mapa.to_global(Vector2(area.end) * tam)

	limit_left = int(canto_cima_esq.x - margem_esquerda * tam.x)
	limit_top = int(canto_cima_esq.y - margem_cima * tam.y)
	limit_right = int(canto_baixo_dir.x + margem_direita * tam.x)
	limit_bottom = int(canto_baixo_dir.y + margem_baixo * tam.y)
