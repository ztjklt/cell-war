class_name WarAudio
extends Node
var players: Dictionary = {}

func _ready() -> void:
	# Headless rules/presentation checks do not own an audio device.
	if DisplayServer.get_name() == "headless": return
	for key in ["ambient","command","build"]:
		var path: String = "res://assets/audio/"+key+".wav"
		if not ResourceLoader.exists(path): continue
		var player := AudioStreamPlayer.new()
		player.stream = load(path)
		player.volume_db = linear_to_db(.4 if key == "ambient" else .25)
		add_child(player)
		players[key] = player
		if key == "ambient":
			if player.stream is AudioStreamWAV: player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			player.play()

func play(key: String) -> void:
	if players.has(key): players[key].play()

func _exit_tree() -> void:
	for player in players.values():
		player.stop()
		if player.finished.is_connected(player.play): player.finished.disconnect(player.play)
		player.stream = null
	players.clear()
