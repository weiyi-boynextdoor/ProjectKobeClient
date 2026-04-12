extends Node

signal connection_state_changed(state: int)
signal text_response_received(content: String)
signal audio_started(sample_rate: int, channels: int)
signal audio_chunk_received(data: PackedByteArray)
signal audio_finished()

const CONNECT_TIMEOUT := 5.0

var websocket: WebSocketPeer = WebSocketPeer.new()
var ws_state: int = WebSocketPeer.STATE_CLOSED
var connect_timer: float = 0.0


func poll(delta: float) -> void:
	websocket.poll()

	var previous_state: int = ws_state
	ws_state = websocket.get_ready_state()

	if ws_state == WebSocketPeer.STATE_CONNECTING:
		connect_timer += delta
		if connect_timer >= CONNECT_TIMEOUT:
			websocket.close()
			connect_timer = 0.0
	elif ws_state == WebSocketPeer.STATE_OPEN:
		connect_timer = 0.0
		while websocket.get_available_packet_count() > 0:
			_process_websocket_message()
	elif ws_state == WebSocketPeer.STATE_CLOSED:
		connect_timer = 0.0

	if previous_state != ws_state:
		connection_state_changed.emit(ws_state)


func connect_to_server(ip: String, port: String) -> void:
	if websocket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return
	var url := "ws://{0}:{1}/ws".format([ip.strip_edges(), port.strip_edges()])
	connect_timer = 0.0
	websocket.connect_to_url(url)
	ws_state = websocket.get_ready_state()
	connection_state_changed.emit(ws_state)


func disconnect_from_server() -> void:
	if websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		websocket.close()
		ws_state = websocket.get_ready_state()
		connection_state_changed.emit(ws_state)


func send_chat_message(message: String) -> void:
	if ws_state != WebSocketPeer.STATE_OPEN:
		return
	var payload := {
		"action": "chat",
		"message": message.strip_edges(),
	}
	websocket.send_text(JSON.stringify(payload))


func get_connection_state() -> int:
	return ws_state


func _process_websocket_message() -> void:
	var packet := websocket.get_packet()
	var text := packet.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)

	if not data is Dictionary:
		return

	var dict := data as Dictionary
	var event: String = dict.get("event", "")

	if event == "text_response":
		text_response_received.emit(dict.get("content", ""))
	elif event == "audio_start":
		audio_started.emit(int(dict.get("sample_rate", 32000)), int(dict.get("channels", 1)))
	elif event == "audio_chunk":
		var encoded: String = dict.get("data", "")
		if not encoded.is_empty():
			audio_chunk_received.emit(_decode_hex_bytes(encoded))
	elif event == "audio_done":
		audio_finished.emit()


func _decode_hex_bytes(encoded: String) -> PackedByteArray:
	var byte_count := encoded.length() / 2
	var decoded := PackedByteArray()
	decoded.resize(byte_count)
	for i in byte_count:
		decoded[i] = encoded.substr(i * 2, 2).hex_to_int()
	return decoded
