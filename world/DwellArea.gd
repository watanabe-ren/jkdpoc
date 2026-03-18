## DwellArea.gd
## ユーザーが一定時間エリア内に留まったことを検知する。
## SceneMapper が PlacementAnchor の周辺に自動生成する。
##
## res://scripts/world/DwellArea.gd

class_name DwellArea
extends Node3D

# ---------------------------------------------------------------------------
# エクスポートプロパティ
# ---------------------------------------------------------------------------

## エリアID（SceneMapper が "dwell_" + anchor_id で設定）
@export var area_id: String = ""

## 紐付く PlacementAnchor の ID
@export var linked_anchor_id: String = ""

## 滞在検知に必要な時間（秒）
@export var required_dwell_time: float = 3.0

## 同一エリアで再発火するまでのクールダウン（秒）
@export var cooldown_time: float = 10.0

# ---------------------------------------------------------------------------
# 内部ノード参照
# ---------------------------------------------------------------------------

@onready var _detection_area: Area3D          = $DetectionArea
@onready var _collision_shape: CollisionShape3D = $DetectionArea/CollisionShape3D
@onready var _dwell_timer: Timer              = $DwellTimer

# ---------------------------------------------------------------------------
# 内部状態
# ---------------------------------------------------------------------------

var _is_user_inside: bool  = false
var _elapsed_time:   float = 0.0
var _is_cooling_down: bool = false
var _cooldown_elapsed: float = 0.0

## EventBus Autoload への参照（_ready で解決）
var _event_bus: Node = null

# ---------------------------------------------------------------------------
# シグナル
# ---------------------------------------------------------------------------

## 必要滞在時間を達成したときに発火
signal dwell_triggered(area: DwellArea)

## ユーザーがエリアに入ったときに発火
signal user_entered(area: DwellArea)

## ユーザーがエリアから出たときに発火
signal user_exited(area: DwellArea)

# ---------------------------------------------------------------------------
# ライフサイクル
# ---------------------------------------------------------------------------

func _ready() -> void:
	# EventBus Autoload への参照を解決
	_event_bus = get_node_or_null("/root/EventBus")

	# DetectionArea のシグナルを接続
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)

	# DwellTimer の設定
	_dwell_timer.one_shot = true
	_dwell_timer.wait_time = required_dwell_time
	_dwell_timer.timeout.connect(_on_dwell_timer_timeout)

	# CollisionShape に SphereShape3D を設定（Inspector で変更可）
	if _collision_shape.shape == null:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.6
		_collision_shape.shape = sphere

	# Layer 1 = ユーザー物理ボディ用レイヤー（PlayerBody）
	_detection_area.collision_layer = 0
	_detection_area.collision_mask  = 1


func _process(delta: float) -> void:
	# 滞在中は経過時間を更新
	if _is_user_inside and not _is_cooling_down:
		_elapsed_time += delta

	# クールダウン中はカウント
	if _is_cooling_down:
		_cooldown_elapsed += delta
		if _cooldown_elapsed >= cooldown_time:
			_is_cooling_down   = false
			_cooldown_elapsed  = 0.0

# ---------------------------------------------------------------------------
# 公開 API
# ---------------------------------------------------------------------------

## 現在ユーザーがエリア内にいるか
func is_occupied() -> bool:
	return _is_user_inside


## 滞在経過時間を返す（エリア外・クールダウン中は 0.0）
func get_elapsed_dwell_time() -> float:
	return _elapsed_time if _is_user_inside else 0.0

# ---------------------------------------------------------------------------
# 内部コールバック
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	# PlayerBody（CharacterBody3D）のみ対象
	if not body.is_in_group("player_body"):
		return
	if _is_cooling_down:
		return

	_is_user_inside = true
	_elapsed_time   = 0.0
	_dwell_timer.wait_time = required_dwell_time
	_dwell_timer.start()

	user_entered.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player_body"):
		return

	_is_user_inside = false
	_elapsed_time   = 0.0
	_dwell_timer.stop()

	user_exited.emit(self)


func _on_dwell_timer_timeout() -> void:
	if not _is_user_inside:
		return

	# 滞在時間達成 → イベントを発火
	dwell_triggered.emit(self)
	if _event_bus:
		# BehaviorTrigger.ON_DWELL = 3（BehaviorTrigger.gd の Value enum 順に対応）
		_event_bus.raw_dwell_triggered.emit(area_id, required_dwell_time)
		_event_bus.behavior_triggered.emit("", 3, linked_anchor_id)

	# クールダウン開始
	_is_cooling_down  = true
	_cooldown_elapsed = 0.0
	_elapsed_time     = 0.0
