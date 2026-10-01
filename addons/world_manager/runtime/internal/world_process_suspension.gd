class_name WorldProcessSuspension
extends RefCounted
## Records a node's process_mode and disables it, so a world root that is being
## staged or retained mid-transaction cannot run gameplay. Restores the recorded
## value, never a default, and never touches a node it did not record.
##
## This is deliberately not an input lock. It applies only to the managed world
## roots the addon owns, and never to SceneTree.paused or a project's
## controller; README D18 remains open and Phase 12 still owns that question.
##
## Instance ids rather than Node references: a root freed mid-transaction is the
## normal case (a successful travel frees the outgoing one), and an id turns
## that into a skip instead of a dangling reference.


var _order: Array[int] = []
var _modes: Dictionary = {}


## First call wins. A second suspend of the same node would otherwise record
## PROCESS_MODE_DISABLED as its "previous" value and restore it to that.
func suspend(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _modes.has(id):
		return
	_modes[id] = int(node.process_mode)
	_order.append(id)
	node.process_mode = Node.PROCESS_MODE_DISABLED


## Drop an entry without restoring it, for a node this ledger no longer owns.
func forget(node: Node) -> void:
	if node == null:
		return
	var id := node.get_instance_id()
	if not _modes.has(id):
		return
	_modes.erase(id)
	_order.erase(id)


## Reverse of the order they were suspended in, then empty. Clearing is what
## makes a second call a no-op, so every failure path may call this without
## checking whether an earlier one already did.
func restore_all() -> void:
	for index in range(_order.size() - 1, -1, -1):
		var id: int = _order[index]
		var node := instance_from_id(id) as Node
		if node != null and is_instance_valid(node):
			node.process_mode = int(_modes[id]) as Node.ProcessMode
	_order.clear()
	_modes.clear()


func is_empty() -> bool:
	return _order.is_empty()


## Test seam: the mode recorded for a node, or -1 when it is not recorded.
func recorded_mode(node: Node) -> int:
	if node == null:
		return -1
	var id := node.get_instance_id()
	if not _modes.has(id):
		return -1
	return int(_modes[id])
