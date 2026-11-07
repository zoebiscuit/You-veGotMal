extends Node2D

signal structure_added(structure: Node)
signal structure_removed(structure: Node)

@export_node_path("TileMapLayer") var ground_path: NodePath = ^"../Ground"
@export_node_path("Button") var build_button_path: NodePath = ^"../BuildModeUI/BuildModeButton"
@export_node_path("Panel") var selection_panel_path: NodePath = ^"../BuildModeUI/SelectionPanel"
@export_node_path("Button") var firewall_button_path: NodePath = ^"../BuildModeUI/SelectionPanel/PanelMargin/PanelVBox/BuildingSelector/FirewallButton"
@export_node_path("Button") var antivirus_button_path: NodePath = ^"../BuildModeUI/SelectionPanel/PanelMargin/PanelVBox/BuildingSelector/AntivirusButton"
@export var block_max_health: float = 100.0
@export var antivirus_scene: PackedScene = preload("res://Buildings/antivirus.tscn")

const BLOCK_COLOR := Color(1.0, 0.0, 0.0, 1.0)
const ANTIVIRUS_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const GRID_LINE_WIDTH := 2.0

const BUILDING_FIREWALL := "firewall"
const BUILDING_ANTIVIRUS := "antivirus"

var build_mode_enabled := false
var occupied_cells: Dictionary = {}
var structure_data_by_cell: Dictionary = {}
var hovered_cell: Vector2i
var has_hovered_cell := false
var used_rect: Rect2i
var reserved_cells: Dictionary = {}
var block_structures: Dictionary = {}
var selected_building_type: String = BUILDING_FIREWALL

@onready var ground: TileMapLayer = get_node(ground_path) as TileMapLayer
@onready var build_button: Button = get_node_or_null(build_button_path) as Button
@onready var selection_panel: Panel = get_node_or_null(selection_panel_path) as Panel
@onready var firewall_button: Button = get_node_or_null(firewall_button_path) as Button
@onready var antivirus_button: Button = get_node_or_null(antivirus_button_path) as Button

func _ready() -> void:
	if ground == null:
		push_error("BuildSystem: Ground TileMapLayer not found.")
		set_process(false)
		set_process_unhandled_input(false)
		return

	used_rect = ground.get_used_rect()
	z_index = max(ground.z_index + 1, 1)
	_refresh_reserved_cells()
	set_process(true)
	set_process_unhandled_input(true)
	if firewall_button != null:
		firewall_button.pressed.connect(_on_firewall_selected)
	if antivirus_button != null:
		antivirus_button.pressed.connect(_on_antivirus_selected)
	_update_button_visuals()
	queue_redraw()

func _process(_delta: float) -> void:
	_refresh_reserved_cells()
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
		_create_structure(cell, selected_building_type)
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

func get_structure_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for node in block_structures.values():
		if node != null and is_instance_valid(node):
			result.append(node)
	return result

func has_occupied_cell(cell: Vector2i) -> bool:
	return occupied_cells.has(cell)

func get_cell_world_center(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))

func get_cell_size_world() -> Vector2:
	return Vector2(ground.tile_set.tile_size) * ground.global_scale

func get_structure_type(cell: Vector2i) -> String:
	return str(structure_data_by_cell.get(cell, {}).get("type", BUILDING_FIREWALL))

func _create_structure(cell: Vector2i, building_type: String) -> void:
	match building_type:
		BUILDING_ANTIVIRUS:
			_create_antivirus(cell)
		_:
			_create_firewall(cell)

