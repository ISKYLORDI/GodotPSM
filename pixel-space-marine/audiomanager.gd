extends Node

enum SfxCategory { MISC = 0, FOOTSTEP, COMBAT, WORLD, UI }
# 可在 Inspector 里配置：音效名 -> 音效路径（res://...）
@export var sfx_paths: Dictionary = {
	"walk": "res://Resources/Audio/SFX/walk.wav",
	"hit": "res://Resources/Audio/SFX/hit.wav",
	"die": "res://Resources/Audio/SFX/die.wav",
	"use_item": "res://Resources/Audio/SFX/use_item.wav",
	"Playershot": "res://Resources/Audio/SFX/Playershot.mp3",
	"Reload": "res://Resources/Audio/SFX/Reload.mp3",
	"Aim": "res://Resources/Audio/SFX/Aim.mp3",
	"Holster": "res://Resources/Audio/SFX/Holster.mp3",
	"Explosion1": "res://Resources/Audio/SFX/Explosion1.mp3",
	"Explosion2": "res://Resources/Audio/SFX/Explosion2.mp3",
	"GlassBreak": "res://Resources/Audio/SFX/GlassBreak.mp3",
	"Hit1": "res://Resources/Audio/SFX/Hit1.mp3",
	"Hit2": "res://Resources/Audio/SFX/Hit2.mp3",
	"Hit3": "res://Resources/Audio/SFX/Hit3.mp3",
	"Hit4": "res://Resources/Audio/SFX/Hit4.mp3",
	"Hit5": "res://Resources/Audio/SFX/Hit5.mp3",
	"EnemyDeath1": "res://Resources/Audio/SFX/EnemyDeath1.mp3",
	"EnemyDeath2": "res://Resources/Audio/SFX/EnemyDeath2.mp3",
	"PlayerDeath1": "res://Resources/Audio/SFX/PlayerDeath.mp3",
	"PlayerDeath2": "res://Resources/Audio/SFX/PlayerDeath2.mp3",
	"Footstep1": "res://Resources/Audio/SFX/Footstep1.mp3",
	"Footstep2": "res://Resources/Audio/SFX/Footstep2.mp3",
	"Footstep3": "res://Resources/Audio/SFX/Footstep3.mp3",
	"Impact1": "res://Resources/Audio/SFX/Impact1.mp3",
	"Impact2": "res://Resources/Audio/SFX/Impact2.mp3",
	"Impact3": "res://Resources/Audio/SFX/Impact3.mp3",
	"Impact4": "res://Resources/Audio/SFX/Impact4.mp3",
	"Impact5": "res://Resources/Audio/SFX/Impact5.mp3",
	"Impact6": "res://Resources/Audio/SFX/Impact6.mp3",
	"Splash": "res://Resources/Audio/SFX/Splash.mp3",
	"WaterFootstep1": "res://Resources/Audio/SFX/WaterStep-01.wav",
	"WaterFootstep2": "res://Resources/Audio/SFX/WaterStep-02.wav",
	"WaterFootstep3": "res://Resources/Audio/SFX/WaterStep-03.wav",
	"DoorOpen": "res://Resources/Audio/SFX/DoorOpen.mp3",
	"Switch": "res://Resources/Audio/SFX/Switch.mp3",
	"Exit": "res://Resources/Audio/SFX/Exit.mp3",
	"MetalPipe": "res://Resources/Audio/SFX/MetalPipe.wav",
	"Hurt": "res://Resources/Audio/SFX/Hurt.mp3",
	"Fire": "res://Resources/Audio/SFX/Fire.mp3",
	"Ignite": "res://Resources/Audio/SFX/Ignite.wav",
	"Ricochet1": "res://Resources/Audio/SFX/Ricochet1.wav",
	"Ricochet2": "res://Resources/Audio/SFX/Ricochet2.wav",
	"Ricochet3": "res://Resources/Audio/SFX/Ricochet3.wav",
}
# 可选：统一走哪个音频总线
@export var sfx_bus: StringName = &"SFX"
@export_range(-40.0, 6.0, 0.5) var sfx_volume_db: float = -6.0
@export_range(-40.0, 6.0, 0.5) var footstep_volume_db: float = -12.0
@export_group("Pitch variance")
## 关掉后不按分类微调音高；仍可用下方各分类开关为将来扩展保留。
@export var pitch_variance_enabled: bool = true
## 半音偏移上限（± 值），在该范围内均匀随机。
@export_range(0.0, 2.0, 0.05) var pitch_variance_max_semitones: float = 0.2
## 应用到所有通过 play_sfx 播放的音效；按分类勾选。
@export var pitch_variance_footsteps: bool = true
@export var pitch_variance_combat: bool = true
@export var pitch_variance_world: bool = true
@export var pitch_variance_ui: bool = false
@export var pitch_variance_misc: bool = true
@export_group("Fire ambience")
## 玩家在视野内看到燃烧液体时播放的循环音效；渐入渐出以避免突兀。
@export var fire_ambience_enabled: bool = true
@export_range(0.05, 5.0, 0.05) var fire_ambience_fade_in_sec: float = 0.4
@export_range(0.05, 5.0, 0.05) var fire_ambience_fade_out_sec: float = 0.55
@export_range(-48.0, 6.0, 0.5) var fire_ambience_volume_db: float = -16.0
# 缓存已加载的音频，避免高频 load() 造成抖动
var _stream_cache: Dictionary = {} # sfx_name(String) -> AudioStream
var _missing_bus_warned: bool = false
var _pitch_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fire_loop_player: AudioStreamPlayer
var _fire_ambience_wants_on: bool = false
var _fire_fade_tween: Tween
const SILENT_VOLUME_DB := -80.0


