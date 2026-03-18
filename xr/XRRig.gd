# res://scripts/xr/XRRig.gd
extends XROrigin3D

@onready var xr_camera = $XRCamera3D
@onready var _world_environment: WorldEnvironment = \
	get_tree().root.find_child("WorldEnvironment", true, false)

func _ready() -> void:
	var xr_interface: OpenXRInterface = \
		XRServer.find_interface("OpenXR") as OpenXRInterface

	if xr_interface == null:
		push_error("XRRig: OpenXRInterface が見つかりません")
		return

	if not xr_interface.initialize():
		push_error("XRRig: initialize() 失敗")
		return

	# ★ initialize() の直後に use_xr = true を設定する（最重要）
	get_viewport().use_xr = true

	xr_interface.session_begun.connect(_on_openxr_session_begun)
	
	await get_tree().process_frame
	DK.set_current_camera(xr_camera)
	

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
