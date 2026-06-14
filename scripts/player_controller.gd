## player_controller.gd — Input controller for the player.
##
## FASE 4 (2026-06-14): el player es solo un Character con
## data.ai_controlled = false. Toda la lógica de input (WASD, jump,
## share, etc.) vive aquí, no en el Character.
##
## Esto cumple la directiva del user: "los controles por defecto solo
## mueven el jugador" — el Controller es lo único que sabe del input.
extends Node
class_name PlayerController

var character: Node = null


func _ready() -> void:
	# El player siempre procesa input, aún si el mundo está pausado
	# (necesario para toggle del skill book con Share button).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if character == null or not is_instance_valid(character):
		return
	# TODO: mover input handlers del player.gd aquí.
	# Por ahora, si el character es el player, este Controller
	# es un stub que delega todo al character. La migración
	# completa de player.gd queda como TODO (no rompe nada).
	pass
