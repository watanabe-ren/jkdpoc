# res://scripts/input/TouchInputHandler.gd
class_name TouchInputHandler
extends Node
## 【役割】
## 物理エンジン（Area3D）の接触判定を監視し、
## 手の震えなどによる連続発火（チャタリング）を防ぎつつ、
## 1回の「タッチ」という意味のあるイベントに変換してシステム全体に通知するクラス。

# ---------------------------------------------------------
# 公開プロパティ
# ---------------------------------------------------------
## 連続タッチを防ぐクールダウン（秒）。
## 一度触ってから、次に同じ家具を触ったと判定されるまでの無効時間。
@export var cooldown_time: float = 1.0

# ---------------------------------------------------------
# 内部状態
# ---------------------------------------------------------
## システムに登録された「手」のセンサー（Area3D）のリスト。
## 通常は左手と右手の最大2つが格納される。
var _hand_colliders: Array[Area3D] = []
## 現在監視している現実の家具（アンカー）のリスト。
var _registered_anchors: Array[PlacementAnchor] = []
## チャタリング防止用のタイマー管理辞書。
## 構造: { "アンカーのID": 次にタッチが許可される時刻(ミリ秒) }
var _cooldowns: Dictionary = {}

# ---------------------------------------------------------
# API (XRRig や GameManager から呼ばれる)
# ---------------------------------------------------------
## 【機能】プレイヤーの「手」をシステムに登録する
## 呼ばれるタイミング: アプリ起動時（XRRigの_ready内など）
func set_hand_colliders(colliders: Array[Area3D]) -> void:
	# 既存の登録をリセット
	_hand_colliders.clear()
	for col in colliders:
		if is_instance_valid(col):
			_hand_colliders.append(col)

## 【機能】空間スキャンで生成された「家具」を監視対象に追加する
## 呼ばれるタイミング: 部屋のスキャン完了時（GameManagerから一括で呼ばれる）
func register_anchor(anchor: PlacementAnchor) -> void:
	# 既に登録済みの家具なら何もしない（二重登録防止）
	if anchor in _registered_anchors: return
	# 監視リストに追加
	_registered_anchors.append(anchor)
	# 家具の当たり判定ボックス（TouchArea）を取得
	var touch_area: Area3D = anchor.get_node_or_null("TouchArea")
	if touch_area:
		# is_connected で既にシグナルが繋がっていないかを確認（安全策）
		if not touch_area.area_entered.is_connected(_on_touch_area_entered):
			# 家具のエリアに何かが侵入したら `_on_touch_area_entered` を呼ぶように結線する。
			# bind(anchor) を使うことで、関数が呼ばれた時に「どの家具が触られたか」を引数として渡せる。
			touch_area.area_entered.connect(_on_touch_area_entered.bind(anchor))
		# この家具のクールダウンタイマーを初期化（最初は0なので、すぐに触れる状態）
		_cooldowns[anchor.anchor_id] = 0

## 【機能】監視対象の「家具」をリストから外し、判定を止める
## 呼ばれるタイミング: 家具が消滅した時や、シーン切り替え時
func unregister_anchor(anchor: PlacementAnchor) -> void:
	# リストの中に存在する場合のみ処理する
	if anchor in _registered_anchors:
		# リストとクールダウン管理から削除
		_registered_anchors.erase(anchor)
		_cooldowns.erase(anchor.anchor_id)
		
		var touch_area: Area3D = anchor.get_node_or_null("TouchArea")
		# 結線されていたシグナル（監視）を切り離し、無駄な処理が走らないようにする
		if touch_area and touch_area.area_entered.is_connected(_on_touch_area_entered):
			touch_area.area_entered.disconnect(_on_touch_area_entered)

# ---------------------------------------------------------
# イベントハンドリング (関所のコアロジック)
# ---------------------------------------------------------
## 【機能】家具の当たり判定に、何らかの物体が侵入した瞬間に呼ばれる
## 引数 hit_area: 侵入してきた物体（手など）
## 引数 anchor: 触られた家具のデータ
func _on_touch_area_entered(hit_area: Area3D, anchor: PlacementAnchor) -> void:
	# [ステップ1: 認証] 
	# 侵入してきた物体が、事前に set_hand_colliders で登録された「手」であるか確認。
	# 頭やペット自身など、手以外のものがぶつかった場合はここで弾く。
	if not hit_area in _hand_colliders:
		return
		
	# [ステップ2: ノイズ除去（チャタリング防止）]
	# VRでは手が微細に震えるため、1回のタッチでこの関数が数十回呼ばれることがある。
	# そのため、前回のタッチから指定した秒数（cooldown_time）が経過しているかを確認する。
	var current_time = Time.get_ticks_msec()
	var next_allowed_time = _cooldowns.get(anchor.anchor_id, 0)
	
	# まだクールダウン期間中なら、今回のタッチはノイズとして無視する
	if current_time < next_allowed_time:
		return 
		
	# [ステップ3: 状態の更新]
	# 今回は有効なタッチだったと判定し、次にこの家具を触れるようになる時刻を更新する。
	# (秒をミリ秒に変換するため 1000 を掛ける)
	_cooldowns[anchor.anchor_id] = current_time + int(cooldown_time * 1000)
	
	# [ステップ4: グローバルへの通知]
	# 物理判定とノイズ除去という面倒な処理を終えた「純粋なタッチイベント」として、
	# アプリ全体（EventBus）にブロードキャスト（一斉送信）する。
	DK.print_fixed("[C3] 🌟 タッチ検知 -> " + anchor.form_id)
	
	if EventBus.has_signal("behavior_triggered"):
		# 送信するデータ:
		# "pet_001" : ターゲットとするペットのID（将来の拡張用）
		# 2 : トリガーの種類（BehaviorTrigger.ON_TOUCH を表す整数値）
		# anchor.anchor_id : 触られた家具のID（誰が触られたか）
		EventBus.behavior_triggered.emit("pet_001", 2, anchor.anchor_id)
