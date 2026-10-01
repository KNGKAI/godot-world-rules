class_name WorldEntityOrigin
extends RefCounted
## Whether a record describes an entity authored into a scene or one spawned at
## runtime. Not the same axis as persistence policy: an authored entity and a
## spawned one can both be SAVE_GAME, and the difference is only in who has to
## produce the actor when the record is restored.
##
## AUTHORED is zero so a default-constructed EntityRecord keeps behaving exactly
## as it did before the field existed.


enum Kind {
	AUTHORED = 0,
	DYNAMIC = 1,
}


## Modelled on WorldPersistencePolicy rather than WorldEntityParent. The latter
## has no validator, which is why its three-way check is open-coded in three
## places; adding a second enum without one would repeat that immediately.
static func validate(kind: int) -> Error:
	match kind:
		Kind.AUTHORED, Kind.DYNAMIC:
			return OK
		_:
			return ERR_INVALID_PARAMETER
