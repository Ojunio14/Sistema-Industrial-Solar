shader_type spatial;
render_mode cull_back, unshaded;

uniform int debug_mode = 1;
uniform sampler2D biome_dominant : repeat_enable, filter_nearest;
uniform sampler2D biome_blend : repeat_enable, filter_linear;
varying vec3 local_direction;

void vertex() {
	local_direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(local_direction);
	vec2 uv = vec2(atan(d.z, d.x) / (2.0 * PI) + 0.5,
		0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	vec4 dominant = texture(biome_dominant, uv);
	vec4 blend = texture(biome_blend, uv);
	if (debug_mode == 1) {
		ALBEDO = dominant.rgb;
	} else if (debug_mode == 2) {
		ALBEDO = blend.rgb;
	} else {
		ALBEDO = mix(vec3(0.04, 0.07, 0.11), dominant.rgb, dominant.a);
	}
	ROUGHNESS = 1.0;
}
