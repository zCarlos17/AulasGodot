extends Area2D

# Onde o player reaparece, em relação à origem (negativo = para cima)
@export var offset_respawn: Vector2 = Vector2(0, -20)

var ativado: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(corpo: Node2D) -> void:
	if ativado or not corpo.has_method("respawn"):
		return
	ativado = true
	GameManager.set_checkpoint(global_position + offset_respawn)
	modulate = Color(0.6, 1.0, 0.6)   # feedback provisório: fica esverdeado
