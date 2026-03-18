## RoomScanDetector.gd
## 部屋入室検知の入口ユニット。
## Meta Scene API（OpenXRFbSceneManager）のスキャンデータの有無を確認し、
## ・スキャンあり → SceneMapper に初期化を委譲
## ・スキャンなし → OS の Space Setup へ誘導する UI を表示
## という振り分けを行う。
##
## 配置: WorldRoot > RoomScanDetector (Node)
## res://scripts/world/RoomScanDetector.gd
##
## ■ GameManager からの呼び出し順
##   1. RoomScanDetector.start_detection()
##   2. room_entered シグナルを受けたら通常ゲームフローへ
##   3. scan_unavailable シグナルを受けたら UI でユーザーに案内

class_name RoomScanDetector
extends Node

# ---------------------------------------------------------------------------
# エクスポートプロパティ
# ---------------------------------------------------------------------------

## Scene Manager への参照（省略時は自動検索）
@export var scene_manager_path: NodePath = NodePath("")

## SceneMapper への参照（省略時は自動検索）
@export var scene_mapper_path: NodePath = NodePath("")

## XROrigin3D への参照（OpenXR 初期化完了の確認に使用）
@export var xr_origin_path: NodePath = NodePath("")

## OpenXR 初期化完了を待つ最大時間（秒）
@export var xr_init_timeout: float = 8.0

# ---------------------------------------------------------------------------
# 内部状態
# ---------------------------------------------------------------------------

## 検知フェーズ
enum DetectionPhase {
	IDLE,           ## 未開始
	WAITING_XR,     ## OpenXR 初期化待ち
	REQUESTING,     ## Scene API へリクエスト中
	MAPPING,        ## SceneMapper が動作中
	COMPLETED,      ## 完了
	UNAVAILABLE,    ## スキャンデータなし
}

var _phase: DetectionPhase = DetectionPhase.IDLE
var _xr_init_elapsed: float = 0.0
var _xr_ready: bool = false

var _scene_mapper: SceneMapper = null
var _scene_manager: OpenXRFbSceneManager = null
var _xr_origin: XROrigin3D = null

# ---------------------------------------------------------------------------
# シグナル
# ---------------------------------------------------------------------------

## スキャンデータが有効で、アンカー生成が完了した（入室成功）
signal room_entered(anchor_count: int)

## スキャンデータが存在しない（Space Setup 誘導が必要）
signal scan_unavailable()

## 各フェーズが変化したときにデバッグ等で利用可能
signal detection_phase_changed(phase: DetectionPhase)

# ---------------------------------------------------------------------------
# ライフサイクル
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_process(false)  # start_detection() が呼ばれるまで処理しない


func _process(delta: float) -> void:
	match _phase:
		DetectionPhase.WAITING_XR:
			_wait_for_xr(delta)


# ---------------------------------------------------------------------------
# 公開 API
# ---------------------------------------------------------------------------

## 部屋入室検知を開始する。GameManager._ready() から呼ぶ。
func start_detection() -> void:
	if _phase != DetectionPhase.IDLE:
		push_warning("RoomScanDetector: すでに開始済みです。")
		return

	print("RoomScanDetector: 入室検知を開始します。")
	_resolve_node_references()
	_set_phase(DetectionPhase.WAITING_XR)
	set_process(true)


## 現在のフェーズを返す（UI や GameManager の条件分岐に使用）。
func get_phase() -> DetectionPhase:
	return _phase


## アンカーが存在しない場合に手動でリトライする（UIボタンなどから呼ぶ）。
func retry() -> void:
	if _phase == DetectionPhase.UNAVAILABLE:
		_set_phase(DetectionPhase.IDLE)
		start_detection()

# ---------------------------------------------------------------------------
# 内部処理
# ---------------------------------------------------------------------------

func _wait_for_xr(delta: float) -> void:
	_xr_init_elapsed += delta

	# OpenXRInterface が初期化済みかどうかで XR 準備完了を判定する。
	# XRServer.get_tracker() はトラッカーパス文字列を引数に取るインスタンスメソッドであり、
	# static では呼べないため使用しない。
	var xr_interface: OpenXRInterface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface != null and xr_interface.is_initialized():
		_on_xr_ready()
		return

	# タイムアウト
	if _xr_init_elapsed >= xr_init_timeout:
		push_warning("RoomScanDetector: OpenXR 初期化タイムアウト。Scene API リクエストを試みます。")
		_on_xr_ready()


