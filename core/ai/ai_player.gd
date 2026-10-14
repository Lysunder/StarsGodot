class_name AiPlayer
extends RefCounted
## A computer player's brain (spec S22): each turn `play` reads the context and gives the turn's
## orders through it. This base brain gives none (the "idle" brain); the others extend it.


func play(_ctx: AiContext) -> void:
	pass
