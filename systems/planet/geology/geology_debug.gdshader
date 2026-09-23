shader_type spatial;
render_mode cull_back, unshaded;

uniform int debug_mode = 1;
varying flat float province_id;
varying flat float province_type;
varying float maturity;
varying float influence;

void vertex() {
	province_id = CUSTOM0.x;
	province_type = CUSTOM0.w;
	maturity = CUSTOM0.y;
	influence = CUSTOM0.z;
}

void fragment() {
	int kind = int(round(province_type));
	float age = clamp(maturity, 0.0, 1.0);
	vec3 palette[9] = vec3[9](
		vec3(0.04, 0.12, 0.25), vec3(0.78, 0.57, 0.24),
		vec3(0.81, 0.27, 0.31), vec3(0.42, 0.70, 0.37),
		vec3(0.91, 0.26, 0.09), vec3(0.51, 0.40, 0.73),
		vec3(0.20, 0.70, 0.72), vec3(0.89, 0.78, 0.49),
		vec3(0.11, 0.31, 0.42));
	if (debug_mode == 1) {
		float variation = fract(sin(province_id * 57.83) * 43758.5453);
		ALBEDO = palette[clamp(kind, 0, 8)] * (0.75 + variation * 0.25);
	} else if (debug_mode == 2) {
		ALBEDO = mix(vec3(0.12, 0.22, 0.55), vec3(0.98, 0.76, 0.25), age);
	} else {
		int selected = debug_mode - 2;
		float mask = kind == selected ? clamp(influence * 2.5, 0.0, 1.0) : 0.0;
		ALBEDO = mix(vec3(0.025, 0.045, 0.065), palette[clamp(selected, 0, 8)], mask);
	}
	ROUGHNESS = 1.0;
}
