extends Node2D

@export var IKController: Node2D
@export var IKTarget: Node2D

func _ready():
	pass

func _process(delta):
	IKController.Target = IKTarget.global_position
	pass
