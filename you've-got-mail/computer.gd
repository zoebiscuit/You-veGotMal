extends TextureButton

@export var information_scene: PackedScene = preload("res://information.tscn")

func _on_pressed() -> void:
	if information_scene == null:
		return
	var root := get_tree().current_scene
	if root == null:
		return
	if root.get_node_or_null("information") != null:
		return
	var info_instance := information_scene.instantiate()
	if info_instance == null:
		return
	root.add_child(info_instance)
