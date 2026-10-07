extends Area2D

@export var dano: int = 10
@export var mata_instantaneamente: bool = false
@export var pode_ser_bloqueado: bool = false


func _physics_process(_delta: float) -> void:
	for corpo in get_overlapping_bodies():
		_aplicar(corpo)


func _aplicar(corpo: Node2D) -> void:
	if mata_instantaneamente and corpo.has_method("kill"):
		corpo.kill()
	elif corpo.has_method("take_damage"):
		corpo.take_damage(dano, global_position, pode_ser_bloqueado)
