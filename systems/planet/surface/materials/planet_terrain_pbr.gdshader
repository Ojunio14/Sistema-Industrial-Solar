shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform bool show_lod = false;
uniform int material_debug_mode = 0;
uniform float sea_normalized : hint_range(0.0, 1.0) = 0.28;
uniform float height_range_m = 3000.0;
// Metros cobertos por uma repetição de cada textura 2K. Constantes físicas, não UV de chunk.
uniform float rock_generic_tile_m = 6.0;
uniform float rock_sedimentary_tile_m = 8.0;
uniform float rock_volcanic_tile_m = 6.0;
uniform float soil_tile_m = 4.5;
uniform float sand_tile_m = 6.0;
uniform float arid_ground_tile_m = 6.0;
uniform float snow_ice_tile_m = 8.0;
uniform float gravel_tile_m = 3.0;
instance uniform vec3 lod_color = vec3(0.7);
uniform sampler2D rock_generic_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_generic_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_generic_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_sedimentary_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_sedimentary_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_sedimentary_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_volcanic_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_volcanic_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_volcanic_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arid_ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arid_ground_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arid_ground_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_ice_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_ice_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_ice_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 planet_position;
varying vec3 planet_normal;
varying vec4 family_a;
varying vec4 family_b;

void vertex() {
	planet_position = VERTEX;
	planet_normal = NORMAL;
	family_a = CUSTOM1;
	family_b = CUSTOM2;
}

float family_weight(int id) {
	if (id < 4) { return family_a[id]; }
	return family_b[id - 4];
}

vec3 family_color(int id) {
	if (id == 0) { return vec3(0.53, 0.55, 0.57); }
	if (id == 1) { return vec3(0.77, 0.59, 0.39); }
	if (id == 2) { return vec3(0.38, 0.21, 0.31); }
	if (id == 3) { return vec3(0.31, 0.66, 0.29); }
	if (id == 4) { return vec3(0.94, 0.79, 0.35); }
	if (id == 5) { return vec3(0.73, 0.45, 0.21); }
	if (id == 6) { return vec3(0.83, 0.92, 1.0); }
	return vec3(0.48, 0.47, 0.50);
}

vec3 family_average_color(int id) {
	if (id == 0) { return vec3(0.1662, 0.1250, 0.0758); }
	if (id == 1) { return vec3(0.2475, 0.2149, 0.1728); }
	if (id == 2) { return vec3(0.1946, 0.1706, 0.1346); }
	if (id == 3) { return vec3(0.1333, 0.0935, 0.0341); }
	if (id == 4) { return vec3(0.2240, 0.1712, 0.1076); }
	if (id == 5) { return vec3(0.1472, 0.1039, 0.0598); }
	if (id == 6) { return vec3(0.3783, 0.3782, 0.3897); }
	return vec3(0.2306, 0.1935, 0.1537);
}

float family_average_roughness(int id) {
	if (id == 0) { return 0.793; }
	if (id == 1) { return 0.538; }
	if (id == 2) { return 0.812; }
	if (id == 3) { return 0.920; }
	if (id == 4) { return 0.963; }
	if (id == 5) { return 0.901; }
	if (id == 6) { return 0.801; }
	return 0.808;
}

float family_scale(int id) {
	if (id == 0) { return 1.0 / rock_generic_tile_m; }
	if (id == 1) { return 1.0 / rock_sedimentary_tile_m; }
	if (id == 2) { return 1.0 / rock_volcanic_tile_m; }
	if (id == 3) { return 1.0 / soil_tile_m; }
	if (id == 4) { return 1.0 / sand_tile_m; }
	if (id == 5) { return 1.0 / arid_ground_tile_m; }
	if (id == 6) { return 1.0 / snow_ice_tile_m; }
	return 1.0 / gravel_tile_m;
}

vec3 rotated_domain(vec3 p) {
	vec3 y = vec3(0.8660254 * p.x - 0.5 * p.z, p.y,
		0.5 * p.x + 0.8660254 * p.z);
	return vec3(y.x, 0.921061 * y.y - 0.389418 * y.z,
		0.389418 * y.y + 0.921061 * y.z);
}

vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yxz + 19.19);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Offset pseudoaleatório 3D interpolado. O hash só muda a cada 16 m;
// a interpolação cúbica evita saltos em bordas de células e cube faces.
vec3 stochastic_offset(vec3 p) {
	vec3 cell = floor(p / 16.0);
	vec3 f = fract(p / 16.0);
	vec3 t = f * f * (3.0 - 2.0 * f);
	vec3 low = mix(
		mix(hash3(cell), hash3(cell + vec3(1.0, 0.0, 0.0)), t.x),
		mix(hash3(cell + vec3(0.0, 1.0, 0.0)), hash3(cell + vec3(1.0, 1.0, 0.0)), t.x), t.y);
	vec3 high = mix(
		mix(hash3(cell + vec3(0.0, 0.0, 1.0)), hash3(cell + vec3(1.0, 0.0, 1.0)), t.x),
		mix(hash3(cell + vec3(0.0, 1.0, 1.0)), hash3(cell + vec3(1.0, 1.0, 1.0)), t.x), t.y);
	return (mix(low, high, t.z) - vec3(0.5)) * 8.0;
}

vec2 uv_x(vec3 p, vec3 n) { return vec2(-sign(n.x) * p.z, p.y); }
vec2 uv_y(vec3 p, vec3 n) { return vec2(p.x, -sign(n.y) * p.z); }
vec2 uv_z(vec3 p, vec3 n) { return vec2(sign(n.z) * p.x, p.y); }

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.00001);
	w *= smoothstep(vec3(0.005), vec3(0.02), w);
	return w / max(dot(w, vec3(1.0)), 0.00001);
}

vec3 sample_albedo(int id, vec2 uv, vec2 gx, vec2 gy) {
	if (id == 0) { return textureGrad(rock_generic_albedo, uv, gx, gy).rgb; }
	else if (id == 1) { return textureGrad(rock_sedimentary_albedo, uv, gx, gy).rgb; }
	else if (id == 2) { return textureGrad(rock_volcanic_albedo, uv, gx, gy).rgb; }
	else if (id == 3) { return textureGrad(soil_albedo, uv, gx, gy).rgb; }
	else if (id == 4) { return textureGrad(sand_albedo, uv, gx, gy).rgb; }
	else if (id == 5) { return textureGrad(arid_ground_albedo, uv, gx, gy).rgb; }
	else if (id == 6) { return textureGrad(snow_ice_albedo, uv, gx, gy).rgb; }
	else if (id == 7) { return textureGrad(gravel_albedo, uv, gx, gy).rgb; }
	return vec3(0.5);
}

float sample_roughness(int id, vec2 uv, vec2 gx, vec2 gy) {
	if (id == 0) { return textureGrad(rock_generic_roughness, uv, gx, gy).r; }
	else if (id == 1) { return textureGrad(rock_sedimentary_roughness, uv, gx, gy).r; }
	else if (id == 2) { return textureGrad(rock_volcanic_roughness, uv, gx, gy).r; }
	else if (id == 3) { return textureGrad(soil_roughness, uv, gx, gy).r; }
	else if (id == 4) { return textureGrad(sand_roughness, uv, gx, gy).r; }
	else if (id == 5) { return textureGrad(arid_ground_roughness, uv, gx, gy).r; }
	else if (id == 6) { return textureGrad(snow_ice_roughness, uv, gx, gy).r; }
	else if (id == 7) { return textureGrad(gravel_roughness, uv, gx, gy).r; }
	return 0.9;
}

