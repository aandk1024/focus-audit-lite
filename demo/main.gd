extends Control

## The demo menu. It looks finished and it works perfectly with a mouse.
##
## Deliberately, nothing here calls grab_focus(). That is the single most
## common navigation bug in a Godot menu: with no initial focus the whole
## screen is inert until a mouse touches it, and on a controller there is no
## way to give it one. Uncomment the line below to see the dock's
## "Screen opens with nothing focused" finding disappear.

func _ready() -> void:
	# $Menu/Buttons/Start.grab_focus.call_deferred()
	pass
