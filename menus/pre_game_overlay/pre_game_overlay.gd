extends Control


func set_msg(
	_msg: String, _color: Color = Color(0.59607845544815, 0.56078433990479, 0.88235294818878)
) -> void:
	$VBoxContainer/Detail.text = _msg
	$VBoxContainer/Detail.add_theme_color_override("font_color", _color)


func update_progress_bar(percentage: int = -1) -> void:
	if percentage >= 0:
		$VBoxContainer/ProgressBar.value = percentage
		$VBoxContainer/ProgressBar.visible = true
	else:
		$VBoxContainer/ProgressBar.visible = false
