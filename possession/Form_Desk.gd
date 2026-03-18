class_name Form_Desk
extends FormBase

@onready var _desk_model: Node3D = $DeskModel

func _ready() -> void:
	form_id = "DESK"
	visible = false


func play_enter_animation() -> void:
	print("Form_Desk: enter_animation 開始")
	await get_tree().process_frame
	visible = true
	scale = Vector3.ZERO

	# GLBにenterアニメーションがある場合
	var anim := _desk_model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation("enter"):
		anim.play("enter")
		await anim.animation_finished
	else:
		# アニメーションがなければTweenでスケールアニメーション
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3.ONE, 0.5)\
			.set_ease(Tween.EASE_OUT)\
			.set_trans(Tween.TRANS_BACK)
		await tween.finished

	print("Form_Desk: enter_animation 完了")  # ← 追加
	enter_animation_finished.emit()


func play_idle_animation() -> void:
	var anim := _desk_model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim and anim.has_animation("idle"):
		anim.play("idle")
	else:
		_start_idle_sway()


func _start_idle_sway() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "rotation_degrees:y", 3.0, 1.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation_degrees:y", -3.0, 1.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
