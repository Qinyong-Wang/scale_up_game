extends Node

## SfxPlayer — 界面音效与按钮按压反馈。Per design/音频系统设计.md §4bis。
##
## 不依赖静态 click 文件: 运行时生成一个很短的 AudioStreamWAV, 用小播放器池轮询播放。
## 视觉反馈只缩放 Control, 不改 Container 布局。

const CLICK_POOL_SIZE := 4
const CLICK_MIX_RATE := 44100
const CLICK_DURATION_SEC := 0.055
const CLICK_VOLUME_DB := -16.0
const PRESS_SCALE := 0.975
const PRESS_DOWN_SEC := 0.045
const PRESS_UP_SEC := 0.075

var _players: Array[AudioStreamPlayer] = []
var _player_index := 0
var _button_click_stream: AudioStreamWAV
var _registered_buttons: Dictionary = {}  # instance_id -> true
var _button_refs: Dictionary = {}          # instance_id -> WeakRef
var _button_base_scales: Dictionary = {}   # instance_id -> Vector2
var _button_tweens: Dictionary = {}        # instance_id -> Tween
var _clicks_played_for_test := 0

func _ready() -> void:
	_button_click_stream = _make_button_click_stream()
	for i in range(CLICK_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		p.volume_db = CLICK_VOLUME_DB
		p.stream = _button_click_stream
		add_child(p)
		_players.append(p)
	if get_tree() != null and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred(&"_register_existing_buttons")

func is_enabled() -> bool:
	return Preferences.sfx_enabled

func set_enabled(enabled: bool) -> void:
	Preferences.set_sfx_enabled(enabled)

func register_button(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return
	var id := button.get_instance_id()
	if _registered_buttons.has(id):
		return
	_registered_buttons[id] = true
	_button_refs[id] = weakref(button)
	_button_base_scales[id] = button.scale
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_connect_button_signal(button.pressed, _on_button_pressed.bind(button))
	_connect_button_signal(button.button_down, _on_button_down.bind(button))
	_connect_button_signal(button.button_up, _on_button_up.bind(button))
	_connect_button_signal(button.mouse_exited, _on_button_up.bind(button))
	_connect_button_signal(button.tree_exiting, _on_button_exiting.bind(id))

func play_button_click() -> void:
	if not is_enabled():
		return
	if _players.is_empty() or _button_click_stream == null:
		return
	_clicks_played_for_test += 1
	var p: AudioStreamPlayer = _players[_player_index % _players.size()]
	_player_index = (_player_index + 1) % _players.size()
	p.stop()
	p.volume_db = CLICK_VOLUME_DB
	p.stream = _button_click_stream
	p.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		register_button(node as BaseButton)

func _register_existing_buttons() -> void:
	var root := get_tree().root if get_tree() != null else null
	if root != null:
		_register_buttons_recursive(root)

func _register_buttons_recursive(node: Node) -> void:
	if node is BaseButton:
		register_button(node as BaseButton)
	for child in node.get_children():
		_register_buttons_recursive(child)

func _on_button_pressed(_button: BaseButton) -> void:
	play_button_click()

func _on_button_down(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button) or button.disabled:
		return
	var id := button.get_instance_id()
	if not _button_base_scales.has(id):
		_button_base_scales[id] = button.scale
	button.pivot_offset = button.size * 0.5
	var base: Vector2 = _button_base_scales[id]
	_tween_button_scale(button, base * PRESS_SCALE, PRESS_DOWN_SEC)

func _on_button_up(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return
	var id := button.get_instance_id()
	var base: Vector2 = _button_base_scales.get(id, Vector2.ONE)
	_tween_button_scale(button, base, PRESS_UP_SEC)

func _on_button_exiting(id: int) -> void:
	var button := _button_for_id(id)
	if button != null:
		_disconnect_button_signals(button, id)
	_kill_button_tween(id)
	_registered_buttons.erase(id)
	_button_refs.erase(id)
	_button_base_scales.erase(id)
	_button_tweens.erase(id)

func _button_for_id(id: int) -> BaseButton:
	var ref: WeakRef = _button_refs.get(id, null)
	if ref == null:
		return null
	var obj: Object = ref.get_ref()
	if obj is BaseButton and is_instance_valid(obj):
		return obj as BaseButton
	return null

func _connect_button_signal(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)

func _disconnect_button_signals(button: BaseButton, id: int) -> void:
	_disconnect_button_signal(button.pressed, _on_button_pressed.bind(button))
	_disconnect_button_signal(button.button_down, _on_button_down.bind(button))
	_disconnect_button_signal(button.button_up, _on_button_up.bind(button))
	_disconnect_button_signal(button.mouse_exited, _on_button_up.bind(button))
	_disconnect_button_signal(button.tree_exiting, _on_button_exiting.bind(id))

func _disconnect_button_signal(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)

func _tween_button_scale(button: BaseButton, target: Vector2, duration: float) -> void:
	var id := button.get_instance_id()
	_kill_button_tween(id)
	var t := button.create_tween()
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(button, "scale", target, duration)
	_button_tweens[id] = t

func _kill_button_tween(id: int) -> void:
	var t: Tween = _button_tweens.get(id, null)
	if t != null and t.is_valid():
		t.kill()

func _make_button_click_stream() -> AudioStreamWAV:
	var sample_count := int(CLICK_MIX_RATE * CLICK_DURATION_SEC)
	var bytes := PackedByteArray()
	bytes.resize(0)
	for i in range(sample_count):
		var t := float(i) / float(CLICK_MIX_RATE)
		var phase := float(i) / float(sample_count)
		var env := pow(1.0 - phase, 3.2)
		var wave := sin(TAU * 1450.0 * t) * 0.55 + sin(TAU * 2350.0 * t) * 0.30
		var sample := int(clampf(wave * env * 32767.0, -32768.0, 32767.0))
		if sample < 0:
			sample += 65536
		bytes.append(sample & 0xff)
		bytes.append((sample >> 8) & 0xff)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = CLICK_MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
