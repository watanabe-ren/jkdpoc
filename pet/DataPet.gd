## DataPet.gd
## データペット中枢スクリプト（Phase 6・7 対応版）
## ・FormRegistry を使って複数フォームに対応
## ・憑依完了後に一定時間で次のアンカーへ自動移動
## ・同じアンカーへの連続憑依を避けるランダム選択
##
## res://scripts/pet/DataPet.gd

class_name DataPet
extends Node3D

# ---------------------------------------------------------------------------
# 状態定義
# ---------------------------------------------------------------------------

enum PetState {
	IDLE,             ## 浮遊待機中
	MOVING_TO_ANCHOR, ## アンカーへ移動中
	POSSESSING,       ## 憑依エフェクト再生中
	POSSESSED,        ## 憑依中
	RELEASING,        ## 憑依解除中
}

# ---------------------------------------------------------------------------
# エクスポートプロパティ（Inspector から調整可能）
# ---------------------------------------------------------------------------

## 最初の憑依発火までの待機時間（秒）
@export var first_possession_delay: float = 5.0

## 憑依後に次のアンカーへ移動するまでの待機時間（秒）
@export var stay_duration_min: float = 8.0
@export var stay_duration_max: float = 15.0

## 移動速度（m/秒）
@export var move_speed: float = 0.8

## ふわふわの振幅（メートル）
@export var hover_amplitude: float = 0.05

## ふわふわの周期（秒）
@export var hover_period: float = 2.0

# ---------------------------------------------------------------------------
# 内部ノード参照
# ---------------------------------------------------------------------------

var _form_slot: Node3D = null
var _possession_timer: Timer = null
var _stay_timer: Timer = null  # 憑依後の滞在タイマー
var _base_mesh: Node3D = null  # ← これを追加

# ---------------------------------------------------------------------------
# 内部状態
# ---------------------------------------------------------------------------

var _state: PetState = PetState.IDLE
var _target_anchor: PlacementAnchor = null
var _current_form: FormBase = null
var _current_form_node: Node3D = null  # ワールドに配置したフォームノード
var _hover_base_y: float = 0.0
var _hover_elapsed: float = 0.0
var _scene_mapper: SceneMapper = null

## 直前に憑依したアンカーIDを記録（同じ場所への連続憑依を避ける）
var _last_anchor_id: String = ""

# ---------------------------------------------------------------------------
# シグナル
# ---------------------------------------------------------------------------

signal possession_started(anchor: PlacementAnchor)
signal possession_completed(anchor: PlacementAnchor)
signal possession_released(anchor: PlacementAnchor)

# ---------------------------------------------------------------------------
# ライフサイクル
# ---------------------------------------------------------------------------

func _ready() -> void:
	_hover_base_y = position.y

	# ノード参照（Node3D として取得）
	_base_mesh = get_node_or_null("PetBaseMesh") as Node3D
	if _base_mesh == null:
		push_warning("DataPet: PetBaseMesh が見つかりません。")

	_form_slot = get_node_or_null("FormSlot") as Node3D
	if _form_slot == null:
		push_error("DataPet: FormSlot が見つかりません。")
		return

	# タイマーを確実にコードで生成
	_possession_timer = Timer.new()
	_possession_timer.name = "PossessionTimer"
	_possession_timer.one_shot = true
	_possession_timer.wait_time = first_possession_delay
	add_child(_possession_timer)
	_possession_timer.timeout.connect(_on_possession_timer_timeout)

	_stay_timer = Timer.new()
	_stay_timer.name = "StayTimer"
	_stay_timer.one_shot = true
	_stay_timer.timeout.connect(_on_stay_timer_timeout)
	add_child(_stay_timer)

	print("DataPet: 起動。SceneMapper の設定を待機します。")
	
	# ---------------------------------------------------------
	# [イベントの購読 (Subscribe)]
	# グローバルなイベント管理（EventBus）から通知を受け取るための設定。
	# ---------------------------------------------------------
	var event_bus = get_node_or_null("/root/EventBus")
	if event_bus and event_bus.has_signal("behavior_triggered"):
		# EventBusが「behavior_triggered」というシグナル（割り込み）を発行したら、
		# 自身の「_on_behavior_triggered」関数を実行するように結線（関数ポインタを登録）する
		event_bus.behavior_triggered.connect(_on_behavior_triggered)
		print("DataPet: EventBusの監視を開始しました")
	else:
		push_warning("DataPet: EventBusが見つからないか、シグナルがありません")

func _process(delta: float) -> void:
	match _state:
		PetState.IDLE:
			_process_hover(delta)
		PetState.MOVING_TO_ANCHOR:
			_process_move_to_anchor(delta)


# ---------------------------------------------------------------------------
# ふわふわ浮遊
# ---------------------------------------------------------------------------

