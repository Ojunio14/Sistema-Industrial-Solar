shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D digits : source_color, filter_nearest;
varying float glyph;
void vertex() {
	glyph = INSTANCE_CUSTOM.r;
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 normal = normalize(MODEL_MATRIX[2].xyz);
	vec3 screen_right = INV_VIEW_MATRIX[0].xyz;
	vec3 right = screen_right - normal * dot(screen_right, normal);
	if (dot(right, right) < 0.000001) { right = MODEL_MATRIX[0].xyz; }
	right = normalize(right);
	vec3 up = normalize(cross(normal, right));
	vec3 world_position = centre
		+ right * (VERTEX.x * INSTANCE_CUSTOM.b + INSTANCE_CUSTOM.g)
		+ up * (VERTEX.y * INSTANCE_CUSTOM.a);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
}
void fragment() {
	vec2 atlas_uv = vec2((UV.x + round(glyph)) / 12.0, UV.y);
	vec4 sample_color = texture(digits, atlas_uv);
	ALBEDO = sample_color.rgb;
	ALPHA = sample_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
