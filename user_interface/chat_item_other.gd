extends Control

const MAX_TEXT_WIDTH := 750.0
const MIN_ITEM_HEIGHT := 80.0

@onready var text_label: Label = $HBoxContainer/text


func set_text(content: String) -> void:
	text_label.text = content
	_update_text_layout()


func _ready() -> void:
	_update_text_layout()


func _update_text_layout() -> void:    
	var font := text_label.get_theme_font("font")
	var font_size := text_label.get_theme_font_size("font_size")
	
	var real_text_size = font.get_multiline_string_size(
		text_label.text, 
		text_label.horizontal_alignment, 
		-1,
		font_size
	)
	
	var target_width = minf(MAX_TEXT_WIDTH, real_text_size.x)
	
	text_label.custom_minimum_size.x = target_width
	
	if real_text_size.x > MAX_TEXT_WIDTH:
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		text_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	text_label.update_minimum_size()
	update_minimum_size()
