extends SceneTree
## Regenerates res://themes/blueprint_theme.tres from BlueprintThemeBuilder.
##   godot --headless --path . -s res://scripts/ui/theme/build_theme.gd


func _initialize() -> void:
	var builder: GDScript = load("res://scripts/ui/theme/blueprint_theme_builder.gd")
	var theme: Theme = builder.build()
	var err := ResourceSaver.save(theme, builder.OUTPUT_PATH)
	print("theme -> %s (%s)" % [builder.OUTPUT_PATH, error_string(err)])
	quit(0 if err == OK else 1)
