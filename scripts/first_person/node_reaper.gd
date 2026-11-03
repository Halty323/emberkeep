class_name NodeReaper
extends RefCounted
## Frees large detached subtrees a little at a time. Deleting a whole room
## (hundreds of meshes, bodies and lights) in one go cost ~8 ms on a desktop
## and several times that on a phone, always on the frame a corridor hands
## over. Detaching is cheap, so the old room leaves the world at once and its
## nodes are then deleted, deepest first, within a small budget each frame.
const BUDGET_USEC := 1000
# Pre-order runs, one per reaped subtree; popped from the back, so a node is
# always deleted after every node below it.
var doomed: Array = []

func reap(node: Node) -> void:
	if node == null or not is_instance_valid(node): return
	if node.get_parent(): node.get_parent().remove_child(node)
	doomed.append(node)
	doomed.append_array(node.find_children("*", "", true, false))

func pending() -> int:
	return doomed.size()

func step(budget := BUDGET_USEC) -> void:
	var start := Time.get_ticks_usec()
	while not doomed.is_empty() and Time.get_ticks_usec() - start < budget:
		var node = doomed.pop_back()
		if is_instance_valid(node): node.free()

## Everything at once (leaving the game, or a test that needs it gone).
func flush() -> void:
	while not doomed.is_empty():
		var node = doomed.pop_back()
		if is_instance_valid(node): node.free()
