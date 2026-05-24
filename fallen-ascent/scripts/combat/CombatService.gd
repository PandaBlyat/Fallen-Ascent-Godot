extends RefCounted
##
## Static melee resolver. Called by HostileBot, NeutralBot, and Worker when they
## want to swing at a target. Range check, cooldown check, damage roll,
## knockback application, EventBus emit. Targets just need `current_grid()`,
## `take_damage(amount, attacker)`, and `apply_knockback(vec, stun_seconds)`.
##


static func try_attack(attacker: Node2D, target: Node, stats: CombatStats, now_seconds: float) -> bool:
	if attacker == null or target == null or stats == null:
		return false
	if not is_instance_valid(target):
		return false
	if not stats.is_alive():
		return false
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return false
	if stats.last_attack_at + stats.attack_cooldown_seconds > now_seconds:
		return false
	if not target.has_method("current_grid"):
		return false
	var attacker_grid: Vector2i = attacker.call("current_grid") as Vector2i
	var target_grid: Vector2i = target.call("current_grid") as Vector2i
	var cheb: int = maxi(absi(attacker_grid.x - target_grid.x), absi(attacker_grid.y - target_grid.y))
	if cheb > stats.attack_range_tiles:
		return false
	var damage: float = randf_range(stats.damage_min, stats.damage_max)
	if target.has_method("take_damage"):
		target.call("take_damage", damage, attacker)
	stats.last_attack_at = now_seconds
	if target is Node2D and target.has_method("apply_knockback"):
		var dir: Vector2 = (target as Node2D).position - attacker.position
		if dir.length() <= 0.0001:
			dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		var push: Vector2 = dir.normalized() * stats.knockback_px
		target.call("apply_knockback", push, stats.stun_on_hit_seconds)
	EventBus.combat_hit.emit(attacker, target, damage)
	return true