func _on_xr_ready() -> void:
	print("RoomScanDetector: OpenXR 準備完了。session_begun を待機します。")
	set_process(false)
	_set_phase(DetectionPhase.REQUESTING)
	
	var xr_interface: OpenXRInterface = \
		XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		push_error("RoomScanDetector: OpenXRInterface が null")
		return
	
	if xr_interface.is_initialized():
		print("RoomScanDetector: セッション確立済み。直接 mapping を開始します。")
		# 1フレーム待ってから呼ぶ（XR_ERROR_HANDLE_INVALID 回避）
		call_deferred("_start_scene_mapping")
	else:
		xr_interface.session_begun.connect(_on_session_begun, CONNECT_ONE_SHOT)
		
func _on_session_begun() -> void:
	print("RoomScanDetector: session_begun 受信。")
	await get_tree().create_timer(3.0).timeout
	_start_scene_mapping()
	
func _start_scene_mapping() -> void:
	if _scene_mapper == null:
		push_error("RoomScanDetector: SceneMapper が見つかりません。")
		_set_phase(DetectionPhase.UNAVAILABLE)
		scan_unavailable.emit()
		return
	
	_scene_mapper.scene_mapping_completed.connect(_on_scene_mapping_completed)
	_scene_mapper.scene_scan_unavailable.connect(_on_scene_scan_unavailable)
	_set_phase(DetectionPhase.MAPPING)
	_scene_mapper.initialize(_scene_manager)

func _on_scene_mapping_completed(anchor_count: int) -> void:
	print("RoomScanDetector: 入室検知完了。アンカー数=%d" % anchor_count)
	_set_phase(DetectionPhase.COMPLETED)
	room_entered.emit(anchor_count)


func _on_scene_scan_unavailable() -> void:
	push_warning("RoomScanDetector: スキャンデータなし。Space Setup を案内してください。")
	_set_phase(DetectionPhase.UNAVAILABLE)
	scan_unavailable.emit()


func _set_phase(new_phase: DetectionPhase) -> void:
	_phase = new_phase
	detection_phase_changed.emit(new_phase)
	print("RoomScanDetector: Phase → %s" % DetectionPhase.keys()[new_phase])


## ノード参照を解決する。
func _resolve_node_references() -> void:
	# SceneMapper
	if scene_mapper_path != NodePath(""):
		_scene_mapper = get_node(scene_mapper_path) as SceneMapper
	if _scene_mapper == null:
		_scene_mapper = _find_in_tree("SceneMapper") as SceneMapper

	# OpenXRFbSceneManager
	if scene_manager_path != NodePath(""):
		_scene_manager = get_node(scene_manager_path) as OpenXRFbSceneManager
	if _scene_manager == null:
		_scene_manager = _find_in_tree_by_class("OpenXRFbSceneManager") as OpenXRFbSceneManager

	# XROrigin3D
	if xr_origin_path != NodePath(""):
		_xr_origin = get_node(xr_origin_path) as XROrigin3D
	if _xr_origin == null:
		_xr_origin = _find_in_tree_by_class("XROrigin3D") as XROrigin3D

	print("RoomScanDetector: SceneMapper=%s  SceneManager=%s  XROrigin=%s" % [
		str(_scene_mapper != null),
		str(_scene_manager != null),
		str(_xr_origin != null)
	])


func _find_in_tree(node_name: String) -> Node:
	return get_tree().root.find_child(node_name, true, false)


func _find_in_tree_by_class(class_name_str: String) -> Node:
	return _recursive_find_by_class(get_tree().root, class_name_str)


func _recursive_find_by_class(node: Node, class_name_str: String) -> Node:
	if node.is_class(class_name_str):
		return node
	for child: Node in node.get_children():
		var result: Node = _recursive_find_by_class(child, class_name_str)
		if result:
			return result
	return null
	
