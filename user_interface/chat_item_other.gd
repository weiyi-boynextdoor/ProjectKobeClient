extends Control

@onready var text_label: Label = $HBoxContainer/text


func set_text(content: String) -> void:
	text_label.text = content
