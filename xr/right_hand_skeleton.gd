@tool
extends Skeleton3D

func _ready() -> void:
	_generate_bones()

func _generate_bones() -> void:
	var hand_suffix: String = "_R"
	
	# OpenXRが実際に探しているアンダースコア付きのベース名
	var base_bone_names = [
		"Palm", "Wrist",
		"Thumb_Metacarpal", "Thumb_Proximal", "Thumb_Distal", "Thumb_Tip",
		"Index_Metacarpal", "Index_Proximal", "Index_Intermediate", "Index_Distal", "Index_Tip",
		"Middle_Metacarpal", "Middle_Proximal", "Middle_Intermediate", "Middle_Distal", "Middle_Tip",
		"Ring_Metacarpal", "Ring_Proximal", "Ring_Intermediate", "Ring_Distal", "Ring_Tip",
		"Little_Metacarpal", "Little_Proximal", "Little_Intermediate", "Little_Distal", "Little_Tip"
	]

	# ベース名に "_R" を結合してボーンを作成する
	for base_name in base_bone_names:
		var b_name = base_name + hand_suffix
		if find_bone(b_name) == -1: # まだその骨がない場合だけ作成
			add_bone(b_name)
			print("左手のボーンを作成しました: ", b_name)
	
	# エディタの表示を更新するために通知
	notify_property_list_changed()
