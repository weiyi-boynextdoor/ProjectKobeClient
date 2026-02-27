extends Control

const CONNECT_TIMEOUT := 5.0

var ws := WebSocketPeer.new()
var ws_state := WebSocketPeer.STATE_CLOSED
var connect_timer := 0.0


func _process(delta: float) -> void:
	ws.poll()
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
		WebSocketPeer.STATE_CLOSING:
			$btn_connect.text = "disconnecting..."
			$btn_connect.disabled = true
		WebSocketPeer.STATE_CLOSED:
			connect_timer = 0.0
			$btn_connect.text = "connect"
			$btn_connect.disabled = false


func _on_btn_playsound_pressed() -> void:
	$audio_player.play()


func _on_btn_connect_pressed() -> void:
	match ws.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			var url: String = $text_connect_ip.text.strip_edges()
			connect_timer = 0.0
			ws.connect_to_url(url)
		WebSocketPeer.STATE_OPEN:
			ws.close()
