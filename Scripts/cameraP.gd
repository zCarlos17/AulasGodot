extends Camera2D

@export var alvo: Node2D
@export var suavizacao: float = 6.0

# 1.0 = padrão, menor que 1 = mais longe, maior que 1 = mais perto
@export_range(0.5, 3.0, 0.05) var zoom_camera: float = 1.0:
	set(valor):
		zoom_camera = valor
		zoom = Vector2(valor, valor)

@export_group("Limites")
# Só a horizontal é travada pelo nível. A vertical é livre.
@export var usar_limites: bool = true
@export var margem_esquerda: int = 0
@export var margem_direita: int = 0


func _ready() -> void:
	zoom = Vector2(zoom_camera, zoom_camera)
	if alvo:
		global_position = alvo.global_position
		if alvo.has_signal("respawned"):
			alvo.respawned.connect(_on_alvo_respawned)
	if usar_limites:
		_aplicar_limites()
	reset_smoothing()


func _process(delta: float) -> void:
	if alvo == null:
		return
	# Interpolação independente do FPS: o tempo de aproximação é o mesmo em qualquer máquina
	var peso: float = 1.0 - exp(-suavizacao * delta)
	global_position = global_position.lerp(alvo.global_position, peso)


func _on_alvo_respawned() -> void:
	global_position = alvo.global_position
	reset_smoothing()


func _aplicar_limites() -> void:
	var mapa := get_tree().get_first_node_in_group("limites_camera") as TileMapLayer
	if mapa == null:
		push_warning("Nenhum TileMapLayer no grupo 'limites_camera'. A câmera ficará sem limites.")
		return

	var area := mapa.get_used_rect()
	var tam := Vector2(mapa.tile_set.tile_size)
	var canto_esq := mapa.to_global(Vector2(area.position) * tam)
	var canto_dir := mapa.to_global(Vector2(area.end) * tam)

	# Horizontal: travada pelo nível
	limit_left = int(canto_esq.x - margem_esquerda * tam.x)
	limit_right = int(canto_dir.x + margem_direita * tam.x)

	# Vertical: livre
	limit_top = -10000000
	limit_bottom = 10000000
