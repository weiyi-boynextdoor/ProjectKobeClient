extends Control

const CHAT_ITEM_OTHER_SCENE := preload("res://user_interface/chat_item_other.tscn")

@onready var network_manager = NetworkManager
@onready var text_user_input := $text_user_input
@onready var chat_container := $MarginContainer/ScrollContainer/chat_container


const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "connection"


func _ready() -> void:
	network_manager.connection_state_changed.connect(_on_connection_state_changed)
	network_manager.text_response_received.connect(_on_text_response_received)

	# Clean up placeholder chat items in the editor scene.
	for child in chat_container.get_children():
		child.queue_free()


func _on_btn_send_pressed() -> void:
	if network_manager.get_connection_state() == WebSocketPeer.STATE_OPEN:
		network_manager.send_chat_message(text_user_input.text)


func _on_connection_state_changed(state: int) -> void:
	match state:
		WebSocketPeer.STATE_CLOSED:
			pass


func _on_text_response_received(content: String) -> void:
	var chat_item: Control = CHAT_ITEM_OTHER_SCENE.instantiate()
	chat_container.add_child(chat_item)
	chat_item.set_text(content)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			# Release focus when clicking outside the active text input.
			if not focus_owner.get_global_rect().has_point(event.position):
				focus_owner.release_focus()
				DisplayServer.virtual_keyboard_hide()
