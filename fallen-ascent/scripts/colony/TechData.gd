class_name TechData
extends Resource
##
## Typed node in the technology tree. Each TechData describes one unlock:
## what it shows in the panel, what it costs in Wisdom, what nodes must be
## bought before it becomes available, and which BuildBlueprint ids it
## unlocks once it is acquired.
##

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var wisdom_cost: int = 0
@export var prerequisites: Array[StringName] = []
@export var unlocked_build_ids: Array[int] = []
@export var grid_position: Vector2i = Vector2i.ZERO
@export var branch_label: String = ""


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_description: String = "",
	p_wisdom_cost: int = 0,
	p_prerequisites: Array[StringName] = [],
	p_unlocked_build_ids: Array[int] = [],
	p_grid_position: Vector2i = Vector2i.ZERO,
	p_branch_label: String = "",
) -> void:
	id = p_id
	display_name = p_display_name
	description = p_description
	wisdom_cost = p_wisdom_cost
	prerequisites = p_prerequisites
	unlocked_build_ids = p_unlocked_build_ids
	grid_position = p_grid_position
	branch_label = p_branch_label
