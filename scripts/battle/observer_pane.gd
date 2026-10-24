class_name ObserverPane
extends SubViewportContainer
## The forward observer's view for split screen: a SubViewport that shares the battle's world
## (terrain, shells, overlay drawing all appear automatically) with its own camera and sky.

const SKY_SHADER := preload("res://scripts/ui/blueprint_sky.gdshader")

var camera: Camera2D
var _viewport: SubViewport
var _sky: ColorRect


func _init(world: World2D) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.world_2d = world
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -1
	_viewport.add_child(sky_layer)
	_sky = ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	_sky.material = mat
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky_layer.add_child(_sky)
	camera = Camera2D.new()
	_viewport.add_child(camera)
	camera.enabled = true


func _ready() -> void:
	camera.make_current()


## Points the observer at `center_px` (world pixels) with the given zoom.
func frame(center_px: Vector2, zoom: float, bedrock_y_px: float) -> void:
	camera.position = center_px
	camera.zoom = Vector2(zoom, zoom)
	var mat := _sky.material as ShaderMaterial
	mat.set_shader_parameter("view_size_px", Vector2(_viewport.size))
	mat.set_shader_parameter("camera_center_px", center_px)
	mat.set_shader_parameter("zoom", zoom)
	mat.set_shader_parameter("bedrock_y_px", bedrock_y_px)