func _create_firewall(cell: Vector2i) -> void:
	var block := StaticBody2D.new()
	block.name = "Firewall_%s_%s" % [cell.x, cell.y]
	block.set_meta("cell", cell)
	block.set_meta("max_health", block_max_health)
	block.set_meta("current_health", block_max_health)
	block.add_to_group("structure_targets")
	block.add_to_group("player_blocks")
	block.add_to_group("firewall_blocks")
	block.collision_layer = 2
	block.collision_mask = 1
	add_child(block)

	var visual := Polygon2D.new()
	var size: Vector2 = get_cell_size_world()
	var half: Vector2 = size * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	visual.color = BLOCK_COLOR
	block.add_child(visual)

	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	collision.shape = rect
	block.add_child(collision)

	var health_bar := ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size = Vector2(max(size.x, 24.0), 8.0)
	health_bar.size = health_bar.custom_minimum_size
	health_bar.position = Vector2(-health_bar.custom_minimum_size.x * 0.5, -half.y - 14.0)
	health_bar.show_percentage = false
	block.add_child(health_bar)

	block.position = to_local(get_cell_world_center(cell))
	block.set_script(_create_firewall_script())
	block.call("setup_block", self, cell)
	_register_structure(cell, block, BUILDING_FIREWALL)

func _create_antivirus(cell: Vector2i) -> void:
	if antivirus_scene == null:
		return
	var tower := antivirus_scene.instantiate()
	if tower == null:
		return
	add_child(tower)
	tower.name = "Antivirus_%s_%s" % [cell.x, cell.y]
	tower.position = to_local(get_cell_world_center(cell))
	if tower.has_method("setup_block"):
		tower.setup_block(self, cell, get_cell_size_world())
	_register_structure(cell, tower, BUILDING_ANTIVIRUS)

func _register_structure(cell: Vector2i, structure: Node, building_type: String) -> void:
	occupied_cells[cell] = true
	block_structures[cell] = structure
	structure_data_by_cell[cell] = {"type": building_type}
	emit_signal("structure_added", structure)

func destroy_block_at_cell(cell: Vector2i) -> void:
	var block: Node = block_structures.get(cell, null)
	if block == null or not is_instance_valid(block):
		occupied_cells.erase(cell)
		block_structures.erase(cell)
		structure_data_by_cell.erase(cell)
		queue_redraw()
		return
	emit_signal("structure_removed", block)
	occupied_cells.erase(cell)
	block_structures.erase(cell)
	structure_data_by_cell.erase(cell)
	block.queue_free()
	queue_redraw()

func _create_firewall_script() -> Script:
	var script := GDScript.new()
	script.source_code = "extends StaticBody2D\nvar build_system: Node\nvar cell: Vector2i\nvar destroyed := false\nfunc setup_block(owner_build_system: Node, owner_cell: Vector2i) -> void:\n\tbuild_system = owner_build_system\n\tcell = owner_cell\n\t_update_health_bar()\nfunc take_damage(amount: float) -> void:\n\tif destroyed or amount <= 0.0:\n\t\treturn\n\tvar current_health: float = float(get_meta(\"current_health\", 0.0)) - amount\n\tset_meta(\"current_health\", max(current_health, 0.0))\n\t_update_health_bar()\n\tif current_health <= 0.0:\n\t\tdestroyed = true\n\t\tif build_system != null and is_instance_valid(build_system):\n\t\t\tbuild_system.destroy_block_at_cell(cell)\nfunc is_structure_alive() -> bool:\n\treturn not destroyed and float(get_meta(\"current_health\", 0.0)) > 0.0\nfunc is_destroyed() -> bool:\n\treturn destroyed or float(get_meta(\"current_health\", 0.0)) <= 0.0\nfunc get_anchor_cell() -> Vector2i:\n\treturn cell\nfunc get_occupied_cells() -> Array[Vector2i]:\n\treturn [cell]\nfunc get_cell_world_center(query_cell: Vector2i = cell) -> Vector2:\n\tif build_system != null and is_instance_valid(build_system):\n\t\treturn build_system.get_cell_world_center(query_cell)\n\treturn global_position\nfunc get_closest_attack_point(from_world: Vector2) -> Vector2:\n\tif build_system != null and is_instance_valid(build_system):\n\t\tvar size: Vector2 = build_system.get_cell_size_world()\n\t\tvar half: Vector2 = size * 0.5\n\t\treturn Vector2(\n\t\t\tclampf(from_world.x, global_position.x - half.x, global_position.x + half.x),\n\t\t\tclampf(from_world.y, global_position.y - half.y, global_position.y + half.y)\n\t\t)\n\treturn global_position\nfunc get_attack_radius() -> float:\n\tif build_system != null and is_instance_valid(build_system):\n\t\tvar size: Vector2 = build_system.get_cell_size_world()\n\t\treturn max(size.x, size.y) * 0.5\n\treturn 16.0\nfunc _update_health_bar() -> void:\n\tvar bar := get_node_or_null(\"HealthBar\") as ProgressBar\n\tif bar == null:\n\t\treturn\n\tvar max_health := float(get_meta(\"max_health\", 1.0))\n\tvar current_health := float(get_meta(\"current_health\", max_health))\n\tbar.min_value = 0.0\n\tbar.max_value = max_health\n\tbar.value = current_health\n\tbar.visible = current_health < max_health\n\tvar ratio := current_health / max_health if max_health > 0.0 else 0.0\n\tif ratio > 0.6:\n\t\tbar.modulate = Color(0.2, 0.9, 0.2, 1.0)\n\telif ratio > 0.3:\n\t\tbar.modulate = Color(1.0, 0.85, 0.2, 1.0)\n\telse:\n\t\tbar.modulate = Color(1.0, 0.2, 0.2, 1.0)\n"
	script.reload()
	return script

