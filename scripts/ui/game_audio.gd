class_name GameAudio
extends Node

const CUES := {"ui": "confirm", "pause": "chime", "move": "step", "hit": "impact"}
var music_enabled: bool = true
var effects_enabled: bool = true
var settings_path: String = ""
var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var cue_streams: Dictionary = {}
var voice_index: int = 0
var last_hit: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings_path.is_empty():
		settings_path = "user://audio_settings.cfg" if DisplayServer.get_name() != "headless" else "user://audio_test_%d.cfg" % OS.get_process_id()
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -15.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -9.0)
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		music_enabled = bool(config.get_value("audio", "music", true))
		effects_enabled = bool(config.get_value("audio", "effects", true))
	_apply()
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	var loop: AudioStreamWAV = load("res://assets/audio/dusk_ambient.wav").duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = loop.data.size() / 2
	music.stream = loop
	add_child(music)
	for cue in CUES:
		cue_streams[cue] = load("res://assets/audio/%s.wav" % CUES[cue])
	for index in range(6):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		voices.append(player)
	if DisplayServer.get_name() != "headless": music.play()


func _apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_enabled)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not effects_enabled)


func set_enabled(channel: String, enabled: bool) -> bool:
	if channel not in ["music", "effects"]: return false
	var config := ConfigFile.new()
	config.set_value("audio", "music", enabled if channel == "music" else music_enabled)
	config.set_value("audio", "effects", enabled if channel == "effects" else effects_enabled)
	if config.save(settings_path) != OK: return false
	if channel == "music": music_enabled = enabled
	else: effects_enabled = enabled
	_apply()
	return true


func play_cue(cue: String) -> void:
	if not effects_enabled or not cue_streams.has(cue) or voices.is_empty(): return
	if cue == "hit":
		var now := Time.get_ticks_msec()
		if now - last_hit < 65: return
		last_hit = now
	var player := voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	player.stream = cue_streams[cue]
	player.play()


func _exit_tree() -> void:
	if music != null: music.stop()
	for player in voices: player.stop()
