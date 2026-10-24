class_name OverlaySheet
extends PanelContainer
## A full-screen dimmed overlay with one centred blueprint sheet: kicker, title, Close [Esc] and a
## content box. Base for the pause menu, settings and credits. Works while the tree is paused.

signal closed

var content: VBoxContainer
var _kicker: String
var _title: String
var _width: float
## When > 0, the content scrolls inside this height (for sheets taller than the screen).
var max_content_height := 0.0


func _init(kicker: String, title: String, width := 560.0) -> void:
	_kicker = kicker
	_title = title
	_width = width
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(Blueprint.PAPER_DARK, 0.92)
	add_theme_stylebox_override("panel", shade)
	var center := CenterContainer.new()
	add_child(center)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	sheet.custom_minimum_size = Vector2(_width, 0)
	center.add_child(sheet)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	sheet.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var kicker := Label.new()
	kicker.theme_type_variation = &"SectionLabel"
	kicker.text = _kicker
	heading.add_child(kicker)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.text = _title
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_sheet)
	top.add_child(close)
	root.add_child(HSeparator.new())
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	if max_content_height > 0.0:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(_width - 40.0, minf(max_content_height,
			get_viewport_rect().size.y - 200.0))
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		root.add_child(scroll)
	else:
		root.add_child(content)
	build()


## Subclasses fill `content` here.
func build() -> void:
	pass


func close_sheet() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_sheet()


func add_button(text: String, on_press: Callable, variation := &"MenuButtonLarge") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(on_press)
	content.add_child(b)
	return b


func add_text(text: String, variation := &"BodyLabel") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_width - 60.0, 0)
	content.add_child(l)
	return l
