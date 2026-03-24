# res://scripts/core/Main.gd
extends Node

# =========================================================
# ノード参照（シーン固有の名前 '%' を使用して堅牢に取得）
# =========================================================
@onready var touch_input_handler: TouchInputHandler = %TouchInputHandler
@onready var left_hand_collider: Area3D = %LeftHandCollider

# ※ 右手は後で実装・テストするため、今はコメントアウトしておきます
# @onready var right_hand_collider: Area3D = %RightHandCollider

# =========================================================
# ライフサイクル
# =========================================================
func _ready() -> void:
	print("=== DataPet VR アプリケーション起動 ===")
	
	# 1. 入力システムの初期化（左手センサーの接続）
	_init_input_system()
	
	# （※ 今後、SceneMapperの明示的な初期化呼び出しや、
	# 　　 DataPetのスポーン処理などをここに追加していきます）

# =========================================================
# 初期化メソッド
# =========================================================
func _init_input_system() -> void:
	# ハンドラーが正しく取得できているか（Nullポインタでないか）をチェック
	if is_instance_valid(touch_input_handler):
		
		# 第2引数（右手）に null を渡すことで、左手だけを安全に登録します
		touch_input_handler.set_hand_colliders(left_hand_collider, null)
		print("Main: TouchInputHandler に「左手コライダーのみ」を登録完了しました。")
		
	else:
		push_error("Main: 致命的エラー - TouchInputHandler が見つかりません！")
