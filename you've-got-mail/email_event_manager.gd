extends Node

signal email_event_finished

@export_node_path("Button") var start_wave_button_path: NodePath = ^"../BuildModeUI/StartWaveButton"
@export var mail_scene_paths: Array[String] = [
	"res://mail-1.tscn",
	"res://mail-2.tscn",
	"res://mail-3.tscn"
]

@onready var start_wave_button: Button = get_node_or_null(start_wave_button_path)

var _active_mail: CanvasLayer = null
var _awaiting_response := false
var _correct_answers := {
	"res://mail-1.tscn": "decline",
	"res://mail-2.tscn": "decline",
	"res://mail-3.tscn": "accept"
}

func show_random_email_event() -> void:
	if _awaiting_response or _active_mail != null:
		return
	if mail_scene_paths.is_empty():
		emit_signal("email_event_finished")
		return
	if start_wave_button != null:
		start_wave_button.visible = false
	Global.gameplay_paused = true
	var scene_path: String = mail_scene_paths[randi() % mail_scene_paths.size()]
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		Global.gameplay_paused = false
		emit_signal("email_event_finished")
		return
	var instance := packed.instantiate()
	if instance == null:
		Global.gameplay_paused = false
		emit_signal("email_event_finished")
		return
	_active_mail = CanvasLayer.new()
	_active_mail.name = "ActiveEmailEvent"
	_active_mail.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_active_mail)
	_active_mail.add_child(instance)
	if instance is Node:
		(instance as Node).process_mode = Node.PROCESS_MODE_ALWAYS
		for child in (instance as Node).get_children():
			if child is Node:
				child.process_mode = Node.PROCESS_MODE_ALWAYS
	_awaiting_response = true
	_wire_mail_buttons(instance, scene_path)

func _wire_mail_buttons(instance: Node, scene_path: String) -> void:
	var accept_button := instance.get_node_or_null("Accept") as Button
	var decline_button := instance.get_node_or_null("Decline") as Button
	if accept_button != null:
		accept_button.process_mode = Node.PROCESS_MODE_ALWAYS
		accept_button.pressed.connect(func() -> void:
			_resolve_email_choice(scene_path, "accept")
		, CONNECT_ONE_SHOT)
	if decline_button != null:
		decline_button.process_mode = Node.PROCESS_MODE_ALWAYS
		decline_button.pressed.connect(func() -> void:
			_resolve_email_choice(scene_path, "decline")
		, CONNECT_ONE_SHOT)

func _resolve_email_choice(scene_path: String, choice: String) -> void:
	if not _awaiting_response:
		return
	_awaiting_response = false
	var correct_choice: String = str(_correct_answers.get(scene_path, "decline"))
	var current_crypto: float = float(Global.GlobalCrypto)
	if choice == correct_choice:
		Global.GlobalCrypto = int(round(current_crypto * 1.5))
	else:
		Global.GlobalCrypto = max(0, int(round(current_crypto * 0.5)))
	Global.gameplay_paused = false
	if _active_mail != null and is_instance_valid(_active_mail):
		_active_mail.queue_free()
	_active_mail = null
	emit_signal("email_event_finished")
