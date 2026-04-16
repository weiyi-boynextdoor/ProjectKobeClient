extends Control

const MAX_TEXT_WIDTH := 800.0
const MIN_ITEM_HEIGHT := 80.0

@onready var text_label: Label = $HBoxContainer/text


func set_text(content: String) -> void:
	text_label.text = content
	_update_text_layout()


func _ready() -> void:
	_update_text_layout()


func _update_text_layout() -> void:
	var font: Font = text_label.get_theme_font("font")
	var font_size: int = text_label.get_theme_font_size("font_size")
	var content_width := 0.0

	for line in text_label.text.split("\n"):
		content_width = maxf(
			content_width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)

	var target_width := minf(MAX_TEXT_WIDTH, ceilf(content_width) + 1.0)
	text_label.custom_minimum_size.x = maxf(1.0, target_width)
	custom_minimum_size.y = maxf(MIN_ITEM_HEIGHT, text_label.get_combined_minimum_size().y)
	text_label.update_minimum_size()
	update_minimum_size()
