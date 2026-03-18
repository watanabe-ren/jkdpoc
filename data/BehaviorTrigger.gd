## BehaviorTrigger.gd
## ペットの行動をトリガーするイベント種別の列挙型。
## グローバルスコープで使用できるよう class_name を定義する。
##
## res://scripts/data/BehaviorTrigger.gd
##
## NOTE: GDScript ではファイルスコープの enum はグローバルに公開されないため、
##       このファイルを autoload に加えるか、各スクリプトで
##       const BehaviorTrigger = preload("res://scripts/data/BehaviorTrigger.gd")
##       として利用してください。
##       あるいは class_name を持つクラスとして宣言し
##       BehaviorTrigger.IDLE のように参照します。

class_name BehaviorTrigger
extends RefCounted

enum Value {
	IDLE,                ## 待機中（何もトリガーがない状態）
	PERIODIC,            ## BehaviorScheduler による定期トリガー
	ON_TOUCH,            ## オブジェクト接触
	ON_DWELL,            ## エリア滞在時間達成
	ON_VOICE,            ## 音声・音量検知
	ON_POSSESSION_ENTER, ## 憑依開始時
	ON_POSSESSION_EXIT,  ## 憑依解除時
}

## 短縮アクセス用定数（BehaviorTrigger.IDLE のように使える）
const IDLE                = Value.IDLE
const PERIODIC            = Value.PERIODIC
const ON_TOUCH            = Value.ON_TOUCH
const ON_DWELL            = Value.ON_DWELL
const ON_VOICE            = Value.ON_VOICE
const ON_POSSESSION_ENTER = Value.ON_POSSESSION_ENTER
const ON_POSSESSION_EXIT  = Value.ON_POSSESSION_EXIT
