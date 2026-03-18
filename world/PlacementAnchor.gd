## PlacementAnchor.gd
## XRAnchor3D を継承することで、指定した tracker (UUID) の位置に自動同期される。
class_name PlacementAnchor
extends XRAnchor3D 

var fixed_transform: Transform3D = Transform3D.IDENTITY

# --- エクスポートプロパティ ---
@export var anchor_id: String = ""
@export var form_id: String = ""
@export var raw_label: String = ""
@export var bounding_box: Vector3 = Vector3.ONE

var is_possessed: bool = false
var is_available: bool = false
var _pos_logged: bool = false

# --- 内部ノード参照 ---
@onready var _form_slot: Node3D           = $FormSlot
@onready var _touch_area: Area3D          = $TouchArea
@onready var _touch_shape: CollisionShape3D = $TouchArea/CollisionShape3D
@onready var _dwell_marker: Marker3D      = $DwellAnchorMarker

# --- シグナル ---
signal anchor_ready(anchor: PlacementAnchor)

func _ready() -> void:
	# 親を辿って XROrigin3D がいるかチェック（デバッグ用）
	var origin = _find_xr_origin(self)
	if not origin:
		push_warning("PlacementAnchor: XROrigin3D の配下にありません。位置同期が失敗する可能性があります。")
	# tracker が設定されたら自動で有効化する
	if tracker != "":
		push_warning("PlacementAnchor: Tracker '%s' に同期中..." % tracker)
	
	_touch_area.collision_layer = 2
	_touch_area.collision_mask = 0
	emit_signal("anchor_ready", self)

func _find_xr_origin(node: Node) -> XROrigin3D:
	var p = node.get_parent()
	while p:
		if p is XROrigin3D:
			return p
		p = p.get_parent()
	return null
	
## バウンディングボックスに合わせて CollisionShape を更新
func setup_collision_from_bounding_box(box: Vector3) -> void:
	bounding_box = box
	if not _touch_shape.shape is BoxShape3D:
		_touch_shape.shape = BoxShape3D.new()
	_touch_shape.shape.size = box

func get_dwell_origin() -> Vector3:
	return _dwell_marker.global_position

func get_form_slot() -> Node3D:
	return _form_slot

func mark_as_possessed() -> void:
	is_possessed = true
	is_available = false

func mark_as_available() -> void:
	is_possessed = false
	is_available = (form_id != "")

func to_debug_string() -> String:
	return "PlacementAnchor[id=%s form=%s label=%s pos=%s]" % [
		anchor_id, form_id, raw_label, str(global_position)
	]
	
func setup_scene(entity: Object) -> void:
	print("PlacementAnchor: setup_scene() 呼ばれました。entity=%s" % str(entity))

	var labels: PackedStringArray = PackedStringArray()
	if entity.has_method("get_semantic_labels"):
		labels = entity.get_semantic_labels()
	raw_label = ",".join(labels)

	if "uuid" in entity:
		anchor_id = str(entity.uuid)
	else:
		anchor_id = str(get_instance_id())
		
	# バウンディングボックスを取得
	if entity.has_method("get_bounding_box_3d"):
		var aabb: AABB = entity.get_bounding_box_3d()
		if aabb.size != Vector3.ZERO:
			bounding_box = aabb.size
			setup_collision_from_bounding_box(bounding_box)
	elif entity.has_method("get_bounding_box_2d"):
		var rect: Rect2 = entity.get_bounding_box_2d()
		bounding_box = Vector3(rect.size.x, 0.1, rect.size.y)
		setup_collision_from_bounding_box(bounding_box)

	print("PlacementAnchor: label=%s anchor_id=%s" % [raw_label, anchor_id.substr(0, 8)])

	# SceneMapper に登録
	var scene_mapper := get_tree().root.find_child("SceneMapper", true, false) as SceneMapper
	if scene_mapper:
		scene_mapper.register_anchor_from_node(self, entity)
	else:
		push_warning("PlacementAnchor: SceneMapper が見つかりません。")
		
	var parent := get_parent()
	print("PlacementAnchor: parent class=%s parent_pos=%s self_pos=%s" % [
		parent.get_class() if parent else "null",
		str((parent as Node3D).global_position) if parent is Node3D else "N/A",
		str(global_position)
	])
	
func _process(_delta: float) -> void:
	if _pos_logged:
		return
	var parent := get_parent()
	if parent is Node3D:
		var pos: Vector3 = (parent as Node3D).global_position
		if pos != Vector3.ZERO:
			print("PlacementAnchor: 座標が更新されました！ label=%s pos=%s" % [raw_label, str(pos)])
			_pos_logged = true

## ★ 追加：親の XRAnchor3D から座標を取得する
func get_world_position() -> Vector3:
	# XRAnchor3D の子として維持されているので
	# global_position がそのままワールド座標
	return global_position