func _ready() -> void:
	print("AudioManager ready. name=", name, " path=", get_path())
	add_to_group("audio_manager_play_sfx")
	_pitch_rng.randomize()

func play_sfx(sfx_name: String) -> void:
	if sfx_name.is_empty():
		push_warning("AudioManager.play_sfx: sfx_name 为空。")
		return
	var stream: AudioStream = _get_stream(sfx_name)
	if stream == null:
		# _get_stream 内会输出更具体的 warning
		return
	# 动态创建临时播放器
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = _resolve_bus_name()
	player.volume_db = _resolve_sfx_volume_db(sfx_name)
	_apply_pitch_variance(player, sfx_name)
	# 若管理器不在树中（极少见），防御处理
	var tree := get_tree()
	if tree == null or tree.root == null:
		push_warning("AudioManager.play_sfx: SceneTree 不可用，无法播放 '%s'。" % sfx_name)
		player.queue_free()
		return
	# 加入场景树并播放
	tree.root.add_child(player)
	player.play()
	# 播完自动释放；ONE_SHOT 防止重复连接导致问题
	player.finished.connect(_on_player_finished.bind(player), CONNECT_ONE_SHOT)
func _get_stream(sfx_name: String) -> AudioStream:
	# 命中缓存
	if _stream_cache.has(sfx_name):
		return _stream_cache[sfx_name] as AudioStream
	# 检查配置
	if not sfx_paths.has(sfx_name):
		var auto_stream := _try_load_fallback_stream(sfx_name)
		if auto_stream != null:
			_stream_cache[sfx_name] = auto_stream
			return auto_stream
		push_warning("AudioManager: 未配置音效 '%s'。" % sfx_name)
		return null
	var path_variant = sfx_paths[sfx_name]
	if typeof(path_variant) != TYPE_STRING:
		push_warning("AudioManager: 音效 '%s' 的路径不是字符串。" % sfx_name)
		return null
	var path: String = path_variant
	if path.is_empty():
		push_warning("AudioManager: 音效 '%s' 的路径为空。" % sfx_name)
		return null
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: 资源路径不存在 '%s' -> %s" % [sfx_name, path])
		return null
	# 动态加载并缓存
	var res := load(path)
	if res == null:
		push_warning("AudioManager: 加载失败 '%s' -> %s" % [sfx_name, path])
		return null
	if not (res is AudioStream):
		push_warning("AudioManager: 资源不是 AudioStream '%s' -> %s" % [sfx_name, path])
		return null
	var stream := res as AudioStream
	_stream_cache[sfx_name] = stream
	return stream


func _try_load_fallback_stream(sfx_name: String) -> AudioStream:
	var candidates: PackedStringArray = [
		"res://Resources/Audio/SFX/%s.mp3" % sfx_name,
		"res://Resources/Audio/SFX/%s.wav" % sfx_name,
	]
	for path in candidates:
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is AudioStream:
			return res as AudioStream
	return null
