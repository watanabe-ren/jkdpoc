## SceneMapper.gd
## Meta Scene API（OpenXRFbSceneManager）を利用して
##   1. 部屋スキャンデータの存在確認・取得（入室検知）
##   2. 空間オブジェクトのセマンティックラベル自動認識
##   3. PlacementAnchor / DwellArea の動的生成
## を行うユニット。
##
## 配置シーン : res://scenes/world/ 内の WorldRoot > SceneMapper (Node)
## スクリプト : res://scripts/world/SceneMapper.gd
##
## ■ 正しいアプローチ（公式ドキュメント準拠）
##   OpenXRFbSceneManager は openxr_fb_scene_anchor_created シグナルで
##   シーンノードと OpenXRFbSpatialEntity を渡す。
##   entity.get_semantic_labels() でラベルを取得し、
##   アンカーは XRAnchor3D の子として自動配置される。
##   OpenXRFbSpatialEntityQuery は使わない。
##
## ■ OpenXRFbSceneManager の Inspector 設定
##   Auto Create: ON（セッション開始時に自動でアンカーを生成）

class_name SceneMapper
extends Node

# ---------------------------------------------------------------------------
# エクスポートプロパティ
# ---------------------------------------------------------------------------

## PlacementAnchorRoot / DwellAreaRoot への参照（Inspector でドラッグ設定）
@export var _anchor_root: Node3D = null
@export var _dwell_root: Node3D  = null

## Scene API リクエスト後のタイムアウト（秒）
@export var scene_request_timeout: float = 10.0

## アンカー生成完了とみなすまでの無通信待機時間（秒）
## 最後のアンカーを受け取ってからこの時間後に scene_mapping_completed を発火する
@export var completion_wait_time: float = 2.0

## DwellArea を自動生成するか
@export var auto_create_dwell_areas: bool = true

## DwellArea のデフォルト必要滞在時間（秒）
@export var dwell_required_time: float = 3.0

# ★ DwellAreaのシーン（3Dオブジェクト）をプログラム内で生成できるようにロードしておく
# ※ "res://scenes/world/DwellArea.tscn" の部分は、ご自身のプロジェクトの実際のパスに合わせて書き換えてください！
@export var dwell_area_scene: PackedScene = preload("res://scenes/world/DwellArea.tscn")

# ---------------------------------------------------------------------------
# セマンティックラベル → form_id 変換テーブル
# ---------------------------------------------------------------------------
const LABEL_TO_FORM_ID: Dictionary = {
	"CHAIR":    "CHAIR",
	"COUCH":    "CUSHION",
	"DESK":     "DESK",
	"TABLE":    "DESK",
	"LAMP":     "LAMP",
	"PLANT":    "PLANT",
	"STORAGE":  "BOOKSHELF",
	"SHELF":    "BOOKSHELF",
}

# ---------------------------------------------------------------------------
# シーンパス
# ---------------------------------------------------------------------------
const PLACEMENT_ANCHOR_SCENE_PATH: String = "res://scenes/world/PlacementAnchor.tscn"
const DWELL_AREA_SCENE_PATH:        String = "res://scenes/world/DwellArea.tscn"

var _placement_anchor_scene: PackedScene = null
var _dwell_area_scene:        PackedScene = null

# ---------------------------------------------------------------------------
# 内部状態
# ---------------------------------------------------------------------------

var _scene_manager: OpenXRFbSceneManager = null
var _anchors: Array[PlacementAnchor] = []
var _anchor_map: Dictionary = {}

## タイムアウトタイマー（スキャンデータなし検知用）
var _timeout_timer: Timer = null

## 完了判定タイマー（最後のアンカーから一定時間後に completed を発火）
var _completion_timer: Timer = null

var _initialized: bool = false
var _event_bus: Node = null

# ---------------------------------------------------------------------------
# シグナル
# ---------------------------------------------------------------------------

signal scene_mapping_completed(anchor_count: int)
signal anchor_registered(anchor_id: String, form_id: String)
signal scene_scan_unavailable()