vec2 sample_normal_rg(int id, vec2 uv, vec2 gx, vec2 gy) {
	if (id == 0) { return textureGrad(rock_generic_normal, uv, gx, gy).rg; }
	else if (id == 1) { return textureGrad(rock_sedimentary_normal, uv, gx, gy).rg; }
	else if (id == 2) { return textureGrad(rock_volcanic_normal, uv, gx, gy).rg; }
	else if (id == 3) { return textureGrad(soil_normal, uv, gx, gy).rg; }
	else if (id == 4) { return textureGrad(sand_normal, uv, gx, gy).rg; }
	else if (id == 5) { return textureGrad(arid_ground_normal, uv, gx, gy).rg; }
	else if (id == 6) { return textureGrad(snow_ice_normal, uv, gx, gy).rg; }
	else if (id == 7) { return textureGrad(gravel_normal, uv, gx, gy).rg; }
	return vec2(0.5);
}

vec3 decode_normal(vec2 rg) {
	vec2 xy = rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

vec4 sample_family_data(int id, vec3 p, vec3 n, vec3 axis_w, bool with_roughness,
		float scale_multiplier) {
	float scale = family_scale(id) * scale_multiplier;
	vec2 uv_x_local = uv_x(p, n) * scale;
	vec2 uv_y_local = uv_y(p, n) * scale;
	vec2 uv_z_local = uv_z(p, n) * scale;
	vec2 gx_x = dFdx(uv_x_local), gy_x = dFdy(uv_x_local);
	vec2 gx_y = dFdx(uv_y_local), gy_y = dFdy(uv_y_local);
	vec2 gx_z = dFdx(uv_z_local), gy_z = dFdy(uv_z_local);
	vec4 result = vec4(0.0);
	if (axis_w.x > 0.0) {
		result.rgb += sample_albedo(id, uv_x_local, gx_x, gy_x) * axis_w.x;
		if (with_roughness) { result.a += sample_roughness(id, uv_x_local, gx_x, gy_x) * axis_w.x; }
	}
	if (axis_w.y > 0.0) {
		result.rgb += sample_albedo(id, uv_y_local, gx_y, gy_y) * axis_w.y;
		if (with_roughness) { result.a += sample_roughness(id, uv_y_local, gx_y, gy_y) * axis_w.y; }
	}
	if (axis_w.z > 0.0) {
		result.rgb += sample_albedo(id, uv_z_local, gx_z, gy_z) * axis_w.z;
		if (with_roughness) { result.a += sample_roughness(id, uv_z_local, gx_z, gy_z) * axis_w.z; }
	}
	return result;
}

vec3 sample_family_normal(int id, vec3 p, vec3 n, vec3 axis_w) {
	float scale = family_scale(id);
	vec2 uv_x_local = uv_x(p, n) * scale;
	vec2 uv_y_local = uv_y(p, n) * scale;
	vec2 uv_z_local = uv_z(p, n) * scale;
	vec2 gx_x = dFdx(uv_x_local), gy_x = dFdy(uv_x_local);
	vec2 gx_y = dFdx(uv_y_local), gy_y = dFdy(uv_y_local);
	vec2 gx_z = dFdx(uv_z_local), gy_z = dFdy(uv_z_local);
	vec3 result = vec3(0.0);
	if (axis_w.x > 0.0) {
		vec3 decoded = decode_normal(sample_normal_rg(id, uv_x_local, gx_x, gy_x));
		result += vec3(sign(n.x) * decoded.z, decoded.y, -sign(n.x) * decoded.x) * axis_w.x;
	}
	if (axis_w.y > 0.0) {
		vec3 decoded = decode_normal(sample_normal_rg(id, uv_y_local, gx_y, gy_y));
		result += vec3(decoded.x, sign(n.y) * decoded.z, -sign(n.y) * decoded.y) * axis_w.y;
	}
	if (axis_w.z > 0.0) {
		vec3 decoded = decode_normal(sample_normal_rg(id, uv_z_local, gx_z, gy_z));
		result += vec3(sign(n.z) * decoded.x, decoded.y, sign(n.z) * decoded.z) * axis_w.z;
	}
	return normalize(result);
}

void fragment() {
	vec2 edge = min(UV, vec2(1.0) - UV);
	float border = smoothstep(0.0, 0.015, min(edge.x, edge.y));
	if (show_lod) {
		ALBEDO = mix(vec3(0.025), lod_color, border);
		ROUGHNESS = 0.86;
	} else {
	float land = smoothstep(0.38, 0.62, COLOR.g);
	vec3 n = normalize(planet_normal);
	vec3 radial = normalize(planet_position);
	float slope = clamp(1.0 - dot(n, radial), 0.0, 1.0);
	if (land < 0.001) {
		float depth = COLOR.r / max(sea_normalized, 0.0001);
		ALBEDO = mix(vec3(0.025, 0.062, 0.077), vec3(0.085, 0.14, 0.15), clamp(depth, 0.0, 1.0));
		ROUGHNESS = 0.92;
	} else {
	float macro = 0.5 + 0.25 * sin(dot(planet_position, vec3(0.68, 0.21, 0.70)) / 97.0
		+ 0.6 * sin(planet_position.z / 193.0))
		+ 0.25 * cos(dot(planet_position, vec3(-0.29, 0.91, 0.31)) / 241.0);
	float weights[8];
	float total = 0.0;
	for (int i = 0; i < 8; i++) {
		weights[i] = max(family_weight(i), 0.0);
		total += weights[i];
	}
	float coast_altitude_m = (COLOR.r - sea_normalized) * height_range_m;
	float coast_fade = (1.0 - smoothstep(7.0, 100.0, coast_altitude_m))
		* (1.0 - smoothstep(0.03, 0.25, slope));
	float sand_before = weights[4];
	weights[4] *= 1.0 + coast_fade * (macro - 0.5) * 1.2;
	total += weights[4] - sand_before;
	// Interpolação costeira pode marcar terra sem família (vértices submersos
	// carregam oito zeros). A areia é o fallback visual nessa transição.
	if (total < 0.00001) { weights[4] = 1.0; total = 1.0; }
	for (int i = 0; i < 8; i++) { weights[i] /= max(total, 0.00001); }
	int first = 0, second = 1;
	if (weights[second] > weights[first]) { first = 1; second = 0; }
	for (int i = 2; i < 8; i++) {
		if (weights[i] > weights[first]) { second = first; first = i; }
		else if (weights[i] > weights[second]) { second = i; }
	}
	int third = 0;
	float third_weight = -1.0;
	for (int i = 0; i < 8; i++) {
		if (i != first && i != second && weights[i] > third_weight) {
			third = i;
			third_weight = weights[i];
		}
	}
	float top_sum = max(weights[first] + weights[second], 0.00001);
	float mix_second = weights[second] / top_sum;
	if (material_debug_mode > 0) {
		if (material_debug_mode == 1) { ALBEDO = family_color(first); }
		else if (material_debug_mode == 2) { ALBEDO = mix(family_color(first), family_color(second), mix_second); }
		else if (material_debug_mode == 3) { ALBEDO = vec3(smoothstep(0.01, 0.4, slope)); }
		else if (material_debug_mode == 4) { ALBEDO = vec3(weights[0] + weights[1] + weights[2] + weights[7]); }
		else if (material_debug_mode == 5) { ALBEDO = vec3(weights[6]); }
		else { ALBEDO = vec3(float(first) / 7.0, float(second) / 7.0, mix_second); }
		EMISSION = ALBEDO;
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
	} else {
	vec3 axis_w = tri_weights(n);
	// As duas deformações são globais, contínuas e pequenas em relação ao tile.
	float distance_m = length(VERTEX);
	float anti_fade = 1.0 - smoothstep(800.0, 3600.0, distance_m);
	float macro_fade = 1.0 - smoothstep(1500.0, 10000.0, distance_m);
	vec3 random_offset = vec3(0.0);
	if (anti_fade > 0.001) {
		random_offset = stochastic_offset(planet_position) * anti_fade;
	}
	vec3 texture_position = planet_position + 2.0 * sin(planet_position.yzx / 17.0)
		+ 1.3 * sin(planet_position.zxy / 31.0)
		+ 0.8 * sin(planet_position.xzy / 43.0)
		+ 0.23 * sin(planet_position.zxy / 113.0) + 0.70 * random_offset;
	// O detalhe secundário some quando 2º e 3º empatam: sem corte de textura no ranking.
	float secondary_detail = smoothstep(0.0, 0.08, weights[second] - weights[third]);
	vec4 first_data = sample_family_data(first, texture_position, n, axis_w, true, 1.0);
	vec4 second_data = vec4(0.0);
	if (secondary_detail > 0.001) {
		second_data = sample_family_data(second, texture_position, n, axis_w, true, 1.0);
	}
	// Segunda escala somente do dominante; desaparece suavemente quando a liderança troca.
	float dual_weight = 0.60 * anti_fade *
		smoothstep(0.0, 0.12, weights[first] - weights[second]);
	vec3 dual_delta = vec3(0.0);
	if (dual_weight > 0.001) {
		vec3 rotated_n = rotated_domain(n);
		vec4 dual_data = sample_family_data(first,
			rotated_domain(texture_position + 0.30 * random_offset)
				+ vec3(237.0, -611.0, 347.0),
			rotated_n, tri_weights(rotated_n), false, 0.63);
		dual_delta = dual_data.rgb - family_average_color(first);
	}
	float meso = sin(planet_position.x / 27.0 + planet_position.y / 33.0)
		* cos(planet_position.z / 39.0);
	float meso_fade = 1.0 - smoothstep(1300.0, 7000.0, distance_m);
	float micro_fade = 1.0 - smoothstep(150.0, 1200.0, distance_m);
	vec3 color =
		weights[0] * vec3(0.1662, 0.1250, 0.0758) +
		weights[1] * vec3(0.2475, 0.2149, 0.1728) +
		weights[2] * vec3(0.1946, 0.1706, 0.1346) +
		weights[3] * vec3(0.1333, 0.0935, 0.0341) +
		weights[4] * vec3(0.2240, 0.1712, 0.1076) +
		weights[5] * vec3(0.1472, 0.1039, 0.0598) +
		weights[6] * vec3(0.3783, 0.3782, 0.3897) +
		weights[7] * vec3(0.2306, 0.1935, 0.1537);
	color += weights[first] * ((1.0 - dual_weight) *
		(first_data.rgb - family_average_color(first)) + dual_weight * dual_delta);
	color += weights[second] * secondary_detail *
		(second_data.rgb - family_average_color(second));
	color *= 0.98 + 0.08 * (macro - 0.5) * macro_fade
		+ 0.025 * meso * meso_fade;
	vec3 mapped = n;
	if (micro_fade > 0.001) {
		vec3 first_n = sample_family_normal(first, texture_position, n, axis_w);
		mapped = first_n;
		if (secondary_detail > 0.001) {
			vec3 second_n = sample_family_normal(second, texture_position, n, axis_w);
			mapped = normalize(mix(first_n, second_n, mix_second * secondary_detail));
		}
		mapped = normalize(mix(n, mapped, micro_fade * 0.72));
	}
	vec3 view_normal = normalize(VIEW_MATRIX * vec4(normalize(MODEL_NORMAL_MATRIX * mapped), 0.0)).xyz;
	ALBEDO = mix(vec3(0.055, 0.105, 0.12), color, land);
	float roughness =
		weights[0] * 0.793 + weights[1] * 0.538 + weights[2] * 0.812 +
		weights[3] * 0.920 + weights[4] * 0.963 + weights[5] * 0.901 +
		weights[6] * 0.801 + weights[7] * 0.808;
	roughness += weights[first] * (first_data.a - family_average_roughness(first));
	roughness += weights[second] * secondary_detail *
		(second_data.a - family_average_roughness(second));
	ROUGHNESS = clamp(roughness + 0.035 * (macro - 0.5) * macro_fade, 0.08, 1.0);
	METALLIC = 0.0;
	NORMAL = view_normal;
	}
	}
	}
}
