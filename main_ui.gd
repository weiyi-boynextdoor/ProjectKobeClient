extends Control

const CONNECT_TIMEOUT := 5.0
## Adjust these to match the server's audio format
var audio_sample_rate := 32000
var audio_channels := 1  # 1=Mono, 2=Stereo
var bytes_per_sample := 2  # 16-bit PCM

var websocket := WebSocketPeer.new()
var ws_state := WebSocketPeer.STATE_CLOSED
var connect_timer := 0.0

var audio_buf: = PackedByteArray()
var audio_playback: AudioStreamGeneratorPlayback = null
var audio_done: = false
var end_talk_timer: SceneTreeTimer = null
var is_talking: = false

var audio_stream_generator: AudioStreamGenerator = AudioStreamGenerator.new()

@onready var btn_connect := $Top/btn_connect
@onready var audio_player := $audio_player
@onready var img_kobe_dynamic := $img_kobe_dynamic
@onready var img_kobe_static := $img_kobe_static
@onready var text_assistant_response := $text_assistant_response
@onready var text_user_input := $text_user_input
@onready var text_connect_ip := $Top/text_connect_ip
@onready var text_connect_port := $Top/text_connect_port


const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "connection"


func _ready() -> void:
	audio_stream_generator.mix_rate = audio_sample_rate
	audio_stream_generator.buffer_length = 0.2  # 200ms buffer to reduce stuttering
	audio_player.stream = audio_stream_generator
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


func _process(delta: float) -> void:
	_feed_audio()
	websocket.poll()
	ws_state = websocket.get_ready_state()
	match ws_state:
		WebSocketPeer.STATE_CONNECTING:
			connect_timer += delta
			if connect_timer >= CONNECT_TIMEOUT:
				websocket.close()
				connect_timer = 0.0
			btn_connect.text = "connecting..."
			btn_connect.disabled = true
		WebSocketPeer.STATE_OPEN:
			btn_connect.text = "disconnect"
			btn_connect.disabled = false
			while websocket.get_available_packet_count() > 0:
				_process_websocket_message()
		WebSocketPeer.STATE_CLOSING:
			btn_connect.text = "disconnecting..."
			btn_connect.disabled = true
		WebSocketPeer.STATE_CLOSED:
			connect_timer = 0.0
			btn_connect.text = "connect"
			btn_connect.disabled = false


func _process_websocket_message() -> void:
	var packet := websocket.get_packet()
	var text := packet.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)

	if not data is Dictionary:
		return

	var dict := data as Dictionary
	var event: String = dict.get("event", "")

	if event == "text_response":
		text_assistant_response.text = "Kobe: " + dict.get("content")
	elif event == "audio_start":
		if dict.has("sample_rate"):
			audio_sample_rate = int(dict["sample_rate"])
			audio_stream_generator.mix_rate = audio_sample_rate
			print("Audio sample rate set to ", audio_sample_rate)
		if dict.has("channels"):
			audio_channels = int(dict["channels"])
			print("Audio channels set to ", audio_channels)
		audio_buf.clear()
		audio_done = false
		print("audio start")
	elif event == "audio_chunk":
		var encoded: String = dict.get("data", "")
		if not encoded.is_empty():
			var byte_count := encoded.length() / 2
			var decoded := PackedByteArray()
			decoded.resize(byte_count)
			for i in byte_count:
				decoded[i] = encoded.substr(i * 2, 2).hex_to_int()
			audio_buf.append_array(decoded)
			if not is_talking:
				_begin_talk()
				is_talking = true
	elif event == "audio_done":
		audio_done = true
		is_talking = false
		print("audio done, remaining bytes: ", audio_buf.size())


func _begin_talk() -> void:
	# Cancel any pending end-talk timer from a previous playback
	if end_talk_timer != null:
		if end_talk_timer.timeout.is_connected(_end_talk):
			end_talk_timer.timeout.disconnect(_end_talk)
		end_talk_timer = null
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()
	img_kobe_dynamic.visible = true
	(img_kobe_dynamic.texture as AnimatedTexture).current_frame = 0
	img_kobe_static.visible = false


func _end_talk() -> void:
	end_talk_timer = null
	audio_player.stop()
	img_kobe_dynamic.visible = false
	img_kobe_static.visible = true


func _on_btn_send_pressed() -> void:
	if ws_state == WebSocketPeer.STATE_OPEN:
		var input_text: String = text_user_input.text.strip_edges()
		var message := {"action": "chat", "message": input_text}
		websocket.send_text(JSON.stringify(message))


## Push buffered PCM data into AudioStreamGeneratorPlayback each frame
func _feed_audio() -> void:
	if audio_playback == null:
		return
	var frames_available := audio_playback.get_frames_available()
	if frames_available <= 0:
		return
	# 16-bit PCM: 2 bytes per sample; one sample per frame for Mono
	var bytes_per_frame := bytes_per_sample * audio_channels
	var max_bytes := frames_available * bytes_per_frame
	var available_bytes := audio_buf.size() - (audio_buf.size() % bytes_per_frame)
	var push_bytes := mini(max_bytes, available_bytes)
	var frames_to_push := push_bytes / bytes_per_frame
	for i in range(frames_to_push):
		var offset := i * bytes_per_frame
		# Decode 16-bit little-endian signed integer to normalized float
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
	# Stop once all buffered data has been consumed
	if audio_done and audio_buf.is_empty():
		audio_playback = null
		# Wait for the generator's internal buffer to drain before stopping
		end_talk_timer = get_tree().create_timer(audio_stream_generator.buffer_length)
		end_talk_timer.timeout.connect(_end_talk)


func _on_btn_connect_pressed() -> void:
	match websocket.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			_save_config()
			var url: String = "ws://{0}:{1}/ws".format([text_connect_ip.text.strip_edges(), text_connect_port.text.strip_edges()])
			connect_timer = 0.0
			websocket.connect_to_url(url)
		WebSocketPeer.STATE_OPEN:
			websocket.close()

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			# 检查点击位置是否在输入框之外
			if not focus_owner.get_global_rect().has_point(event.position):
				focus_owner.release_focus()
				DisplayServer.virtual_keyboard_hide()