func _process_hover(delta: float) -> void:
	_hover_elapsed += delta
	var offset: float = sin(_hover_elapsed * TAU / hover_period) * hover_amplitude
	position.y = _hover_base_y + offset


# ---------------------------------------------------------------------------
# アンカーへの移動
# ---------------------------------------------------------------------------

func _process_move_to_anchor(delta: float) -> void:
	if _target_anchor == null:
		_set_state(PetState.IDLE)
		return

	var target_pos: Vector3 = _target_anchor.get_world_position()
	var dir: Vector3 = target_pos - global_position
	var dist: float = dir.length()

	_hover_elapsed += delta
	var hover_offset: float = sin(_hover_elapsed * TAU / hover_period) * hover_amplitude * 0.5

	if dist < 0.05:
		global_position = target_pos
		_start_possession()
	else:
		global_position += dir.normalized() * move_speed * delta
		position.y += hover_offset * delta

	# 移動中は椅子の方向を向く
	var look_target := Vector3(_target_anchor.global_position.x, global_position.y, _target_anchor.global_position.z)
	if global_position.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)


# ---------------------------------------------------------------------------
# 憑依フロー
# ---------------------------------------------------------------------------

## 最初の憑依タイマー発火
func _on_possession_timer_timeout() -> void:
	print("DataPet: タイマー発火。アンカーを検索します。")
	_move_to_next_anchor()


## 次の憑依先アンカーを選んで移動を開始する
func _move_to_next_anchor() -> void:
	if _scene_mapper == null:
		push_error("DataPet: SceneMapper が設定されていません。")
		return

	# 利用可能なアンカーを取得（FormRegistry に登録済みかつ is_available のもの）
	var available: Array[PlacementAnchor] = _get_available_anchors()

	if available.is_empty():
		push_warning("DataPet: 利用可能なアンカーがありません。10秒後にリトライします。")
		_possession_timer.start(10.0)
		return

	# 直前のアンカー以外からランダムに選ぶ
	var candidates: Array[PlacementAnchor] = available.filter(
		func(a: PlacementAnchor) -> bool:
			return a.anchor_id != _last_anchor_id
	)

	# 候補が0件なら直前も含めて選ぶ（アンカーが1つしかない場合）
	if candidates.is_empty():
		candidates = available

	# ランダム選択
	candidates.shuffle()
	_target_anchor = candidates[0]

	print("DataPet: 次のアンカーへ移動。form_id=%s anchor_id=%s" % [
		_target_anchor.form_id,
		_target_anchor.anchor_id.substr(0, 8)
	])
	_set_state(PetState.MOVING_TO_ANCHOR)


## 利用可能なアンカーを返す
## FormRegistry に登録済み かつ is_available のもの
func _get_available_anchors() -> Array[PlacementAnchor]:
	var result: Array[PlacementAnchor] = []
	for anchor in _scene_mapper.get_all_anchors():
		if not anchor.is_available:
			continue
		# FormRegistry にシーンファイルが存在するフォームのみ対象
		if anchor.form_id == "":
			continue
		var scene: PackedScene = FormRegistry.get_form_scene(anchor.form_id)
		if scene != null:
			result.append(anchor)
	return result


## アンカーに到着したときに呼ばれる
func _start_possession() -> void:
	if _target_anchor == null:
		return

	_set_state(PetState.POSSESSING)
	print("DataPet: 到着。憑依を開始します。form_id=%s" % _target_anchor.form_id)
	possession_started.emit(_target_anchor)

	# 素体を非表示
	if _base_mesh != null:
		_base_mesh.visible = false
	else:
		visible = false

	# FormRegistry からシーンを取得
	var form_scene: PackedScene = FormRegistry.get_form_scene(_target_anchor.form_id)
	if form_scene == null:
		push_error("DataPet: FormRegistry にシーンが見つかりません。form_id=%s" % _target_anchor.form_id)
		_release_possession()
		return
	
	
	# フォームをワールド直下に配置
	_current_form = form_scene.instantiate() as FormBase
	_current_form_node = _current_form
	get_tree().root.add_child(_current_form)
	
	var anchor_pos: Vector3 = _target_anchor.get_world_position()
	var offset_y: float = -(_target_anchor.bounding_box.y / 2.0)
	_current_form.global_position = anchor_pos + Vector3(0, offset_y, 0)

	# 憑依アニメーション再生
	_current_form.enter_animation_finished.connect(_finish_possession, CONNECT_ONE_SHOT)
	await _current_form.play_enter_animation()


