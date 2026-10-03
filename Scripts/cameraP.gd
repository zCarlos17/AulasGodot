extends Camera2D
@export var alvo: Node2D
@export var suavizacao: float = 6.0

func _ready() -> void:
	if alvo:
		global_position = alvo.global_position

func _process(delta: float) -> void:
	# / .lerp / Linear intERPolation( interpolação linear ) 
	# Calcula um ponto entre dois valores dado quanto do caminho quero percorrer
	if alvo:
		global_position = global_position.lerp(alvo.global_position, suavizacao * delta)