# ---------------------------------------------------------------------------
# ライフサイクル
# ---------------------------------------------------------------------------

func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus == null:
		push_warning("SceneMapper: EventBus が見つかりません。")

	# シーンをロード
	_placement_anchor_scene = load(PLACEMENT_ANCHOR_SCENE_PATH) as PackedScene
	_dwell_area_scene       = load(DWELL_AREA_SCENE_PATH) as PackedScene

	if _placement_anchor_scene == null:
		push_error("SceneMapper: PlacementAnchor.tscn のロードに失敗。パス: " + PLACEMENT_ANCHOR_SCENE_PATH)
	if _dwell_area_scene == null and auto_create_dwell_areas:
		push_warning("SceneMapper: DwellArea.tscn のロードに失敗。DwellArea を無効化します。")
		auto_create_dwell_areas = false

	# タイムアウトタイマー（スキャンデータなし検知）
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.wait_time = scene_request_timeout
	_timeout_timer.timeout.connect(_on_timeout)
	add_child(_timeout_timer)

	# 完了判定タイマー（最後のアンカーから一定時間後に発火）
	_completion_timer = Timer.new()
	_completion_timer.one_shot = true
	_completion_timer.wait_time = completion_wait_time
	_completion_timer.timeout.connect(_on_completion_timer_timeout)
	add_child(_completion_timer)


# ---------------------------------------------------------------------------
# 公開 API
# ---------------------------------------------------------------------------

func initialize(
	scene_manager: OpenXRFbSceneManager = null,
	anchor_root:   Node3D = null,
	dwell_root:    Node3D = null
) -> void:
	if _initialized:
		push_warning("SceneMapper: 既に初期化済みです。")
		return

	# ノード参照を解決
	_scene_manager = scene_manager if scene_manager else _find_scene_manager()
	if anchor_root:
		_anchor_root = anchor_root
	if dwell_root:
		_dwell_root = dwell_root
	if _anchor_root == null:
		_anchor_root = _find_node_in_tree("PlacementAnchorRoot")
	if _dwell_root == null:
		_dwell_root = _find_node_in_tree("DwellAreaRoot")

	if _scene_manager == null:
		push_error("SceneMapper: OpenXRFbSceneManager が見つかりません。")
		return
	if _anchor_root == null:
		push_error("SceneMapper: PlacementAnchorRoot が見つかりません。")
		return
	if _dwell_root == null and auto_create_dwell_areas:
		push_warning("SceneMapper: DwellAreaRoot が見つかりません。DwellArea を無効化します。")
		auto_create_dwell_areas = false
		
	# ★ SceneManager が持つシグナルを全部出力して確認する
	print("SceneMapper: SceneManager シグナル一覧:")
	for sig in _scene_manager.get_signal_list():
		print("  - " + sig["name"])
	
	print("SceneMapper: SceneManager プロパティ一覧:")
	for prop in _scene_manager.get_property_list():
		if not prop["name"].begins_with("_"):
			print("  - %s = %s" % [prop["name"], str(_scene_manager.get(prop["name"]))])
		
	# ★ シグナルの引数情報を確認する
	for sig in _scene_manager.get_signal_list():
		if sig["name"] == "openxr_fb_scene_anchor_created":
			print("SceneMapper: openxr_fb_scene_anchor_created 引数=%s" % str(sig["args"]))
			
	# ★ 正しいシグナルに接続（公式ドキュメント準拠）
	# openxr_fb_scene_anchor_created: アンカー1件ごとに発火
	if _scene_manager.has_signal("openxr_fb_scene_anchor_created"):
		_scene_manager.openxr_fb_scene_anchor_created.connect(_on_scene_anchor_created)
		print("SceneMapper: openxr_fb_scene_anchor_created に接続しました。")
	else:
		push_error("SceneMapper: openxr_fb_scene_anchor_created シグナルが見つかりません。")
		return

	# スキャンデータなし
	if _scene_manager.has_signal("openxr_fb_scene_data_missing"):
		_scene_manager.openxr_fb_scene_data_missing.connect(_on_scene_data_missing)

	# スキャン完了（request_scene_capture 後のコールバック）
	if _scene_manager.has_signal("openxr_fb_scene_capture_completed"):
		_scene_manager.openxr_fb_scene_capture_completed.connect(_on_scene_capture_completed)

	_initialized = true

	# アンカーの生成を開始
	# Auto Create が ON なら OpenXR セッション開始時に自動生成されるが、
	# 念のため手動でも呼ぶ
	_start_creating_anchors()


