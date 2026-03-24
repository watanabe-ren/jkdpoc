# res://scripts/xr/XRRig.gd
extends XROrigin3D
## 【役割】
## プレイヤーの「頭（ヘッドセット）」と「手（コントローラー/ハンドトラッキング）」の
## 位置を現実に同期させ、MR空間（パススルー）の描画設定を行うクラス。
## さらに、自分の「手」をシステム（TouchInputHandler）に登録する役割も持つ。

@onready var xr_camera = $XRCamera3D
# 現実空間を透かして見せる（パススルー）ために、背景の描画設定を書き換えるための参照
@onready var _world_environment: WorldEnvironment = \
	get_tree().root.find_child("WorldEnvironment", true, false)

func _ready() -> void:
	# ---------------------------------------------------------
	# 1. OpenXRの初期化（本番のパススルー設定）
	# ---------------------------------------------------------
	# GodotとMeta QuestのOSを繋ぐインターフェースを取得
	var xr_interface: OpenXRInterface = \
		XRServer.find_interface("OpenXR") as OpenXRInterface

	if xr_interface == null:
		push_error("XRRig: OpenXRInterface が見つかりません")
		return

	if not xr_interface.initialize():
		push_error("XRRig: initialize() 失敗")
		return

	# Godotのメイン画面をVR用に描画するように指示する(これがないと、ヘッドセット内に映像が映らない)
	get_viewport().use_xr = true
	# QuestのOS側で「VRセッションが完全に開始された」瞬間に呼ばれるシグナルを接続
	xr_interface.session_begun.connect(_on_openxr_session_begun)
	# エンジンの初期化が落ち着くまで1フレーム待つ
	await get_tree().process_frame
	# デバッグコンソール（腕の板）が、常にプレイヤーのカメラを基準に
	# 描画されるように設定する
	DK.set_current_camera(xr_camera)
	
	# ---------------------------------------------------------
	# 2. 入力システムへの登録（依存性注入）
	# ---------------------------------------------------------
	# 自分の手（ハードウェア）のポインタを、システム（ソフトウェア）に渡す
	_register_hands_to_system()
	
## 【機能】自分の手を「物理的な干渉ができる物体」としてシステムに登録する
func _register_hands_to_system() -> void:
	var touch_input = get_tree().root.find_child("TouchInputHandler", true, false)
	if not touch_input:
		DK.print_error("❌ XRRig: TouchInputHandlerが見つかりません")
		return

	# 左手の取得
	var left_hand_sensor = get_node_or_null("%LeftHandCollider")
	# 右手の取得
	var right_hand_sensor = get_node_or_null("%RightHandCollider")
	
	# 取得したすべてのセンサーを配列にまとめる
	var all_hands: Array[Area3D] = [
		left_hand_sensor, 
		right_hand_sensor
	]

	# ★ 本番環境でも必須：手が家具を触れるように物理レイヤーを強制設定
	# Layer 2: 自分は「手」である / Mask 8: 「家具」を探す
	var valid_hands: Array[Area3D] = []

	# ループ処理で、存在するセンサーすべてにレイヤー(2)とマスク(8)を一括設定
	for hand in all_hands:
		if is_instance_valid(hand):
			hand.collision_layer = 2
			hand.collision_mask = 8
			valid_hands.append(hand)

	# 関所に配列ごと渡す
	if touch_input.has_method("set_hand_colliders"):
		touch_input.set_hand_colliders(valid_hands)
		DK.print_fixed("[C1] 成功: 両手（" + str(valid_hands.size()) + "個のセンサー）を登録しました")

func _on_openxr_session_begun() -> void:
	_enable_passthrough(true)


func _enable_passthrough(enable: bool) -> void:
	var xr_interface: OpenXRInterface = \
		XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		return

	if enable and xr_interface.get_supported_environment_blend_modes()\
			.has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		get_viewport().transparent_bg = true
		if _world_environment and _world_environment.environment:
			_world_environment.environment.background_mode = Environment.BG_COLOR
			_world_environment.environment.background_color = Color(0, 0, 0, 0)
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		get_viewport().transparent_bg = false
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