func _on_player_finished(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.queue_free()


func _resolve_bus_name() -> StringName:
	var bus_name := sfx_bus
	if AudioServer.get_bus_index(bus_name) == -1:
		if not _missing_bus_warned:
			_missing_bus_warned = true
			push_warning("AudioManager: 音频总线 '%s' 不存在，已回退到 'Master'。" % String(bus_name))
		return &"Master"
	_missing_bus_warned = false
	return bus_name


func _resolve_sfx_volume_db(sfx_name: String) -> float:
	if sfx_name.begins_with("Footstep") or sfx_name.begins_with("WaterFootstep"):
		return footstep_volume_db
	return sfx_volume_db


func _resolve_sfx_category(sfx_name: String) -> SfxCategory:
	if sfx_name.begins_with("Footstep") or sfx_name.begins_with("WaterFootstep"):
		return SfxCategory.FOOTSTEP
	if sfx_name.begins_with("Hit") \
			or sfx_name.begins_with("Impact") \
			or sfx_name == "Playershot" \
			or sfx_name == "Hurt" \
			or sfx_name.begins_with("EnemyDeath") \
			or sfx_name.begins_with("PlayerDeath") \
			or sfx_name.begins_with("Explosion") \
			or sfx_name == "GlassBreak":
		return SfxCategory.COMBAT
	if sfx_name == "DoorOpen" or sfx_name == "Switch" or sfx_name == "Exit" or sfx_name == "walk" or sfx_name == "Ignite":
		return SfxCategory.WORLD
	if sfx_name == "Reload" or sfx_name == "Aim" or sfx_name == "Holster":
		return SfxCategory.UI
	return SfxCategory.MISC


func _pitch_variance_toggle_for(cat: SfxCategory) -> bool:
	match cat:
		SfxCategory.FOOTSTEP:
			return pitch_variance_footsteps
		SfxCategory.COMBAT:
			return pitch_variance_combat
		SfxCategory.WORLD:
			return pitch_variance_world
		SfxCategory.UI:
			return pitch_variance_ui
		_:
			return pitch_variance_misc


func _apply_pitch_variance(player: AudioStreamPlayer, sfx_name: String) -> void:
	player.pitch_scale = 1.0
	if not pitch_variance_enabled:
		return
	var cat := _resolve_sfx_category(sfx_name)
	if not _pitch_variance_toggle_for(cat):
		return
	var max_s := absf(pitch_variance_max_semitones)
	if max_s <= 0.0:
		return
	var deviation := _pitch_rng.randf_range(-max_s, max_s)
	player.pitch_scale = pow(2.0, deviation / 12.0)
	player.pitch_scale = clampf(player.pitch_scale, 0.25, 4.0)


func update_fire_ambience(want_play: bool) -> void:
	if not fire_ambience_enabled:
		want_play = false
	if want_play == _fire_ambience_wants_on:
		return
	_fire_ambience_wants_on = want_play
	_kill_fire_ambience_tween()
	if want_play:
		if not _prepare_fire_loop_player():
			return
		if not _fire_loop_player.playing:
			_fire_loop_player.volume_db = SILENT_VOLUME_DB
			_fire_loop_player.play()
		var start_db := _fire_loop_player.volume_db
		_fire_fade_tween = create_tween()
		var tw := _fire_fade_tween.tween_property(_fire_loop_player, "volume_db", fire_ambience_volume_db, fire_ambience_fade_in_sec).from(start_db)
		if tw != null:
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if _fire_loop_player == null or not is_instance_valid(_fire_loop_player) or not _fire_loop_player.playing:
			return
		var start_db := _fire_loop_player.volume_db
		_fire_fade_tween = create_tween()
		var tw_out := _fire_fade_tween.tween_property(_fire_loop_player, "volume_db", SILENT_VOLUME_DB, fire_ambience_fade_out_sec).from(start_db)
		if tw_out != null:
			tw_out.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_fire_fade_tween.finished.connect(_on_fire_ambience_fade_out_finished)


func _on_fire_ambience_fade_out_finished() -> void:
	if not _fire_ambience_wants_on and _fire_loop_player != null and is_instance_valid(_fire_loop_player):
		_fire_loop_player.stop()


func _kill_fire_ambience_tween() -> void:
	if _fire_fade_tween != null and is_instance_valid(_fire_fade_tween):
		if _fire_fade_tween.is_valid():
			_fire_fade_tween.kill()
	_fire_fade_tween = null


func _prepare_fire_loop_player() -> bool:
	if _fire_loop_player != null and is_instance_valid(_fire_loop_player) and _fire_loop_player.stream != null:
		_fire_loop_player.bus = _resolve_bus_name()
		return true
	if _fire_loop_player != null and is_instance_valid(_fire_loop_player):
		_fire_loop_player.queue_free()
		_fire_loop_player = null
	var base := _get_stream("Fire")
	if base == null:
		return false
	_fire_loop_player = AudioStreamPlayer.new()
	_fire_loop_player.name = "FireAmbienceLoop"
	add_child(_fire_loop_player)
	var dup: AudioStream = base.duplicate(true) as AudioStream
	if dup is AudioStreamMP3:
		(dup as AudioStreamMP3).loop = true
	elif dup is AudioStreamWAV:
		(dup as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_fire_loop_player.stream = dup
	_fire_loop_player.bus = _resolve_bus_name()
	_fire_loop_player.pitch_scale = 1.0
	return true
