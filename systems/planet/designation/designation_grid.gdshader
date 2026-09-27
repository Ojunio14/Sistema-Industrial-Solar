shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	vec2 edge = min(UV, vec2(1.0) - UV);
	float line = 1.0 - smoothstep(0.015, 0.03, min(edge.x, edge.y));
	if (COLOR.a < 0.25) {
		line *= mix(0.3, 1.0, step(0.5, fract((UV.x + UV.y) * 10.0)));
	}
	float complete_mark = step(0.75, COLOR.a) * step(UV.x, 0.14) * step(UV.y, 0.14);
	ALBEDO = mix(COLOR.rgb, vec3(0.94), line * 0.85);
	ALBEDO = mix(ALBEDO, vec3(1.0), complete_mark);
	ALPHA = max(mix(0.24, 0.9, line), complete_mark);
}
