class_name CombatStats
extends Resource
##
## Per-combatant runtime stats. Attached to Worker / NeutralBot / HostileBot.
## Tracks HP and the attacker's last swing time so CombatService can enforce
## cooldowns without each combatant rolling its own.
##

@export var max_hp: float = 80.0
@export var hp: float = 80.0
@export var damage_min: float = 4.0
@export var damage_max: float = 8.0
@export var attack_cooldown_seconds: float = 1.0
@export var attack_range_tiles: int = 1
@export var knockback_px: float = 6.0
@export var stun_on_hit_seconds: float = 0.15

var last_attack_at: float = -1000.0


func is_alive() -> bool:
	return hp > 0.0


func hp_ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)