## 生成済みの全 PlacementAnchor を返す
func get_all_anchors() -> Array[PlacementAnchor]:
	return _anchors.duplicate()


## 特定 form_id の PlacementAnchor だけを返す
func get_anchors_by_form(form_id: String) -> Array[PlacementAnchor]:
	return _anchors.filter(func(a: PlacementAnchor) -> bool:
		return a.form_id == form_id
	)


## anchor_id から PlacementAnchor を取得
func get_anchor_by_id(anchor_id: String) -> PlacementAnchor:
	return _anchor_map.get(anchor_id, null)


## form_id が解決済みのアンカー数を返す
func get_recognized_anchor_count() -> int:
	return _anchors.filter(func(a: PlacementAnchor) -> bool:
		return a.is_available
	).size()


# ---------------------------------------------------------------------------
# アンカー生成の開始
# ---------------------------------------------------------------------------

func _start_creating_anchors() -> void:
	print("SceneMapper: アンカー生成を開始します。")
	_timeout_timer.start()

	if _scene_manager.has_method("create_scene_anchors"):
		var result = _scene_manager.create_scene_anchors()
		if result == OK:
			print("SceneMapper: create_scene_anchors() 呼び出し成功。シグナル待機中...")
		elif result == ERR_ALREADY_EXISTS:
			# Auto Create が ON または二重呼び出し
			# すでにアンカー生成中なのでシグナルを待つだけでよい
			print("SceneMapper: アンカーは生成済み/生成中です。シグナル待機に移行します。")
		else:
			push_warning("SceneMapper: create_scene_anchors() result=%d" % result)
	else:
		print("SceneMapper: create_scene_anchors() が見つかりません。Auto Create に依存します。")


# ---------------------------------------------------------------------------
# シグナルコールバック
# ---------------------------------------------------------------------------