## 憑依アニメーション完了
func _finish_possession() -> void:
	_set_state(PetState.POSSESSED)
	_last_anchor_id = _target_anchor.anchor_id
	_target_anchor.mark_as_possessed()
	print("DataPet: 憑依完了。%d〜%d秒後に次へ移動します。" % [stay_duration_min, stay_duration_max])
	possession_completed.emit(_target_anchor)

	# idle アニメーション開始
	if _current_form:
		_current_form.play_idle_animation()

	# 滞在タイマーを開始（ランダムな時間後に次のアンカーへ）
	var stay_time: float = randf_range(stay_duration_min, stay_duration_max)
	_stay_timer.start(stay_time)


## 滞在タイマー終了 → 次のアンカーへ移動する
func _on_stay_timer_timeout() -> void:
	print("DataPet: 滞在終了。次のアンカーへ移動します。")
	_release_possession()


## 憑依を解除して次のアンカーへ移動する
func _release_possession() -> void:
	if _base_mesh != null:
		_base_mesh.visible = true
	if _state != PetState.POSSESSED and _state != PetState.POSSESSING:
		return

	_set_state(PetState.RELEASING)

	# アンカーを解放
	if _target_anchor:
		_target_anchor.mark_as_available()
		possession_released.emit(_target_anchor)

	# フォームを削除
	if _current_form_node and is_instance_valid(_current_form_node):
		_current_form_node.queue_free()
	_current_form = null
	_current_form_node = null

	# 素体を再表示してIDLE状態へ
	if _base_mesh != null:
		_base_mesh.visible = true
	else:
		visible = true

	_hover_base_y = position.y
	_set_state(PetState.IDLE)

	# 少し待ってから次のアンカーへ
	await get_tree().create_timer(1.5).timeout
	_move_to_next_anchor()


# ---------------------------------------------------------------------------
# 公開 API
# ---------------------------------------------------------------------------

## SceneMapper を設定する（GameManager から呼ぶ）
func set_scene_mapper(mapper: SceneMapper) -> void:
	_scene_mapper = mapper
	print("DataPet: SceneMapper 受信。%d秒後に最初の憑依を開始します。" % first_possession_delay)
	_possession_timer.start(first_possession_delay)


## 手動で次のアンカーへ移動させる（デバッグ用）
func trigger_next_possession() -> void:
	if _state == PetState.POSSESSED:
		_stay_timer.stop()
		_release_possession()
	elif _state == PetState.IDLE:
		_move_to_next_anchor()


## 現在の状態を返す
func get_state() -> PetState:
	return _state

# ---------------------------------------------------------------------------
# 内部ユーティリティ
# ---------------------------------------------------------------------------

func _set_state(new_state: PetState) -> void:
	_state = new_state
	print("DataPet: State → %s" % PetState.keys()[new_state])
	
# ---------------------------------------------------------------------------
# イベント受信 (EventBus から呼ばれるコールバック関数)
# ---------------------------------------------------------------------------
## 【機能】システム全体で何らかのアクション（タッチ、音声など）が起きた時に呼ばれる
## 引数 target_pet_id: どのペットに向けたイベントか（将来の複数ペット対応用）
## 引数 trigger: 何が起きたか（2 = タッチされた、3 = 滞在された 等の定義値）
## 引数 source_id: どこで起きたか（触られた家具の anchor_id など）
func _on_behavior_triggered(target_pet_id: String, trigger: int, source_id: String) -> void:
	
	# ---------------------------------------------------------
	# [パターンA: タッチ検知 (ON_TOUCH = 2)]
	# ---------------------------------------------------------
	if trigger == 2:
		# ★ ここで C4 ログを出力！
		DK.print_fixed("[C4] 成功: DataPetがタッチイベントを受信！")
		# もし現在、何かの家具に「憑依中(POSSESSED)」ならリアクションする
		if _state == PetState.POSSESSED and _current_form != null:
			
			# 自分が憑依している家具が触られたのかを確認する（一応の安全確認）
			if _target_anchor and _target_anchor.anchor_id == source_id:
				DK.print_fixed("DataPet: 憑依中の家具が触られた！")
	
	# ---------------------------------------------------------
	# [パターンB: 滞在検知 (ON_DWELL = 3)] ★ここを追加！
	# ---------------------------------------------------------
	elif trigger == 3:
		DK.print_fixed("[C4-Dwell] 成功: DataPetが滞在イベントを受信！")
		
		if _state == PetState.POSSESSED and _current_form != null:
			if _target_anchor and _target_anchor.anchor_id == source_id:
				DK.print_fixed("DataPet: ユーザーがそばで見守ってくれている！(喜ぶ)")
				
				# 【リアクション】嬉しくて横にモチッと潰れてプルプルする
				var tween = create_tween()
				var orig_scale = _current_form.scale
				
				# 横に広がり、縦に潰れる（モチッとする）
				tween.tween_property(_current_form, "scale", orig_scale * Vector3(1.3, 0.7, 1.3), 0.15)\
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				# バウンドしながら元の形に戻る
				tween.tween_property(_current_form, "scale", orig_scale, 0.4)\
					.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
