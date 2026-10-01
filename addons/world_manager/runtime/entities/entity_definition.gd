class_name WorldEntityDefinition
extends Resource
## Authored descriptor for a spawnable entity. Register a copy through
## World.entities.register_archetype.
##
## Three fields, deliberately: every extra one is another thing the catalog has
## to copy correctly. `dimension` defaults to NONE so an unset definition is
## refused rather than silently treated as 2D.


@export var id: StringName = &""
@export var scene: PackedScene = null
@export var dimension: WorldSceneValidator.Dimension = WorldSceneValidator.Dimension.NONE
