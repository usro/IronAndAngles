shader_type canvas_item;
// Blueprint look for terrain chunks: a drafting section (45° hatching over the grid) with a
// bright cut edge. TEXTURE is the L8 solidity map (1 = solid), linearly filtered so the 0.5
// contour gives smooth crater edges.

uniform vec4 fill_color : source_color = vec4(0.11, 0.27, 0.52, 1.0);
uniform vec4 edge_color : source_color = vec4(0.85, 0.93, 1.0, 1.0);
uniform vec4 grid_color : source_color = vec4(0.32, 0.52, 0.80, 1.0);
uniform float grid_spacing_px = 80.0;
uniform vec4 hatch_color : source_color = vec4(0.50, 0.83, 1.0, 1.0);
uniform float hatch_spacing_px = 14.0;

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float d = texture(TEXTURE, UV).r;
	float aa = max(fwidth(d), 1e-4);
	float inside = smoothstep(0.5 - aa, 0.5 + aa, d);
	float edge = 1.0 - smoothstep(0.0, 1.5 * aa, abs(d - 0.5) - 0.5 * aa);
	vec2 g = abs(fract(world_px / grid_spacing_px + 0.5) - 0.5) * grid_spacing_px;
	float grid = 1.0 - smoothstep(0.0, 1.0, min(g.x, g.y));
	vec3 col = mix(fill_color.rgb, grid_color.rgb, grid * 0.6);
	float h = abs(fract((world_px.x + world_px.y) / hatch_spacing_px) - 0.5) * hatch_spacing_px;
	float hw = max(fwidth(world_px.x + world_px.y), 1e-4);
	// Fade the hatching out when zoomed so far out that it would turn into moiré.
	float hatch_fade = clamp((hatch_spacing_px / hw - 3.0) / 5.0, 0.0, 1.0);
	col = mix(col, hatch_color.rgb, (1.0 - smoothstep(0.0, hw * 1.2, h)) * 0.18 * hatch_fade);
	col = mix(col, edge_color.rgb, edge);
	COLOR = vec4(col, max(inside, edge) * fill_color.a);
}
