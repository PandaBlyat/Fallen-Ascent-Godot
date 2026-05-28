extends Control
## Dynamic pixel simulation background for the main menu.
## Rises and forms "Fallen Ascent" title for 4 seconds, then decays and erodes.

enum Phase { RISING, HOLDING, DECAYING }

@export var rise_duration: float = 4.0
@export var hold_duration: float = 4.0
@export var decay_duration: float = 6.0

var _current_phase: Phase = Phase.RISING
var _phase_elapsed: float = 0.0
var _simulation_data: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initialize_simulation()


func _process(delta: float) -> void:
	_phase_elapsed += delta
	_update_phase()
	queue_redraw()


func _draw() -> void:
	var progress: float = _get_phase_progress()
	_render_simulation(progress)


## Initialize simulation data structures. Call this once at startup.
func _initialize_simulation() -> void:
	_simulation_data.clear()
	# Placeholder for simulation state


## Update which phase we're in based on elapsed time.
func _update_phase() -> void:
	match _current_phase:
		Phase.RISING:
			if _phase_elapsed >= rise_duration:
				_current_phase = Phase.HOLDING
				_phase_elapsed = 0.0
		Phase.HOLDING:
			if _phase_elapsed >= hold_duration:
				_current_phase = Phase.DECAYING
				_phase_elapsed = 0.0
		Phase.DECAYING:
			# Keep decaying indefinitely
			pass


## Get 0..1 progress within the current phase.
func _get_phase_progress() -> float:
	match _current_phase:
		Phase.RISING:
			return clamp(_phase_elapsed / rise_duration, 0.0, 1.0)
		Phase.HOLDING:
			return 1.0
		Phase.DECAYING:
			return maxf(0.0, 1.0 - (_phase_elapsed / decay_duration))
	return 0.0


## Render the pixel simulation. progress is 0..1 within the current phase.
## When phase=RISING, progress goes 0→1 as pixels rise.
## When phase=HOLDING, progress=1 (full display).
## When phase=DECAYING, progress goes 1→0 as pixels decay/erode.
func _render_simulation(progress: float) -> void:
	# Placeholder: fill with a simple color gradient for now so the menu isn't broken
	var color: Color = Color.BLACK
	color.a = 0.8
	draw_rect(get_rect(), color)

	# TODO: Implement actual pixel simulation here.
	# The simulation should:
	# - During RISING: particles/pixels accumulate and form the "Fallen Ascent" title
	# - During HOLDING: stable display
	# - During DECAYING: pixels fall/erode away
	# Use progress (0..1) to interpolate between states.
