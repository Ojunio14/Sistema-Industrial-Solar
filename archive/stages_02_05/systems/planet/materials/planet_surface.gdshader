shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray terrain_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray terrain_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray terrain_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float morph = 1.0;
uniform float base_radius = 50000.0;
uniform float meters_per_unit = 1.0;
uniform float texture_scale_m = 6.0;
uniform int material_debug = 0;

varying vec3 local_position;
varying vec3 local_surface_normal;
varying vec3 radial;
varying vec3 surface_factors;
varying vec4 climate_values;
varying float coast;

vec3 family_color(int family) {
	if (family == 0) { return vec3(0.48, 0.48, 0.46); }
	if (family == 1) { return vec3(0.68, 0.49, 0.34); }
	if (family == 2) { return vec3(0.24, 0.25, 0.27); }
	if (family == 3) { return vec3(0.36, 0.51, 0.23); }
	if (family == 4) { return vec3(0.86, 0.73, 0.45); }
	if (family == 5) { return vec3(0.65, 0.43, 0.27); }
	if (family == 6) { return vec3(0.88, 0.93, 0.98); }
	return vec3(0.55, 0.55, 0.51);
}

void vertex() {
	VERTEX += CUSTOM0.xyz * (1.0 - morph);
	local_position = VERTEX;
	local_surface_normal = normalize(NORMAL);
	radial = normalize(VERTEX);
	surface_factors = vec3(UV2.xy, COLOR.a);
	climate_values = vec4(CUSTOM2.x * 80.0 - 40.0, CUSTOM2.yzw);
	coast = COLOR.b;
}

float macro_pattern(vec3 p) {
	return 0.5 + 0.25 * sin(p.x * 0.0017 + sin(p.z * 0.0008)) * sin(p.y * 0.0013 - p.z * 0.0011);
}

float meso_pattern(vec3 p) {
	return 0.5 + 0.25 * sin(p.x * 0.055 + p.y * 0.018) * sin(p.z * 0.047 - p.y * 0.029);
}

void surface_weights(float height_m, float slope_value, float coastal, vec4 climate,
		vec3 factors, out float weights[8], out float exposure) {
	exposure = smoothstep(0.08, 0.52, slope_value);
	float flatness = 1.0 - exposure;
	float dry_heat = smoothstep(5.0, 25.0, climate.x);
	float cold = 1.0 - smoothstep(-10.0, 1.0, climate.x);
	float shore = clamp(coastal, 0.0, 1.0) * (1.0 - smoothstep(10.0, 95.0, height_m)) * flatness;
	weights[0] = 0.14 + 1.8 * exposure * exposure;
	weights[1] = factors.y * (1.0 + exposure) * 1.7;
	weights[2] = factors.x * (1.0 + exposure) * 2.1;
	weights[3] = (0.25 + 0.85 * climate.y) * flatness * (1.0 - 0.8 * cold);
	weights[4] = 1.8 * shore + 0.45 * factors.z * dry_heat * flatness;
	weights[5] = (1.0 - climate.w) * (0.3 + 0.7 * dry_heat) * (0.35 + 0.65 * factors.z) * flatness * 1.7;
	weights[6] = cold * 3.0 * (1.0 - 0.72 * exposure);
	weights[7] = 0.10 + 3.0 * exposure * flatness;
	float total = 0.0;
	for (int i = 0; i < 8; i++) { total += weights[i]; }
	for (int i = 0; i < 8; i++) { weights[i] /= total; }
}

