shader_type spatial;
render_mode cull_back, unshaded;

uniform int debug_mode = 1;
uniform sampler2D climate_fields : repeat_enable, filter_linear;
uniform sampler2D climate_shadow : repeat_enable, filter_linear;
varying vec3 local_direction;

void vertex() {
	local_direction = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(local_direction);
	vec2 uv = vec2(atan(d.z, d.x) / (2.0 * PI) + 0.5,
		0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	vec4 c = texture(climate_fields, uv);
	float shadow = texture(climate_shadow, uv).r;
	if (debug_mode == 1) {
		ALBEDO = mix(vec3(0.08, 0.23, 0.62), vec3(0.95, 0.38, 0.08), c.r);
	} else if (debug_mode == 2) {
		ALBEDO = mix(vec3(0.42, 0.27, 0.13), vec3(0.09, 0.66, 0.80), c.g);
	} else if (debug_mode == 3) {
		ALBEDO = mix(vec3(0.65, 0.44, 0.22), vec3(0.08, 0.29, 0.68), c.b);
	} else if (debug_mode == 4) {
		ALBEDO = mix(vec3(0.48, 0.21, 0.09), vec3(0.19, 0.80, 0.91), c.a);
	} else {
		ALBEDO = mix(vec3(0.07, 0.11, 0.16), vec3(0.78, 0.20, 0.73), shadow);
	}
	ROUGHNESS = 1.0;
}
