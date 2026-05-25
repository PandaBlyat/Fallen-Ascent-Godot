extends MultiMeshInstance2D
##
## Batched shader activity effects. Workers and structures provide compact
## dictionaries; one MultiMesh draws all pulses/rings/sparks.
##

const FX_SHADER: Shader = preload("res://resources/shaders/activity_fx.gdshader")
const MAX_INSTANCES: int = 320
const FX_Z_INDEX: int = 120
const DUST_INSTANCE_COUNT: int = 36

@export var camera_path: NodePath
@export var workers_root_path: NodePath
@export var structure_manager_path: NodePath
@export var fog_of_war_path: NodePath

var _camera: Camera2D
var _workers_root: Node2D
var _structure_manager: StructureManager
var _fog: FogOfWar
var _material: ShaderMaterial
var _shader_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = FX_Z_INDEX
	_camera = get_node_or_null(camera_path) as Camera2D
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_fog = get_node_or_null(fog_of_war_path) as FogOfWar
	_setup_multimesh()


func _process(delta: float) -> void:
	_shader_time += delta
	if _material != null:
		_material.set_shader_parameter("time_seconds", _shader_time)
	_rebuild_instances()


func _setup_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX_INSTANCES
	mm.visible_instance_count = 0
	multimesh = mm
	_material = ShaderMaterial.new()
	_material.shader = FX_SHADER
	material = _material


func _rebuild_instances() -> void:
	if multimesh == null:
		return
	var index: int = 0
	index = _add_worker_sources(index)
	index = _add_structure_sources(index)
	index = _add_dust_sources(index)
	multimesh.visible_instance_count = index


func _add_worker_sources(index: int) -> int:
	if _workers_root == null:
		return index
	for child in _workers_root.get_children():
		if index >= MAX_INSTANCES:
			return index
		if not child.has_method("activity_fx"):
			continue
		var source: Dictionary = child.call("activity_fx") as Dictionary
		if source.is_empty():
			continue
		index = _add_source(index, source)
	return index


func _add_structure_sources(index: int) -> int:
	if _structure_manager == null or not _structure_manager.has_method("activity_fx_sources"):
		return index
	var sources: Array = _structure_manager.call("activity_fx_sources") as Array
	for raw_source in sources:
		if index >= MAX_INSTANCES:
			return index
		index = _add_source(index, raw_source as Dictionary)
	return index


func _add_dust_sources(index: int) -> int:
	if _camera == null or _fog == null:
		return index
	var viewport_size: Vector2 = get_viewport_rect().size
	var zoom: Vector2 = _camera.zoom
	var half_world := Vector2(viewport_size.x / zoom.x, viewport_size.y / zoom.y) * 0.5
	var lo := Vector2i(
		int(floor((_camera.global_position.x - half_world.x) / Chunk.TILE_PIXELS)) - 2,
		int(floor((_camera.global_position.y - half_world.y) / Chunk.TILE_PIXELS)) - 2,
	)
	var hi := Vector2i(
		int(ceil((_camera.global_position.x + half_world.x) / Chunk.TILE_PIXELS)) + 2,
		int(ceil((_camera.global_position.y + half_world.y) / Chunk.TILE_PIXELS)) + 2,
	)
	var size := Vector2i(maxi(1, hi.x - lo.x), maxi(1, hi.y - lo.y))
	var bucket: int = int(floor(_shader_time / 9.0))
	var cam_cell := Vector2i(
		int(floor(_camera.global_position.x / float(Chunk.TILE_PIXELS))),
		int(floor(_camera.global_position.y / float(Chunk.TILE_PIXELS))),
	)
	for i in range(DUST_INSTANCE_COUNT):
		if index >= MAX_INSTANCES:
			return index
		var hx: int = absi(hash([i, bucket, cam_cell.x / 6, "dust_x"]))
		var hy: int = absi(hash([i, bucket, cam_cell.y / 6, "dust_y"]))
		var grid := Vector2i(lo.x + hx % size.x, lo.y + hy % size.y)
		if not _fog.is_cell_visible(grid):
			continue
		var seed: float = float(absi(hash([grid.x, grid.y, i, "dust_seed"]))) / 2147483647.0
		var center: Vector2 = Chunk.grid_to_pixel_center(grid)
		multimesh.set_instance_transform_2d(index, Transform2D(0.0, center))
		multimesh.set_instance_color(index, Color(0.70, 0.74, 0.72, 0.22))
		multimesh.set_instance_custom_data(index, Color(0.9, 0.0, 0.32, seed))
		index += 1
	return index


func _add_source(index: int, source: Dictionary) -> int:
	var grid: Vector2i = source.get("grid", Pathfinder.UNREACHABLE) as Vector2i
	if grid == Pathfinder.UNREACHABLE:
		return index
	if _fog != null and not _fog.is_cell_visible(grid):
		return index
	var kind: int = int(source.get("kind", 0))
	var progress: float = clampf(float(source.get("progress", 0.0)), 0.0, 1.0)
	var intensity: float = clampf(float(source.get("intensity", 1.0)), 0.0, 1.0)
	var seed: float = float(absi(hash([grid.x, grid.y, kind]))) / 2147483647.0
	var center: Vector2 = Chunk.grid_to_pixel_center(grid)
	multimesh.set_instance_transform_2d(index, Transform2D(0.0, center))
	multimesh.set_instance_color(index, _color_for(kind))
	multimesh.set_instance_custom_data(index, Color(float(kind) / 10.0, progress, intensity, seed))
	return index + 1


static func _color_for(kind: int) -> Color:
	match kind:
		1:
			return Color(1.0, 0.48, 0.22, 0.95)
		2:
			return Color(1.0, 0.78, 0.30, 0.95)
		3:
			return Color(0.38, 0.92, 1.0, 0.90)
		4:
			return Color(0.48, 1.0, 0.68, 0.85)
		5:
			return Color(0.70, 0.62, 1.0, 0.78)
		_:
			return Color(0.85, 0.92, 1.0, 0.65)
