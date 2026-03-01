extends Control

const CONNECT_TIMEOUT := 5.0
## Adjust these to match the server's audio format
var m_audio_sample_rate := 32000
var m_audio_channels := 1  # 1=Mono, 2=Stereo
var m_bytes_per_sample := 2  # 16-bit PCM

var m_websocket := WebSocketPeer.new()
var m_ws_state := WebSocketPeer.STATE_CLOSED
var m_connect_timer := 0.0
var m_session_id: String = ""

var m_audio_buf := PackedByteArray()
var m_audio_playback: AudioStreamGeneratorPlayback = null
var m_audio_done := false
var m_end_talk_timer: SceneTreeTimer = null
var m_is_talking := false

var m_audio_stream_generator := AudioStreamGenerator.new()

func _ready() -> void:
	m_audio_stream_generator.mix_rate = m_audio_sample_rate
	m_audio_stream_generator.buffer_length = 0.2  # 200ms buffer to reduce stuttering
	$audio_player.stream = m_audio_stream_generator


func _process(delta: float) -> void:
	_feed_audio()
	m_websocket.poll()
	var last_ws_state := m_ws_state
	m_ws_state = m_websocket.get_ready_state()
	match m_ws_state:
		WebSocketPeer.STATE_CONNECTING:
			m_connect_timer += delta
			if m_connect_timer >= CONNECT_TIMEOUT:
				m_websocket.close()
				m_connect_timer = 0.0
			$btn_connect.text = "connecting..."
			$btn_connect.disabled = true
		WebSocketPeer.STATE_OPEN:
			$btn_connect.text = "disconnect"
			$btn_connect.disabled = false
			if last_ws_state != WebSocketPeer.STATE_OPEN:
				# create session
				print("websocket connected, creating session...")
				m_websocket.send_text(JSON.stringify({"action": "create_session"}))
			while m_websocket.get_available_packet_count() > 0:
				process_websocket_message()
		WebSocketPeer.STATE_CLOSING:
			$btn_connect.text = "disconnecting..."
			$btn_connect.disabled = true
		WebSocketPeer.STATE_CLOSED:
			m_connect_timer = 0.0
			$btn_connect.text = "connect"
			$btn_connect.disabled = false
			m_session_id = ""


func process_websocket_message() -> void:
	var packet := m_websocket.get_packet()
	var text := packet.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	
	if not data is Dictionary:
		return
		
	var dict := data as Dictionary

	var event: String = dict.get("event", "")

	if m_session_id.is_empty() and event == "session_created":
		# expect session id
		if dict.has("session_id"):
			m_session_id = dict["session_id"]
			print("session_id: ", m_session_id)
	elif event == "text_response":
		$text_assistant_response.text = "Kobe: " + dict.get("content")
	elif event == "audio_start":
		if dict.has("sample_rate"):
			m_audio_sample_rate = int(dict["sample_rate"])
			m_audio_stream_generator.mix_rate = m_audio_sample_rate
			print("Audio sample rate set to ", m_audio_sample_rate)
		if dict.has("channels"):
			m_audio_channels = int(dict["channels"])
			print("Audio channels set to ", m_audio_channels)
		m_audio_buf.clear()
		m_audio_done = false
		print("audio start")
	elif event == "audio_chunk":
		var encoded: String = dict.get("data", "")
		if not encoded.is_empty():
			var byte_count := encoded.length() / 2
			var decoded := PackedByteArray()
			decoded.resize(byte_count)
			for i in byte_count:
				decoded[i] = encoded.substr(i * 2, 2).hex_to_int()
			m_audio_buf.append_array(decoded)
			if not m_is_talking:
				_begin_talk()
				m_is_talking = true
	elif event == "audio_done":
		m_audio_done = true
		m_is_talking = false
		print("audio done, remaining bytes: ", m_audio_buf.size())


func _begin_talk():
	# Cancel any pending end-talk timer from a previous playback
	if m_end_talk_timer != null:
		if m_end_talk_timer.timeout.is_connected(_end_talk):
			m_end_talk_timer.timeout.disconnect(_end_talk)
		m_end_talk_timer = null
	$audio_player.play()
	m_audio_playback = $audio_player.get_stream_playback()
	$img_kobe_dynamic.visible = true
	($img_kobe_dynamic.texture as AnimatedTexture).current_frame = 0
	$img_kobe_static.visible = false

func _end_talk():
	m_end_talk_timer = null
	$audio_player.stop()
	$img_kobe_dynamic.visible = false
	$img_kobe_static.visible = true

func _on_btn_send_pressed() -> void:
	if m_ws_state == WebSocketPeer.STATE_OPEN and m_session_id != "":
		var input_text : String = $text_user_input.text.strip_edges()
		var message := {"action": "chat", "session_id": m_session_id, "message": input_text}
		m_websocket.send_text(JSON.stringify(message))


## Push buffered PCM data into AudioStreamGeneratorPlayback each frame
func _feed_audio() -> void:
	if m_audio_playback == null:
		return
	var frames_available := m_audio_playback.get_frames_available()
	if frames_available <= 0:
		return
	# 16-bit PCM: 2 bytes per sample; one sample per frame for Mono
	var bytes_per_frame := m_bytes_per_sample * m_audio_channels
	var max_bytes := frames_available * bytes_per_frame
	var available_bytes := m_audio_buf.size() - (m_audio_buf.size() % bytes_per_frame)
	var push_bytes := mini(max_bytes, available_bytes)
	var frames_to_push := push_bytes / bytes_per_frame
	for i in range(frames_to_push):
		var offset := i * bytes_per_frame
		# Decode 16-bit little-endian signed integer to normalized float
		var raw := m_audio_buf[offset] | (m_audio_buf[offset + 1] << 8)
		if raw >= 32768:
			raw -= 65536
		var sample := float(raw) / 32768.0
		if m_audio_channels == 1:
			m_audio_playback.push_frame(Vector2(sample, sample))
		else:
			var raw_r := m_audio_buf[offset + 2] | (m_audio_buf[offset + 3] << 8)
			if raw_r >= 32768:
				raw_r -= 65536
			m_audio_playback.push_frame(Vector2(sample, float(raw_r) / 32768.0))
	if push_bytes > 0:
		m_audio_buf = m_audio_buf.slice(push_bytes)
	# Stop once all buffered data has been consumed
	if m_audio_done and m_audio_buf.is_empty():
		m_audio_playback = null
		# Wait for the generator's internal buffer to drain before stopping
		m_end_talk_timer = get_tree().create_timer(m_audio_stream_generator.buffer_length)
		m_end_talk_timer.timeout.connect(_end_talk)


func _on_btn_connect_pressed() -> void:
	match m_websocket.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			var url: String = $text_connect_ip.text.strip_edges()
			m_connect_timer = 0.0
			m_websocket.connect_to_url(url)
		WebSocketPeer.STATE_OPEN:
			m_websocket.close()
