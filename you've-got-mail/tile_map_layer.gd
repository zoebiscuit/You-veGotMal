
extends TileMapLayer

@export var map_width: int = 100
@export var map_height: int = 100
@export var atlas_coords: Vector2i = Vector2i(0, 0)

func _ready() -> void:
	generate_map()

func generate_map() -> void:
	if tile_set == null or tile_set.get_source_count() == 0:
		push_error("No TileSet source configured!")
		return

	clear()

	var grass_id: int = tile_set.get_source_id(0)

	for x in range(map_width):
		for y in range(map_height):
			set_cell(
				Vector2i(x, y),
				grass_id,
				atlas_coords
			)
