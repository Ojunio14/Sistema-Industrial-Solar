shader_type spatial;
render_mode diffuse_burley;
uniform bool dirty = false;
varying float camera_distance;
void vertex() {
	camera_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
float grid(vec2 coord, float width) {
	vec2 distance_to_line = abs(fract(coord + 0.5) - 0.5) / max(fwidth(coord), vec2(0.0001));
	return 1.0 - smoothstep(width, width + 1.0, min(distance_to_line.x, distance_to_line.y));
}
void fragment() {
	float chunks = grid(UV / 256.0, 1.2);
	float cells = grid(UV / 2.0, 0.45) * (1.0 - smoothstep(90.0, 230.0, camera_distance));
	ALBEDO = mix(COLOR.rgb, vec3(0.13, 0.19, 0.22), cells * 0.6);
	ALBEDO = mix(ALBEDO, dirty ? vec3(1.0, 0.3, 0.13) : vec3(0.25, 0.95, 0.8), chunks);
	ROUGHNESS = 0.92;
}
