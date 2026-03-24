# res://scenes/ui/DebugConsole.gd
extends Node3D

@export var scroll_speed: float = 15.0

# 階層が変わっても絶対に取得できるように「%（シーン固有の名前）」を使います
# ※事前にシーンツリーで LogText, SubViewport, BoardMesh を右クリックして
# 「シーン固有の名前としてアクセス」をオンにしておいてください。
@onready var log_text: RichTextLabel = %LogText
@onready var sub_viewport: SubViewport = %SubViewport
@onready var board_mesh: MeshInstance3D = %BoardMesh

const MAX_LINES: int = 30
@export var right_controller: XRController3D

func _ready() -> void:
	# 自身をDKシングルトンに登録
	DK.register_console(self)
	
	# エンジンの描画準備が整うのを「1フレーム」だけ待つ
	await get_tree().process_frame
	
	# 
	# -------------------------------------------------------------
	var safe_material = StandardMaterial3D.new()
	safe_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # 暗闇でも光らせる
	safe_material.albedo_texture = sub_viewport.get_texture() # 確実なポインタ渡し！
	board_mesh.set_surface_override_material(0, safe_material)
	# -------------------------------------------------------------

	# 起動時のメッセージ
	log_text.text += "[color=green]=== System Ready ===[/color]\n"

func _process(delta: float) -> void:
	if not right_controller:
		return
		
	# 右コントローラーの「プライマリ・ジョイスティック」の値を直接取得
	# Vector2(x, y) が返ってきます
	var joystick_vector = right_controller.get_vector2("primary")
	
	# Y軸（上下）を取り出す
	var scroll_y = joystick_vector.y
	
	# デッドゾーン（遊び）を考慮して 0.1 以上の入力で反応
	if abs(scroll_y) > 0.1:
		var scrollbar = log_text.get_v_scroll_bar()
		log_text.scroll_following = false # 手動操作時は自動追従オフ
		
		# スクロール実行（scroll_speedはインスペクターで調整してください）
		scrollbar.value += scroll_y * scroll_speed
		
	# Aボタン（ax_button）が押されたら自動追従をオンに戻す
	if right_controller.is_button_pressed("ax_button"):
		log_text.scroll_following = true
		
## 外部からログを追加するための関数
func print_log(message: String, color: String = "white") -> void:
	print("★★★ 板にログが届いた！: ", message)
	if not is_instance_valid(log_text): return;
	
	# 時間を取得してプレフィックスをつける
	var time_dict = Time.get_time_dict_from_system()
	var time_str = "[color=gray][%02d:%02d:%02d][/color] " % [time_dict.hour, time_dict.minute, time_dict.second]
	
	# RichTextLabelのBBCode形式でテキストを追加
	log_text.append_text(time_str + "[color=" + color + "]" + message + "[/color]\n")
	
	# 行数が多くなりすぎたら古いものを削除（簡易的な実装）
	var line_count = log_text.get_line_count()
	if line_count > MAX_LINES:
		# 先頭の1行分を大雑把に削除する（より厳密には配列で管理する方が綺麗です）
		var current_text = log_text.text
		var first_newline_idx = current_text.find("\n")
		if first_newline_idx != -1:
			log_text.text = current_text.substr(first_newline_idx + 1)
