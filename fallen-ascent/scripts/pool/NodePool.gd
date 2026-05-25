class_name NodePool
extends RefCounted
##
## Generic node pool. Holds detached instances of a single Script subclass
## so callers can amortize node allocation cost during bursty churn
## (loose item drops, projectiles, future ambient bot promotions).
##
## Lifecycle:
##   var pool := NodePool.new(MY_SCRIPT)
##   var n := pool.acquire()        # new or recycled
##   parent.add_child(n)            # caller wires into tree
##   ...
##   pool.release(n)                # detaches and parks for reuse
##
## Concrete pools (e.g. ItemPool) subclass and override
## `_reset_for_release` to clear per-instance state before re-use.
##

var _script: Script
var _free: Array[Node] = []


func _init(script: Script) -> void:
	_script = script


## Returns a node ready to be added to the tree. Creates one if the free
## list is empty; otherwise reuses a parked instance.
func acquire() -> Node:
	if _free.is_empty():
		return _script.new() as Node
	return _free.pop_back()


## Detach `node` from its parent and park it on the free list. Calls
## `_reset_for_release` first so subclasses can clear instance state.
func release(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	_reset_for_release(node)
	_free.append(node)


## Override in subclasses to clear per-instance state.
func _reset_for_release(_node: Node) -> void:
	pass


func free_count() -> int:
	return _free.size()