## アンカー1件が生成されるたびに呼ばれる（メインのコールバック）
## scene_node: OpenXRFbSceneManager が生成したシーンノード（XRAnchor3D の子）
## spatial_entity: OpenXRFbSpatialEntity
func _on_scene_anchor_created(scene_node: Object, spatial_entity: Object) -> void:
	print("SceneMapper: ★★★ openxr_fb_scene_anchor_created 発火！ scene_node=%s" % str(scene_node))
	# タイムアウトをリセット（アンカーが来ているのでタイムアウトしない）
	_timeout_timer.stop()
	# 完了判定タイマーをリセット（最後のアンカーから数える）
	_completion_timer.start()

	# セマンティックラベルを取得
	var labels: PackedStringArray = PackedStringArray()
	if spatial_entity.has_method("get_semantic_labels"):
		labels = spatial_entity.get_semantic_labels()

	print("SceneMapper: anchor_created 受信。labels=%s" % str(labels))

	if labels.is_empty():
		print("SceneMapper: ラベルなしエンティティをスキップします。")
		return

	var form_id: String   = _resolve_form_id(Array(labels))
	var raw_label: String = ",".join(labels)

	# XRAnchor3D の座標を取得
	# scene_node の親が XRAnchor3D になっている
	var world_pos := Vector3.ZERO
	var world_basis := Basis.IDENTITY
	if scene_node is Node:
		var parent := (scene_node as Node).get_parent()
		if parent is Node3D:
			world_pos   = (parent as Node3D).global_position
			world_basis = (parent as Node3D).global_basis

	# バウンディングボックスを取得
	var bounding_box := Vector3(0.5, 0.5, 0.5)
	if spatial_entity.has_method("get_bounding_box_3d"):
		var aabb: AABB = spatial_entity.get_bounding_box_3d()
		if aabb.size != Vector3.ZERO:
			bounding_box = aabb.size
	elif spatial_entity.has_method("get_bounding_box_2d"):
		var rect: Rect2 = spatial_entity.get_bounding_box_2d()
		bounding_box = Vector3(rect.size.x, 0.1, rect.size.y)

	# anchor_id（UUID）
	var anchor_id: String = ""
	if "uuid" in spatial_entity:
		anchor_id = str(spatial_entity.uuid)
	if anchor_id == "":
		anchor_id = str(scene_node.get_instance_id())

	# 重複チェック
	if _anchor_map.has(anchor_id):
		print("SceneMapper: 重複アンカー anchor_id=%s をスキップ。" % anchor_id.substr(0, 8))
		return

	# PlacementAnchor を生成
	if _placement_anchor_scene == null:
		push_error("SceneMapper: PlacementAnchor.tscn が null です。")
		return

	var anchor: PlacementAnchor = _placement_anchor_scene.instantiate()
	anchor.name         = "PlacementAnchor_" + raw_label.replace(",", "_")
	anchor.anchor_id    = anchor_id
	anchor.form_id      = form_id
	anchor.raw_label    = raw_label
	anchor.bounding_box = bounding_box

	_anchor_root.add_child(anchor)
	# ★ ツリーに追加してから座標を設定する
	anchor.global_position = world_pos
	anchor.global_basis    = world_basis
	anchor.setup_collision_from_bounding_box(bounding_box)

	if form_id != "":
		anchor.mark_as_available()

	_anchors.append(anchor)
	_anchor_map[anchor_id] = anchor

	anchor_registered.emit(anchor_id, form_id)
	if _event_bus:
		_event_bus.anchor_registered.emit(anchor_id, form_id)

	print("SceneMapper: アンカー登録完了 label=%s → form=%s pos=%s box=%s" % [
		raw_label,
		form_id if form_id != "" else "未対応",
		str(world_pos),
		str(bounding_box)
	])

	if auto_create_dwell_areas and form_id != "":
		_create_dwell_area(anchor)


## スキャンデータが存在しない場合
func _on_scene_data_missing() -> void:
	_timeout_timer.stop()
	push_warning("SceneMapper: スキャンデータなし通知を受信。request_scene_capture() を試みます。")

	if _scene_manager.has_method("request_scene_capture"):
		print("SceneMapper: request_scene_capture() を呼び出します。")
		_scene_manager.request_scene_capture()
		# ★ ここでは scan_unavailable を発火しない
		# _on_scene_capture_completed() で結果を受け取る
	else:
		push_warning("SceneMapper: request_scene_capture() が見つかりません。")
		scene_scan_unavailable.emit()
		if _event_bus:
			_event_bus.scene_scan_unavailable.emit()


## request_scene_capture() が完了したとき
func _on_scene_capture_completed(success: bool) -> void:
	print("SceneMapper: scene_capture_completed success=%s" % str(success))
	if success:
		print("SceneMapper: スキャン完了。アンカー生成シグナルを待機します。")
		# ★ create_scene_anchors() の再呼び出しは不要
		# スキャン完了後は openxr_fb_scene_anchor_created が自動発火する
		_timeout_timer.start()  # タイムアウトを再開
	else:
		push_warning("SceneMapper: スキャンが失敗または中断されました。")
		scene_scan_unavailable.emit()
		if _event_bus:
			_event_bus.scene_scan_unavailable.emit()


## タイムアウト：一定時間アンカーが来なかった
func _on_timeout() -> void:
	if _anchors.is_empty():
		push_warning("SceneMapper: タイムアウト。アンカーが0件です。スキャンデータを確認してください。")
		scene_scan_unavailable.emit()
		if _event_bus:
			_event_bus.scene_scan_unavailable.emit()
	else:
		# アンカーは来ているが追加が止まった → 完了とみなす
		_emit_mapping_completed()


