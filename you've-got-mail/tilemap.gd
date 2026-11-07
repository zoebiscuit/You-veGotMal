extends TileMapLayer

@export_range(1, 1000) var map_width: int = 100
@export_range(1, 1000) var map_height: int = 100

@export var grass_source_id: int = 0
@export var grass_atlas_coords: Vector2i = Vector2i(0, 0)

func _ready() -> void:
	generate_map()

func generate_map() -> void:
	clear()

	var start_x := -(map_width / 2)
	var start_y := -(map_height / 2)

	for x in range(map_width):
		for y in range(map_height):
			set_cell(
				Vector2i(start_x + x, start_y + y),
				grass_source_id,
				grass_atlas_coords
			)
