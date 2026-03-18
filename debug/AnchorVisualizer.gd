## AnchorVisualizer.gd
## Meta Scene API で読み取った全アンカーの
## バウンディングボックスとラベルを VR 空間に表示するデバッグノード。
##
## res://scripts/debug/AnchorVisualizer.gd
##
## ■ ノード構成（AnchorVisualizer.tscn）
##   AnchorVisualizer (Node3D)  ← このスクリプト
##   （子ノードはすべてコードで動的生成）
##
## ■ 呼び出し方（GameManager._spawn_pet() 内）
##   var vis = preload("res://scenes/debug/AnchorVisualizer.tscn").instantiate()
##   get_tree().root.add_child(vis)
##   vis.setup(_scene_mapper)

class_name AnchorVisualizer
extends Node3D

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

## form_id ごとのボックスカラー
const FORM_COLORS: Dictionary = {
	"CHAIR":     Color(0.2, 0.8, 0.2, 0.15),  # 緑
	"DESK":      Color(0.2, 0.4, 1.0, 0.15),  # 青
	"CUSHION":   Color(1.0, 0.4, 0.8, 0.15),  # ピンク
	"PLANT":     Color(0.0, 1.0, 0.4, 0.15),  # 黄緑
	"LAMP":      Color(1.0, 1.0, 0.0, 0.15),  # 黄
	"BOOKSHELF": Color(0.8, 0.4, 0.1, 0.15),  # 茶
}
const DEFAULT_COLOR: Color = Color(0.7, 0.7, 0.7, 0.4)  # 未対応はグレー

# ---------------------------------------------------------------------------
# 内部状態
# ---------------------------------------------------------------------------

var _scene_mapper: SceneMapper = null
var _camera: XRCamera3D = null
## ラベルノードの配列（毎フレームカメラに向ける）
var _labels: Array[Label3D] = []

# AnchorVisualizer.gd に追加
var _box_nodes: Array[MeshInstance3D] = []  # バウンディングボックスノード配列
var _anchors_ref: Array[PlacementAnchor] = []  # アンカー参照を保持

# ---------------------------------------------------------------------------
# 公開 API
# ---------------------------------------------------------------------------

## GameManager._spawn_pet() から呼ぶ。
func setup(scene_mapper: SceneMapper) -> void:
	_scene_mapper = scene_mapper
	_camera = get_tree().root.find_child("XRCamera3D", true, false) as XRCamera3D

	var anchors: Array[PlacementAnchor] = _scene_mapper.get_all_anchors()

	if anchors.is_empty():
		push_warning("AnchorVisualizer: アンカーが0件です。")
		return

	for anchor in anchors:
		# ★ 各アンカーの座標をログ出力
		print("AnchorVisualizer: anchor form=%s global_pos=%s world_pos=%s" % [
			anchor.form_id,
			str(anchor.global_position),
			str(anchor.get_world_position())
		])
		_build_anchor_visual(anchor)

	print("AnchorVisualizer: %d 件のアンカーを可視化しました。" % anchors.size())

# ---------------------------------------------------------------------------
# ライフサイクル
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# ラベルをカメラに向ける
	if _camera:
		for label in _labels:
			if is_instance_valid(label):
				label.look_at(
					Vector3(_camera.global_position.x, label.global_position.y, _camera.global_position.z),
					Vector3.UP
				)

	# ★ 毎フレームアンカーの座標を更新する
	for i in range(min(_anchors_ref.size(), _box_nodes.size())):
		var anchor := _anchors_ref[i]
		var box_node := _box_nodes[i]
		if is_instance_valid(anchor) and is_instance_valid(box_node):
			var pos := anchor.get_world_position()
			if pos != Vector3.ZERO:
				box_node.global_position = pos
				_labels[i].global_position = pos + Vector3(0, box_node.mesh.size.y / 2.0 + 0.15, 0)


# ---------------------------------------------------------------------------
# アンカー1件のビジュアルを生成する
# ---------------------------------------------------------------------------

func _build_anchor_visual(anchor: PlacementAnchor) -> void:
	
	if anchor.form_id == "":
		return
	
	var color: Color = FORM_COLORS.get(anchor.form_id, DEFAULT_COLOR)
	
	var world_pos: Vector3 = anchor.get_world_position()
	# --- バウンディングボックス ---
	var box_mesh := BoxMesh.new()
	box_mesh.size = anchor.bounding_box if anchor.bounding_box != Vector3.ZERO \
		else Vector3(0.5, 0.5, 0.5)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	box_mesh.material = mat

	var box_node := MeshInstance3D.new()
	box_node.mesh = box_mesh
	# ★ add_child() を先に行う（ツリーに入れてから global_position を設定）
	add_child(box_node)
	box_node.global_position = world_pos
	box_node.global_basis    = anchor.global_basis

	# --- ラベル ---
	var label := Label3D.new()
	label.text          = _make_label_text(anchor)
	label.font_size     = 10
	label.modulate      = color
	label.no_depth_test = true
	label.double_sided  = true
	label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED

	# ★ add_child() を先に行う
	add_child(label)
	var box_half_y: float = box_mesh.size.y / 2.0
	label.global_position = world_pos + Vector3(0, box_half_y + 0.15, 0)  # ← 変更
	_anchors_ref.append(anchor)   # ← 追加
	_box_nodes.append(box_node)   # ← 追加
	_labels.append(label)


func _make_label_text(anchor: PlacementAnchor) -> String:
	var form := anchor.form_id   if anchor.form_id   != "" else "未対応"
	var raw  := anchor.raw_label if anchor.raw_label != "" else "unknown"
	var id   := anchor.anchor_id.substr(0, 8)
	var pos  := anchor.global_position
	var box  := anchor.bounding_box
	return (
		"[%s]  %s\n" % [form, raw]
		+ "id: %s\n" % id
		+ "pos: (%.2f, %.2f, %.2f)\n" % [pos.x, pos.y, pos.z]
		+ "box: (%.2f, %.2f, %.2f)" % [box.x, box.y, box.z]
	)
