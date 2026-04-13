extends Control

## Adjust these to match the server's audio format
var audio_sample_rate := 32000
var audio_channels := 1  # 1=Mono, 2=Stereo
var bytes_per_sample := 2  # 16-bit PCM

@onready var network_manager = NetworkManager

var audio_buf := PackedByteArray()
var audio_playback: AudioStreamGeneratorPlayback = null
var audio_done := false
var end_talk_timer: SceneTreeTimer = null
var is_talking := false

var audio_stream_generator: AudioStreamGenerator = AudioStreamGenerator.new()

@onready var btn_connect := $Top/btn_connect
@onready var text_connect_ip := $Top/text_connect_ip
@onready var text_connect_port := $Top/text_connect_port


const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "connection"


func _ready() -> void:
	audio_stream_generator.mix_rate = audio_sample_rate
	audio_stream_generator.buffer_length = 0.2  # 200ms buffer to reduce stuttering
	network_manager.connection_state_changed.connect(_on_connection_state_changed)
	_load_config()


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	text_connect_ip.text = config.get_value(CONFIG_SECTION, "ip", text_connect_ip.text)
	text_connect_port.text = config.get_value(CONFIG_SECTION, "port", text_connect_port.text)


func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "ip", text_connect_ip.text.strip_edges())
	config.set_value(CONFIG_SECTION, "port", text_connect_port.text.strip_edges())
	config.save(CONFIG_PATH)


func _on_btn_connect_pressed() -> void:
	match network_manager.get_connection_state():
		WebSocketPeer.STATE_CLOSED:
			_save_config()
			network_manager.connect_to_server(text_connect_ip.text, text_connect_port.text)
		WebSocketPeer.STATE_OPEN:
			network_manager.disconnect_from_server()


func _on_connection_state_changed(state: int) -> void:
	match state:
		WebSocketPeer.STATE_CONNECTING:
			btn_connect.text = "connecting..."
			btn_connect.disabled = true
		WebSocketPeer.STATE_OPEN:
			btn_connect.text = "disconnect"
			btn_connect.disabled = false
			get_tree().change_scene_to_file("res://chat_ui.tscn")
		WebSocketPeer.STATE_CLOSING:
			btn_connect.text = "disconnecting..."
			btn_connect.disabled = true
		WebSocketPeer.STATE_CLOSED:
			btn_connect.text = "connect"
			btn_connect.disabled = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			# Release focus when clicking outside the active text input.
			if not focus_owner.get_global_rect().has_point(event.position):
				focus_owner.release_focus()
				DisplayServer.virtual_keyboard_hide()
