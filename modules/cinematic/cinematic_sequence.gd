class_name CinematicSequence
extends Resource
## Ordered shots for one play(). Seen-flags live on the example coordinator, not here.

@export var id: StringName
@export var shots: Array[CinematicShot] = []
