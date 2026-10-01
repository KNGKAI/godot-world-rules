class_name CinematicShot
extends Resource
## One step in a sequence. The director calls enter, tick, and exit; shots do not touch the viewport themselves.

@export var duration := 0.0
@export var subtitle := ""

var _elapsed := 0.0
var _finished := false


## host is the CinematicDirector. The parameter stays untyped so this base class does not cycle with the director script.
func enter(_host) -> Error:
	_elapsed = 0.0
	_finished = false
	return OK


func tick(_host, delta: float) -> bool:
	if _finished:
		return true
	_elapsed += delta
	return _elapsed >= duration


func exit(_host) -> void:
	pass


## Camera-only shots expire the clock. A later shot overrides this to place the body.
func skip_to_end(_host) -> void:
	_finished = true


func requires_on_foot() -> bool:
	return false


## A vehicle beat refuses play unless the player is the driver. Camera shots leave this false.
func requires_vehicle() -> bool:
	return false


## Vehicle skip stays borrowed for one physics frame so the handbrake snapshot reaches the sedan.
func skip_holds_borrow() -> bool:
	return false


func ignores_duration_cap() -> bool:
	return false


## World passage stays borrowed until the travel terminal has waited one frame.
func defers_skip_restore() -> bool:
	return false