// OpenGL normal maps: +green follows +V. Projection tangent bases are
// oriented separately on +/-X, +/-Y and +/-Z; a flat map leaves base normal.
void sample_family(int family, vec3 p, vec3 base_n, vec3 axis_weight,
		out vec3 albedo, out vec3 mapped_normal, out float roughness_value) {
	vec3 sign_axis = sign(base_n);
	vec2 uv_x = vec2(-sign_axis.x * p.z, p.y) * meters_per_unit / texture_scale_m;
	vec2 uv_y = vec2(p.x, -sign_axis.y * p.z) * meters_per_unit / texture_scale_m;
	vec2 uv_z = vec2(sign_axis.z * p.x, p.y) * meters_per_unit / texture_scale_m;
	vec3 a_x = texture(terrain_albedo, vec3(uv_x, float(family))).rgb;
	vec3 a_y = texture(terrain_albedo, vec3(uv_y, float(family))).rgb;
	vec3 a_z = texture(terrain_albedo, vec3(uv_z, float(family))).rgb;
	albedo = a_x * axis_weight.x + a_y * axis_weight.y + a_z * axis_weight.z;
	roughness_value = texture(terrain_roughness, vec3(uv_x, float(family))).r * axis_weight.x +
		texture(terrain_roughness, vec3(uv_y, float(family))).r * axis_weight.y +
		texture(terrain_roughness, vec3(uv_z, float(family))).r * axis_weight.z;
	vec2 n_x = texture(terrain_normal, vec3(uv_x, float(family))).rg * 2.0 - 1.0;
	vec2 n_y = texture(terrain_normal, vec3(uv_y, float(family))).rg * 2.0 - 1.0;
	vec2 n_z = texture(terrain_normal, vec3(uv_z, float(family))).rg * 2.0 - 1.0;
	vec3 perturb_x = vec3(0.0, n_x.y, -sign_axis.x * n_x.x);
	vec3 perturb_y = vec3(n_y.x, 0.0, -sign_axis.y * n_y.y);
	vec3 perturb_z = vec3(sign_axis.z * n_z.x, n_z.y, 0.0);
	vec3 perturb = perturb_x * axis_weight.x + perturb_y * axis_weight.y + perturb_z * axis_weight.z;
	perturb -= base_n * dot(perturb, base_n);
	mapped_normal = normalize(base_n + perturb * 0.7);
}

void fragment() {
	vec3 base_n = normalize(local_surface_normal);
	float h = (length(local_position) - base_radius) * meters_per_unit;
	if (h <= 0.0) {
		ALBEDO = mix(vec3(0.025, 0.08, 0.16), vec3(0.10, 0.30, 0.39), clamp(1.0 + h / 2500.0, 0.0, 1.0));
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
	} else {
	float slope_value = 1.0 - clamp(dot(base_n, normalize(radial)), 0.0, 1.0);
	float weights[8];
	float exposed;
	surface_weights(h, slope_value, coast, climate_values, surface_factors, weights, exposed);
	int first = 0;
	int second = 1;
	if (weights[1] > weights[0]) { first = 1; second = 0; }
	for (int i = 2; i < 8; i++) {
		if (weights[i] > weights[first]) { second = first; first = i; }
		else if (weights[i] > weights[second]) { second = i; }
	}
	float first_mix = weights[first] / max(0.00001, weights[first] + weights[second]);
	float macro_value = macro_pattern(local_position * meters_per_unit);
	float meso_value = meso_pattern(local_position * meters_per_unit);
	float micro_fade = 1.0 - smoothstep(5000.0, 22000.0, length(VERTEX) * meters_per_unit);
	if (material_debug != 0) {
		vec3 diagnostic = family_color(first);
		if (material_debug == 2) { diagnostic = mix(family_color(second), family_color(first), first_mix); }
		if (material_debug == 3) { diagnostic = vec3(slope_value); }
		if (material_debug == 4) { diagnostic = vec3(exposed, 0.2, 1.0 - exposed); }
		if (material_debug == 5) { diagnostic = base_n * 0.5 + 0.5; }
		if (material_debug == 6) { diagnostic = vec3(macro_value); }
		if (material_debug == 7) { diagnostic = vec3(meso_value); }
		if (material_debug == 8) { diagnostic = vec3(micro_fade); }
		ALBEDO = vec3(0.0);
		EMISSION = diagnostic;
		ROUGHNESS = 1.0;
	} else {
	vec3 axis_weight = pow(abs(base_n), vec3(4.0));
	axis_weight /= axis_weight.x + axis_weight.y + axis_weight.z;
	vec3 albedo_a;
	vec3 normal_a;
	float rough_a;
	sample_family(first, local_position, base_n, axis_weight, albedo_a, normal_a, rough_a);
	vec3 albedo_b;
	vec3 normal_b;
	float rough_b;
	sample_family(second, local_position, base_n, axis_weight, albedo_b, normal_b, rough_b);
	vec3 color = mix(albedo_b, albedo_a, first_mix);
	color *= 0.83 + 0.30 * macro_value + (meso_value - 0.5) * 0.14 * micro_fade;
	ALBEDO = color;
	ROUGHNESS = clamp(mix(rough_b, rough_a, first_mix), 0.25, 1.0);
	METALLIC = 0.0;
	vec3 detailed_normal = normalize(mix(normal_b, normal_a, first_mix));
	vec3 local_n = normalize(mix(base_n, detailed_normal, micro_fade));
	NORMAL = normalize(VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * local_n, 0.0)).xyz;
	}
	}
}
