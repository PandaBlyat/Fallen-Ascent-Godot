extends Node
##
## Round-robin AI tick scheduler. Agents register on `_ready` and receive
## `ai_tick(delta_since_last_tick)` calls a fraction of the time, naturally
## staggered across frames so dozens of bots don't all decide things in the
## same frame.
##
## At AGENTS_PER_FRAME = 8 with 75 registered bots, each bot ticks every
## ~9 frames (~150 ms at 60 fps). With 200 bots, ~25 frames (~415 ms).
## Replaces the per-bot perception Timer nodes the ambient bots used to
## carry.
##

const AGENTS_PER_FRAME: int = 8

var _agents: Array = []
var _next_index: int = 0
## instance_id -> last tick msec, so each agent's `dt` reflects how long
## ago we last visited it (not the round-trip frame delta).
var _last_tick_msec: Dictionary = {}


func register(agent: Node) -> void:
	if agent == null:
		return
	var id: int = agent.get_instance_id()
	if _last_tick_msec.has(id):
		return
	_agents.append(agent)
	_last_tick_msec[id] = Time.get_ticks_msec()


func unregister(agent: Node) -> void:
	if agent == null:
		return
	var id: int = agent.get_instance_id()
	if not _last_tick_msec.has(id):
		return
	_last_tick_msec.erase(id)
	var idx: int = _agents.find(agent)
	if idx < 0:
		return
	_agents.remove_at(idx)
	if _next_index > idx:
		_next_index -= 1
	elif _next_index >= _agents.size():
		_next_index = 0


func agent_count() -> int:
	return _agents.size()


func _process(_delta: float) -> void:
	if _agents.is_empty():
		return
	var budget: int = mini(AGENTS_PER_FRAME, _agents.size())
	var now: int = Time.get_ticks_msec()
	for _i in range(budget):
		if _next_index >= _agents.size():
			_next_index = 0
		var agent: Node = _agents[_next_index]
		_next_index += 1
		if not is_instance_valid(agent):
			continue
		if not agent.has_method("ai_tick"):
			continue
		var id: int = agent.get_instance_id()
		var last: int = int(_last_tick_msec.get(id, now))
		var dt: float = float(now - last) / 1000.0
		_last_tick_msec[id] = now
		agent.call("ai_tick", dt)