func _update_button_visuals() -> void:
	if build_button != null:
		build_button.text = "Exit Build Mode" if build_mode_enabled else "Build Mode"
		build_button.button_pressed = build_mode_enabled
		build_button.modulate = Color(1.0, 0.75, 0.75, 1.0) if build_mode_enabled else Color(1.0, 1.0, 1.0, 1.0)
	if selection_panel != null:
		selection_panel.visible = build_mode_enabled
	if firewall_button != null:
		firewall_button.modulate = Color(1.0, 0.35, 0.35, 1.0) if selected_building_type == BUILDING_FIREWALL else Color(1.0, 0.85, 0.85, 1.0)
		firewall_button.text = "[SELECTED] Firewall" if selected_building_type == BUILDING_FIREWALL else "Firewall"
	if antivirus_button != null:
		antivirus_button.modulate = Color(0.75, 0.9, 1.0, 1.0) if selected_building_type == BUILDING_ANTIVIRUS else Color(0.95, 0.95, 0.95, 1.0)
		antivirus_button.text = "[SELECTED] Antivirus" if selected_building_type == BUILDING_ANTIVIRUS else "Antivirus"

func _draw() -> void:
	if build_mode_enabled:
		_draw_grid()
		if has_hovered_cell and not occupied_cells.has(hovered_cell):
			_draw_filled_cell(hovered_cell, _get_preview_color())

func _draw_grid() -> void:
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return

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

func _get_preview_color() -> Color:
	return Color(1.0, 1.0, 1.0, 0.7) if selected_building_type == BUILDING_ANTIVIRUS else Color(1.0, 0.0, 0.0, 0.5)

func _get_cell_under_mouse() -> Vector2i:
	var mouse_world := get_global_mouse_position()
	var mouse_in_ground := ground.to_local(mouse_world)
	return ground.local_to_map(mouse_in_ground)

func _is_cell_buildable(cell: Vector2i) -> bool:
	return used_rect.has_point(cell) and not reserved_cells.has(cell)

func _refresh_reserved_cells() -> void:
	reserved_cells.clear()
	var level := get_parent()
	if level != null and level.has_method("get_server_occupied_cells"):
		for cell in level.get_server_occupied_cells():
			reserved_cells[cell] = true

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

func _on_firewall_selected() -> void:
	selected_building_type = BUILDING_FIREWALL
	_update_button_visuals()
	queue_redraw()

func _on_antivirus_selected() -> void:
	selected_building_type = BUILDING_ANTIVIRUS
	_update_button_visuals()
	queue_redraw()
