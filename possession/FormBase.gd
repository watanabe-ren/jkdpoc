## FormBase.gd
## 全フォーム（椅子・机・クッション等）共通の基底スクリプト。
## 各 Form_XXX.tscn のルートノードにアタッチする。
##
## res://scripts/possession/FormBase.gd

class_name FormBase
extends Node3D

# ---------------------------------------------------------------------------
# プロパティ
# ---------------------------------------------------------------------------

## このフォームのID（例: "CHAIR"）
@export var form_id: String = ""

## GLBモデルを持つ MeshInstance3D への参照
@onready var _mesh: MeshInstance3D = null

## アニメーションプレイヤーへの参照（なければ null）
@onready var _anim_player: AnimationPlayer = $AnimPlayer if has_node("AnimPlayer") else null

# ---------------------------------------------------------------------------
# シグナル
# ---------------------------------------------------------------------------

signal enter_animation_finished()
signal exit_animation_finished()

# ---------------------------------------------------------------------------
# 公開 API
# ---------------------------------------------------------------------------

## 憑依開始アニメーションを再生する
func play_enter_animation() -> void:
	if _anim_player and _anim_player.has_animation("enter"):
		_anim_player.play("enter")
		await _anim_player.animation_finished
	enter_animation_finished.emit()


## 憑依解除アニメーションを再生する
func play_exit_animation() -> void:
	if _anim_player and _anim_player.has_animation("exit"):
		_anim_player.play("exit")
		await _anim_player.animation_finished
	exit_animation_finished.emit()


## 待機アニメーションを再生する
func play_idle_animation() -> void:
	if _anim_player and _anim_player.has_animation("idle"):
		_anim_player.play("idle")


## フォームを表示する
func show_form() -> void:
	visible = true


## フォームを非表示にする
func hide_form() -> void:
	visible = false
