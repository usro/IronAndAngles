shader_type canvas_item;
// Battle sky: blueprint paper with a world-aligned grid (it pans and zooms with the camera and
// lines up with the terrain shader's grid) and a soft glow toward the horizon.

uniform vec4 paper_top : source_color = vec4(0.03, 0.10, 0.20, 1.0);
uniform vec4 paper_bottom : source_color = vec4(0.07, 0.19, 0.34, 1.0);
uniform vec4 grid_color : source_color = vec4(0.45, 0.70, 0.95, 1.0);
uniform vec2 view_size_px = vec2(1280.0, 720.0);
uniform vec2 camera_center_px = vec2(0.0);
uniform float zoom = 1.0;
uniform float minor_px = 80.0;
uniform float major_px = 400.0;
// Below the terrain grid's bottom edge everything is bedrock: continue the terrain fill there.
uniform float bedrock_y_px = 1e9;
uniform vec4 bedrock_color : source_color = vec4(0.11, 0.27, 0.52, 1.0);
uniform vec4 bedrock_grid : source_color = vec4(0.32, 0.52, 0.80, 1.0);

float grid_line(vec2 world, float spacing, float width_screen_px) {
	vec2 d = abs(fract(world / spacing + 0.5) - 0.5) * spacing * zoom;
	float m = min(d.x, d.y);
	return 1.0 - smoothstep(width_screen_px * 0.5, width_screen_px * 0.5 + 1.0, m);
}

void fragment() {
	vec2 world = camera_center_px + (UV - 0.5) * view_size_px / zoom;
	vec3 col = mix(paper_top.rgb, paper_bottom.rgb, smoothstep(0.0, 1.0, UV.y));
	// Fade the minor grid out when it gets denser than ~12 screen px.
	float minor_fade = clamp((minor_px * zoom - 6.0) / 12.0, 0.0, 1.0);
	col = mix(col, grid_color.rgb, grid_line(world, minor_px, 1.0) * 0.07 * minor_fade);
	col = mix(col, grid_color.rgb, grid_line(world, major_px, 1.0) * 0.16);
	if (world.y > bedrock_y_px) {
		col = mix(bedrock_color.rgb, bedrock_grid.rgb, grid_line(world, minor_px, 1.0) * 0.15 * minor_fade);
	}
	COLOR = vec4(col, 1.0);
}
