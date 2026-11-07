extends CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		if child is Node:
			child.process_mode = Node.PROCESS_MODE_ALWAYS
	var button := get_node_or_null("Accept") as Button
	if button != null and not button.pressed.is_connected(_on_accept_pressed):
		button.pressed.connect(_on_accept_pressed)
	Global.gameplay_paused = true

func _on_accept_pressed() -> void:
	Global.gameplay_paused = false
	queue_free()
