extends Control

const CONNECT_TIMEOUT := 5.0
## Adjust these to match the server's audio format
const AUDIO_SAMPLE_RATE := 32000
const AUDIO_CHANNELS := 1  # 1=Mono, 2=Stereo

var ws := WebSocketPeer.new()
var ws_state := WebSocketPeer.STATE_CLOSED
var connect_timer := 0.0
var session_id: String = ""

var _audio_buf := PackedByteArray()
var _audio_playback: AudioStreamGeneratorPlayback = null
var _audio_done := false


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AUDIO_SAMPLE_RATE
	gen.buffer_length = 0.2  # 200ms buffer to reduce stuttering
	$audio_player.stream = gen


func _process(delta: float) -> void:
	_feed_audio()
	ws.poll()
	var last_ws_state := ws_state
	ws_state = ws.get_ready_state()
	match ws_state:
		WebSocketPeer.STATE_CONNECTING:
			connect_timer += delta
			if connect_timer >= CONNECT_TIMEOUT:
				ws.close()
				connect_timer = 0.0
			$btn_connect.text = "connecting..."
			$btn_connect.disabled = true
		WebSocketPeer.STATE_OPEN:
			$btn_connect.text = "disconnect"
			$btn_connect.disabled = false
			if last_ws_state != WebSocketPeer.STATE_OPEN:
				# create session
				print("websocket connected, creating session...")
				ws.send_text(JSON.stringify({"action": "create_session"}))
			while ws.get_available_packet_count() > 0:
				process_websocket_message()
		WebSocketPeer.STATE_CLOSING:
			$btn_connect.text = "disconnecting..."
			$btn_connect.disabled = true
		WebSocketPeer.STATE_CLOSED:
			connect_timer = 0.0
			$btn_connect.text = "connect"
			$btn_connect.disabled = false
			session_id = ""


func process_websocket_message() -> void:
	var packet := ws.get_packet()
	var text := packet.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	
	if not data is Dictionary:
		return
		
	var dict := data as Dictionary

	var event: String = dict.get("event", "")

	if session_id.is_empty() and event == "session_created":
		# expect session id
		if dict.has("session_id"):
			session_id = dict["session_id"]
			print("session_id: ", session_id)
	elif event == "text_response":
		$text_assistant_response.text = "Kobe: " + dict.get("content")
	elif event == "audio_start":
		_audio_buf.clear()
		_audio_done = false
		$audio_player.play()
		_audio_playback = $audio_player.get_stream_playback()
		print("audio start")
	elif event == "audio_chunk":
		var encoded: String = dict.get("data", "")
		if not encoded.is_empty():
			var byte_count := encoded.length() / 2
			var decoded := PackedByteArray()
			decoded.resize(byte_count)
			for i in byte_count:
				decoded[i] = encoded.substr(i * 2, 2).hex_to_int()
			_audio_buf.append_array(decoded)
	elif event == "audio_done":
		_audio_done = true
		print("audio done, remaining bytes: ", _audio_buf.size())


func _on_btn_send_pressed() -> void:
	if ws_state == WebSocketPeer.STATE_OPEN and session_id != "":
		var input_text : String = $text_user_input.text.strip_edges()
		var message := {"action": "chat", "session_id": session_id, "message": input_text}
		ws.send_text(JSON.stringify(message))


## Push buffered PCM data into AudioStreamGeneratorPlayback each frame
func _feed_audio() -> void:
	if _audio_playback == null:
		return
	var frames_available := _audio_playback.get_frames_available()
	if frames_available <= 0:
		return
	# 16-bit PCM: 2 bytes per sample; one sample per frame for Mono
	var bytes_per_frame := 2 * AUDIO_CHANNELS
	var max_bytes := frames_available * bytes_per_frame
	var available_bytes := _audio_buf.size() - (_audio_buf.size() % bytes_per_frame)
	var push_bytes := mini(max_bytes, available_bytes)
	var frames_to_push := push_bytes / bytes_per_frame
	for i in range(frames_to_push):
		var offset := i * bytes_per_frame
		# Decode 16-bit little-endian signed integer to normalized float
		var raw := _audio_buf[offset] | (_audio_buf[offset + 1] << 8)
		if raw >= 32768:
			raw -= 65536
		var sample := float(raw) / 32768.0
		if AUDIO_CHANNELS == 1:
			_audio_playback.push_frame(Vector2(sample, sample))
		else:
			var raw_r := _audio_buf[offset + 2] | (_audio_buf[offset + 3] << 8)
			if raw_r >= 32768:
				raw_r -= 65536
			_audio_playback.push_frame(Vector2(sample, float(raw_r) / 32768.0))
	if push_bytes > 0:
		_audio_buf = _audio_buf.slice(push_bytes)
	# Stop once all buffered data has been consumed
	if _audio_done and _audio_buf.is_empty():
		_audio_playback = null


func _on_btn_connect_pressed() -> void:
	match ws.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			var url: String = $text_connect_ip.text.strip_edges()
			connect_timer = 0.0
			ws.connect_to_url(url)
		WebSocketPeer.STATE_OPEN:
			ws.close()
