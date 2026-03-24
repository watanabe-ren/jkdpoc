# res://scripts/input/DwellInputHandler.gd
class_name DwellInputHandler
extends Node
## 【役割】
## 空間の「滞在センサー（DwellArea）」を束ねる関所。
## センサーが「ユーザーが一定時間滞在した」と判断した結果を受け取り、
## システム共通の「イベント」に翻訳してグローバルに配信するクラス。

# ---------------------------------------------------------
# 内部状態
# ---------------------------------------------------------
## 監視対象となっている滞在センサーのリスト。
var _registered_dwells: Array[Node] = []

# ---------------------------------------------------------
# API (GameManager から呼ばれる設定関数)
# ---------------------------------------------------------

## 【機能】空間スキャン等で生成された「滞在センサー」を監視対象に追加する
## 引数 dwell_area: 登録するセンサー（DwellArea.gd がアタッチされたノード）
func register_dwell_area(dwell_area: Node) -> void:
	# 既に登録済みのセンサーなら何もしない（二重登録防止）
	if dwell_area in _registered_dwells: return
	
	# 監視リストに追加
	_registered_dwells.append(dwell_area)
	
	# センサー（DwellArea）が独自にタイマー計算を終え、
	# 「滞在完了（dwell_triggered）」シグナルを出した時だけ、自分の関数を呼ぶように結線する。
	if dwell_area.has_signal("dwell_triggered"):
		if not dwell_area.dwell_triggered.is_connected(_on_dwell_triggered):
			# bind を使わずとも、DwellArea 側がシグナル引数として自分自身を渡してくる設計を想定
			dwell_area.dwell_triggered.connect(_on_dwell_triggered)
			
	DK.print_fixed("[Dwell] 登録完了: " + str(dwell_area.name))

## 【機能】監視対象のセンサーをリストから外し、判定を止める
func unregister_dwell_area(dwell_area: Node) -> void:
	if dwell_area in _registered_dwells:
		_registered_dwells.erase(dwell_area)
		
		# 結線されていたシグナル（監視）を切り離す
		if dwell_area.has_signal("dwell_triggered"):
			if dwell_area.dwell_triggered.is_connected(_on_dwell_triggered):
				dwell_area.dwell_triggered.disconnect(_on_dwell_triggered)

# ---------------------------------------------------------
# イベントハンドリング (関所のコアロジック)
# ---------------------------------------------------------

## 【機能】現場のセンサー（DwellArea）から「滞在条件を満たした」と報告を受けた時に呼ばれる
## 引数 area: 発火したセンサー自身
func _on_dwell_triggered(area: Node) -> void:
	
	# この時点で、ノイズ除去や時間計算はすべてセンサー側が終わらせているため、
	# ハンドラーは「受け取って横流しするだけ」の非常にシンプルな処理になる。
	
	var target_anchor_id = ""
	if "linked_anchor_id" in area:
		target_anchor_id = area.linked_anchor_id
		
	# ---------------------------------------------------------
	var furniture_name = "UNKNOWN"
	if "form_id" in area and area.form_id != "":
		furniture_name = area.form_id
		
	DK.print_fixed("[C3-Dwell] 🌟 滞在検知完了 -> " + furniture_name)
	
	# 意味のあるイベントとしてグローバルに翻訳・配信
	if EventBus.has_signal("behavior_triggered"):
		# 送信するデータ:
		# "pet_001" : ターゲットとするペットのID
		# 3 : トリガーの種類（BehaviorTrigger.ON_DWELL を表す整数値）
		# target_anchor_id : 滞在された家具のID
		EventBus.behavior_triggered.emit("pet_001", 3, target_anchor_id)