## 最後のアンカーから一定時間後に完了を発火
func _on_completion_timer_timeout() -> void:
	_emit_mapping_completed()


func _emit_mapping_completed() -> void:
	# 二重発火防止
	if not _completion_timer.is_stopped():
		_completion_timer.stop()
	if not _timeout_timer.is_stopped():
		_timeout_timer.stop()

	var count: int = _anchors.size()
	print("SceneMapper: マッピング完了。総数=%d 認識済み=%d" % [count, get_recognized_anchor_count()])
	scene_mapping_completed.emit(count)
	if _event_bus:
		_event_bus.scene_mapping_completed.emit(count)


# ---------------------------------------------------------------------------
# セマンティックラベル → form_id 解決
# ---------------------------------------------------------------------------

func _resolve_form_id(labels: Array) -> String:
	for label in labels:
		var upper: String = str(label).to_upper()
		if LABEL_TO_FORM_ID.has(upper):
			return LABEL_TO_FORM_ID[upper]
	return ""


# ---------------------------------------------------------------------------
# DwellArea 自動生成
# ---------------------------------------------------------------------------

func _create_dwell_area(anchor: PlacementAnchor) -> void:
	if _dwell_area_scene == null:
		return

	var dwell: DwellArea = _dwell_area_scene.instantiate()
	dwell.form_id = anchor.form_id
	dwell.name              = "DwellArea_" + anchor.anchor_id.substr(0, 8)
	dwell.area_id           = "dwell_" + anchor.anchor_id
	dwell.linked_anchor_id  = anchor.anchor_id
	dwell.required_dwell_time = dwell_required_time

	_dwell_root.add_child(dwell)

	# DwellAnchorMarker があればその位置、なければアンカー位置
	if anchor.has_node("DwellAnchorMarker"):
		dwell.global_position = anchor.get_node("DwellAnchorMarker").global_position
	else:
		dwell.global_position = anchor.global_position

	print("SceneMapper: DwellArea 生成 [%s] → anchor=%s" % [
		dwell.area_id, anchor.anchor_id.substr(0, 8)
	])


# ---------------------------------------------------------------------------
# ユーティリティ
# ---------------------------------------------------------------------------

func _find_scene_manager() -> OpenXRFbSceneManager:
	var result := _find_node_in_tree("OpenXRFbSceneManager")
	return result as OpenXRFbSceneManager if result else null


func _find_node_in_tree(node_name: String) -> Node:
	return _recursive_find_by_name(get_tree().root, node_name)


func _recursive_find_by_name(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child: Node in node.get_children():
		var result: Node = _recursive_find_by_name(child, target)
		if result:
			return result
	return null
	
## PlacementAnchor.setup_scene() から呼ばれる
func register_anchor_from_node(anchor: PlacementAnchor, _entity: Object) -> void:
	_timeout_timer.stop()
	_completion_timer.start()

	# form_id を解決
	var labels := anchor.raw_label.split(",")
	anchor.form_id = _resolve_form_id(Array(labels))

	if anchor.form_id != "":
		anchor.mark_as_available()

	# 重複チェック
	if _anchor_map.has(anchor.anchor_id):
		return

	# ★ XRAnchor3D から切り離さない
	# PlacementAnchor は XRAnchor3D の子のまま維持する
	# _anchor_root への移動は行わない

	_anchors.append(anchor)
	_anchor_map[anchor.anchor_id] = anchor
	
	anchor_registered.emit(anchor.anchor_id, anchor.form_id)
	if _event_bus:
		_event_bus.anchor_registered.emit(anchor.anchor_id, anchor.form_id)

	print("SceneMapper: アンカー登録完了 label=%s → form=%s" % [
		anchor.raw_label,
		anchor.form_id if anchor.form_id != "" else "未対応",
	])

	if auto_create_dwell_areas and anchor.form_id != "":
		_create_dwell_area(anchor)
		
