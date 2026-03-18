# res://scripts/possession/Form_Bookshelf.gd
class_name Form_Shelf
extends FormBase

@onready var _model: Node3D = $ShelfModel

func _ready() -> void:
	form_id = "BOOKSHELF"
	visible = false


func play_enter_animation() -> void:
	print("Form_Bookshelf: enter_animation 開始")
	await get_tree().process_frame
	visible = true
	scale = Vector3.ZERO

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.5)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_BACK)
	await tween.finished

	print("Form_Bookshelf: enter_animation 完了")
	enter_animation_finished.emit()


func play_idle_animation() -> void:
	_start_idle_rumble()


# 本棚固有のidle：小刻みに振動
func _start_idle_rumble() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "rotation_degrees:z", 1.5, 0.1)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation_degrees:z", -1.5, 0.1)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
