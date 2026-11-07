extends TextureButton

@export var information_scene: PackedScene = preload("res://information.tscn")

func _on_pressed() -> void:
	if information_scene == null:
		return
	var root := _get_scene_root()
	if root == null:
		return
	if root.get_node_or_null("information") != null:
		return
	var info_instance := information_scene.instantiate()
	if info_instance == null:
		return
	root.add_child(info_instance)

func _get_scene_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	var root := tree.root
	if root == null or root.get_child_count() <= 0:
		return null
	return root.get_child(root.get_child_count() - 1)
