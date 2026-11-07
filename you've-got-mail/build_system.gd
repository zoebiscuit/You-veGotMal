extends Node2D

@export_node_path("TileMapLayer") var ground_path: NodePath = ^"../Ground"
@export_node_path("Button") var build_button_path: NodePath = ^"../BuildModeUI/BuildModeButton"

const BLOCK_COLOR := Color(1.0, 0.0, 0.0, 1.0)
const PREVIEW_COLOR := Color(1.0, 0.0, 0.0, 0.45)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const GRID_LINE_WIDTH := 2.0

var build_mode_enabled := false
var occupied_cells: Dictionary = {}
var hovered_cell: Vector2i
var has_hovered_cell := false
var used_rect: Rect2i

@onready var ground: TileMapLayer = get_node(ground_path) as TileMapLayer
@onready var build_button: Button = get_node_or_null(build_button_path) as Button

func _ready() -> void:
	if ground == null:
		push_error("BuildSystem: Ground TileMapLayer not found.")
		set_process(false)
		set_process_unhandled_input(false)
		return

	used_rect = ground.get_used_rect()
	z_index = max(ground.z_index + 1, 1)
	set_process(true)
	set_process_unhandled_input(true)
	_update_button_visuals()
	queue_redraw()

func _process(_delta: float) -> void:
	if not build_mode_enabled:
		if has_hovered_cell:
			has_hovered_cell = false
			queue_redraw()
		return

	var next_hovered := _get_cell_under_mouse()
	var next_has_hovered := _is_cell_buildable(next_hovered)
	if next_has_hovered != has_hovered_cell or (next_has_hovered and next_hovered != hovered_cell):
		has_hovered_cell = next_has_hovered
		hovered_cell = next_hovered
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not build_mode_enabled:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed \
	and not event.is_echo():
		if _is_mouse_over_control():
			return
		var cell := _get_cell_under_mouse()
		if not _is_cell_buildable(cell):
			return
		if occupied_cells.has(cell):
			return
		occupied_cells[cell] = true
		queue_redraw()
		get_viewport().set_input_as_handled()

func set_build_mode_enabled(enabled: bool) -> void:
	if build_mode_enabled == enabled:
		return
	build_mode_enabled = enabled
	if not build_mode_enabled:
		has_hovered_cell = false
	_update_button_visuals()
	queue_redraw()

func toggle_build_mode() -> void:
	set_build_mode_enabled(not build_mode_enabled)

func _update_button_visuals() -> void:
	if build_button == null:
		return
	build_button.text = "Exit Build Mode" if build_mode_enabled else "Build Mode"
	build_button.button_pressed = build_mode_enabled
	build_button.modulate = Color(1.0, 0.75, 0.75, 1.0) if build_mode_enabled else Color(1.0, 1.0, 1.0, 1.0)

func _draw() -> void:
	for cell in occupied_cells.keys():
		_draw_filled_cell(cell, BLOCK_COLOR)

	if build_mode_enabled:
		_draw_grid()
		if has_hovered_cell and not occupied_cells.has(hovered_cell):
			_draw_filled_cell(hovered_cell, PREVIEW_COLOR)

func _draw_grid() -> void:
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return

	var top_left := _cell_top_left(used_rect.position)
	var bottom_right_cell := used_rect.position + used_rect.size
	var bottom_right := _cell_top_left(bottom_right_cell)

	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x + 1):
		var start := _cell_top_left(Vector2i(x, used_rect.position.y))
		var finish := Vector2(start.x, bottom_right.y)
		draw_line(start, finish, GRID_COLOR, GRID_LINE_WIDTH)

	for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y + 1):
		var start := _cell_top_left(Vector2i(used_rect.position.x, y))
		var finish := Vector2(bottom_right.x, start.y)
		draw_line(start, finish, GRID_COLOR, GRID_LINE_WIDTH)

func _draw_filled_cell(cell: Vector2i, color: Color) -> void:
	var rect := Rect2(_cell_top_left(cell), _cell_size())
	draw_rect(rect, color, true)

func _get_cell_under_mouse() -> Vector2i:
	var mouse_world := get_global_mouse_position()
	var mouse_in_ground := ground.to_local(mouse_world)
	return ground.local_to_map(mouse_in_ground)

func _is_cell_buildable(cell: Vector2i) -> bool:
	return used_rect.has_point(cell)

func _cell_top_left(cell: Vector2i) -> Vector2:
	var local_center := ground.map_to_local(cell)
	var local_top_left := local_center - ground.tile_set.tile_size * 0.5
	return to_local(ground.to_global(local_top_left))

func _cell_size() -> Vector2:
	return Vector2(ground.tile_set.tile_size) * ground.global_scale

func _is_mouse_over_control() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var hovered := viewport.gui_get_hovered_control()
	return hovered != null
