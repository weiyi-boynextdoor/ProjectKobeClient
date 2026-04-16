extends Control

const CHAT_ITEM_OTHER_SCENE := preload("res://user_interface/chat_item_other.tscn")

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

@onready var audio_player := $audio_player
@onready var text_assistant_response := $text_assistant_response
@onready var text_user_input := $text_user_input
@onready var chat_container := $MarginContainer/ScrollContainer/chat_container


const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "connection"


func _ready() -> void:
	audio_stream_generator.mix_rate = audio_sample_rate
	audio_stream_generator.buffer_length = 0.2  # 200ms buffer to reduce stuttering
	audio_player.stream = audio_stream_generator
	network_manager.connection_state_changed.connect(_on_connection_state_changed)
	network_manager.text_response_received.connect(_on_text_response_received)
	network_manager.audio_started.connect(_on_audio_started)
	network_manager.audio_chunk_received.connect(_on_audio_chunk_received)
	network_manager.audio_finished.connect(_on_audio_finished)
	
	# clean up
	for child in chat_container.get_children():
		child.queue_free()


func _process(delta: float) -> void:
	_feed_audio()


func _begin_talk() -> void:
	# Cancel any pending end-talk timer from a previous playback.
	if end_talk_timer != null:
		if end_talk_timer.timeout.is_connected(_end_talk):
			end_talk_timer.timeout.disconnect(_end_talk)
		end_talk_timer = null
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()


func _end_talk() -> void:
	end_talk_timer = null
	audio_player.stop()


func _on_btn_send_pressed() -> void:
	if network_manager.get_connection_state() == WebSocketPeer.STATE_OPEN:
		network_manager.send_chat_message(text_user_input.text)


## Push buffered PCM data into AudioStreamGeneratorPlayback each frame.
func _feed_audio() -> void:
	if audio_playback == null:
		return
	var frames_available := audio_playback.get_frames_available()
	if frames_available <= 0:
		return
	# 16-bit PCM: 2 bytes per sample; one sample per frame for Mono.
	var bytes_per_frame := bytes_per_sample * audio_channels
	var max_bytes := frames_available * bytes_per_frame
	var available_bytes := audio_buf.size() - (audio_buf.size() % bytes_per_frame)
	var push_bytes := mini(max_bytes, available_bytes)
	var frames_to_push := push_bytes / bytes_per_frame
	for i in range(frames_to_push):
		var offset := i * bytes_per_frame
		# Decode 16-bit little-endian signed integer to normalized float.
		var raw := audio_buf[offset] | (audio_buf[offset + 1] << 8)
		if raw >= 32768:
			raw -= 65536
		var sample := float(raw) / 32768.0
		if audio_channels == 1:
			audio_playback.push_frame(Vector2(sample, sample))
		else:
			var raw_r := audio_buf[offset + 2] | (audio_buf[offset + 3] << 8)
			if raw_r >= 32768:
				raw_r -= 65536
			audio_playback.push_frame(Vector2(sample, float(raw_r) / 32768.0))
	if push_bytes > 0:
		audio_buf = audio_buf.slice(push_bytes)
	# Stop once all buffered data has been consumed.
	if audio_done and audio_buf.is_empty():
		audio_playback = null
		# Wait for the generator's internal buffer to drain before stopping.
		end_talk_timer = get_tree().create_timer(audio_stream_generator.buffer_length)
		end_talk_timer.timeout.connect(_end_talk)


func _on_connection_state_changed(state: int) -> void:
	match state:
		WebSocketPeer.STATE_CLOSED:
			pass


func _on_text_response_received(content: String) -> void:
	var chat_item: Control = CHAT_ITEM_OTHER_SCENE.instantiate()
	chat_container.add_child(chat_item)
	chat_item.set_text(content)


func _on_audio_started(sample_rate: int, channels: int) -> void:
	audio_sample_rate = sample_rate
	audio_channels = channels
	audio_stream_generator.mix_rate = audio_sample_rate
	audio_buf.clear()
	audio_done = false
	print("Audio sample rate set to ", audio_sample_rate)
	print("Audio channels set to ", audio_channels)
	print("audio start")


func _on_audio_chunk_received(data: PackedByteArray) -> void:
	audio_buf.append_array(data)
	if not is_talking:
		_begin_talk()
		is_talking = true


func _on_audio_finished() -> void:
	audio_done = true
	is_talking = false
	print("audio done, remaining bytes: ", audio_buf.size())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			# Release focus when clicking outside the active text input.
			if not focus_owner.get_global_rect().has_point(event.position):
				focus_owner.release_focus()
				DisplayServer.virtual_keyboard_hide()
