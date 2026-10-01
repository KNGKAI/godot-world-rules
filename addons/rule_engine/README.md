# Godot Rule Engine addon

A deterministic Event-Condition-Action rules addon for Godot 4.7.1+.

## Installation

Copy this entire `rule_engine` directory to `res://addons/rule_engine/`, then
enable **Rule Engine** in **Project > Project Settings > Plugins**. Enabling the
plugin adds an optional `Rules` autoload; disabling it removes that autoload
only when it still points to this addon's runtime facade.

You may instead own the runtime directly:

```gdscript
var rule_engine := RERuleEngine.new()

func _ready() -> void:
	rule_engine.load_book(load("res://rules/game_rules.tres"))
	rule_engine.emit_event(&"game_started")
```

Retain the `RERuleEngine` in a member variable. Its blackboard and enabled
overrides are per-engine, in-memory state; your game is responsible for any
save-game persistence. Values written through built-in actions are copied,
including nested containers, packed arrays, and Resources, so authored data is
not used as mutable runtime state.

## Authoring

The plugin adds a **Rules** main-screen workspace that discovers indexed
`RERuleBook` `.tres` and `.res` resources throughout the project, groups them
by directory, and filters Rules by ID, event, or tag. It opens without a main
scene dependency.

Create external `RERule` `.tres` resources and reference them from an
`RERuleBook`. The workspace's Create and Duplicate actions save the new Rule
asset first, then link it to the chosen book. **Unlink** removes only that
reference: it never deletes the `.tres` file. These operations, plus Rule
fields, condition-tree edits, and action ordering, use Godot undo/redo. Undoing
create, duplicate, or unlink changes the book link but keeps the external
asset, and redo reuses that same asset.

An empty rule event makes it queryable through `check()`; a non-empty event
makes it reactive through `emit_event()`. Reactive rules require at least one
action.

Built-in conditions are `REAllCondition`, `REAnyCondition`, `RENotCondition`,
`RECompareCondition`, and `REExistsCondition`. Built-in actions emit another
rule event or set a blackboard value. Use NOT + blackboard EXISTS followed by a
set action for one-time behavior.

`RECompareCondition` supports equal, not-equal, ordered comparisons,
`CONTAINS`, and `NOT_CONTAINS`. Text uses substring membership; Arrays and
packed arrays use element membership; Dictionaries use key membership. Invalid
operand combinations remain invalid, including under `NOT_CONTAINS`.

ID, event, and tags fields commit with Enter or focus loss. The workspace
validation panel and CLI share one validator: empty configured built-in emit
events and blackboard keys are errors, and `potential_event_cycle` warnings
identify reactive event cycles without failing warning-only CI input.

Validate authored books in automation:

```powershell
godot --headless --path . --script addons/rule_engine/tools/validate_rules.gd -- --book=res://rules/game_rules.tres
```

Configure `RERuleEngine.max_chain_depth` (default `64`, minimum `1`) to cap a
root event chain. External `emit_event()` calls start at depth `0`; events
emitted while dispatching are one level deeper. When dequeuing an event beyond
the limit, the engine clears that dispatch queue and emits
`dispatch_failed(&"chain_depth", ...)`; a later root event can dispatch
normally.

Custom GDScript conditions and actions require `@tool`, a global `class_name`,
and constructors callable with default arguments so the Inspector can create
them. After adding or changing a tool script, reopen the project if Godot's
global class cache has not refreshed it.

For Godot 4.7 exports, select **Text** as the GDScript export mode when relying
on the addon's export callback, or add `addons/rule_engine/editor/*` to the
preset's exclude filter. Godot issue
[#93487](https://github.com/godotengine/godot/issues/93487) tracks cases where
`_export_file()` is not called for GDScript files in binary-token exports.

See the repository documentation for the full runtime contract and extension
examples. Licensed under the [MIT License](LICENSE).
