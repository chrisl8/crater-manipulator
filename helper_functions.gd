extends Node


func log_print(text: String, color: String = "white") -> void:
	if Globals.is_server or OS.is_debug_build():
		var unique_id: int = -1
		if multiplayer.has_multiplayer_peer():
			unique_id = multiplayer.get_unique_id()
		print_rich(
			"[color=",
			color,
			"]",
			Globals.local_debug_instance_number,
			" ",
			unique_id,
			" ",
			text,
			"[/color]"
		)


func generate_random_string(length: int) -> String:
	var characters: String = "abcdefghijklmnopqrstuvwxyz0123456789"
	var word: String = ""
	var n_char: int = len(characters)
	for i in range(length):
		word += characters[randi() % n_char]
	return word


func save_data_to_file(file_name: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(file_name, FileAccess.WRITE)
	file.store_string(content)


func load_data_from_file(file_name: String) -> String:
	var content: String = ""
	var file: FileAccess = FileAccess.open(file_name, FileAccess.READ)
	if file:
		content = file.get_as_text()
	return content


func save_server_player_save_data_to_file() -> void:
	# Save config back out to file, even if we imported it from the file.
	save_data_to_file(
		Globals.server_player_save_data_file_name, JSON.stringify(Globals.player_save_data)
	)


func quit_gracefully() -> void:
	# Quitting in Web just stops the game but leaves it stalled in the browser window, so it really should never happen.
	if !Globals.shutdown_in_progress and OS.get_name() != "Web":
		Globals.shutdown_in_progress = true
		if Globals.is_server:
			print_rich(
				"[color=orange]Disconnecting clients and saving data before shutting down server...[/color]"
			)
			var toast: Toast = Toast.new("Disconnecting clients and shutting down server...", 2.0)
			get_node("/root").add_child(toast)
			toast.display()
			Network.shutdown_server()
			while Network.peers.size() > 0:
				print_rich("[color=orange]...server still clearing clients...[/color]")
				await get_tree().create_timer(1).timeout
		get_tree().quit()
