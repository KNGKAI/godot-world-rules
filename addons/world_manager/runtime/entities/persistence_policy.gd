class_name WorldPersistencePolicy
extends RefCounted
## Persistence policy enum. SCENE and GLOBAL are defined, not exposed.


enum Kind {
	NONE = 0,
	SESSION = 1,
	SAVE_GAME = 2,
}


static func validate(kind: int) -> Error:
	match kind:
		Kind.NONE, Kind.SESSION, Kind.SAVE_GAME:
			return OK
		_:
			return ERR_INVALID_PARAMETER
