extends Control

const CONNECT_TIMEOUT := 5.0

var ws := WebSocketPeer.new()
var ws_state := WebSocketPeer.STATE_CLOSED
var connect_timer := 0.0
var session_id: String = ""


func _process(delta: float) -> void:
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

	if session_id.is_empty():
		# expect session id
		if data is Dictionary and data.has("session_id"):
			session_id = data["session_id"]
			print("session_id: ", session_id)
	else:
		if data is Dictionary and data.get("event") == "text_response":
			$text_assistant_response.text = "Kobe: " + data.get("content")


func _on_btn_send_pressed() -> void:
	# $audio_player.play()
	if ws_state == WebSocketPeer.STATE_OPEN and session_id != "":
		var input_text : String = $text_user_input.text.strip_edges()
		var message := {"action": "chat", "session_id": session_id, "message": input_text}
		ws.send_text(JSON.stringify(message))


func _on_btn_connect_pressed() -> void:
	match ws.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			var url: String = $text_connect_ip.text.strip_edges()
			connect_timer = 0.0
			ws.connect_to_url(url)
		WebSocketPeer.STATE_OPEN:
			ws.close()
