shader_type spatial;
render_mode unshaded, cull_back;
uniform float morph : hint_range(0.0, 1.0) = 1.0;
uniform vec4 face_color : source_color = vec4(0.4, 0.7, 0.9, 1.0);
uniform float level = 0.0;
uniform bool show_borders = true;
uniform int debug_mode = 0;
uniform float base_radius = 50000.0;
uniform float meters_per_unit = 1.0;
varying vec3 radial;
varying vec3 planet_position;
varying flat float macro_form;
varying flat float province_id;
varying vec2 geological_attributes;
varying vec4 climate_values;
varying float climate_shadow;
varying flat float primary_biome;
varying flat float secondary_biome;
varying float biome_pair_mix;
vec3 biome_color(int kind) {
	if (kind == 0) { return vec3(0.08, 0.36, 0.16); }
	if (kind == 1) { return vec3(0.64, 0.64, 0.19); }
	if (kind == 2) { return vec3(0.83, 0.64, 0.32); }
	if (kind == 3) { return vec3(0.88, 0.78, 0.73); }
	if (kind == 4) { return vec3(0.31, 0.64, 0.30); }
	if (kind == 5) { return vec3(0.12, 0.55, 0.52); }
	if (kind == 6) { return vec3(0.16, 0.37, 0.37); }
	if (kind == 7) { return vec3(0.56, 0.48, 0.59); }
	if (kind == 8) { return vec3(0.48, 0.57, 0.72); }
	return vec3(0.85, 0.92, 0.97);
}
void vertex() {
	VERTEX += CUSTOM0.xyz * (1.0 - morph);
	radial = normalize(VERTEX);
	planet_position = VERTEX;
	// Categorical metadata must not invent intermediate IDs by interpolation.
	macro_form = floor(COLOR.g * 8.0 + 0.5);
	province_id = CUSTOM1.x;
	geological_attributes = CUSTOM1.yz;
	climate_values = vec4(CUSTOM2.x * 80.0 - 40.0, CUSTOM2.yzw);
	climate_shadow = CUSTOM3.x;
	primary_biome = round(CUSTOM3.y * 11.0) - 1.0;
	secondary_biome = round(CUSTOM3.z * 11.0) - 1.0;
	biome_pair_mix = CUSTOM3.w;
}
void fragment() {
	// Technical unshaded lighting follows the actual morphed triangle.
	vec3 n = normalize(cross(dFdx(planet_position), dFdy(planet_position)));
	if (dot(n, radial) < 0.0) { n = -n; }
	float light = 0.50 + 0.50 * max(dot(n, normalize(vec3(0.6, 0.8, 1.0))), 0.0);
	vec3 color = face_color.rgb * light * (0.85 + 0.15 * fract(level * 0.37));
	float h = (length(planet_position) - base_radius) * meters_per_unit;
	if (debug_mode == 1) { color = h >= 0.0 ? vec3(0.34, 0.66, 0.32) : vec3(0.08, 0.30, 0.58); }
	if (debug_mode == 2) {
		color = h < 0.0 ? mix(vec3(0.03, 0.09, 0.25), vec3(0.16, 0.53, 0.66), clamp(1.0 + h / 3000.0, 0.0, 1.0)) :
			mix(mix(vec3(0.34, 0.57, 0.24), vec3(0.64, 0.45, 0.24), clamp(h / 900.0, 0.0, 1.0)), vec3(0.90, 0.86, 0.78), clamp((h - 900.0) / 1100.0, 0.0, 1.0));
		color *= light;
	}
	if (debug_mode == 3) { color = mix(vec3(0.1, 0.2, 0.65), vec3(0.85, 0.60, 0.15), COLOR.r); }
	if (debug_mode == 4) {
		float kind = macro_form;
		color = 0.3 + 0.6 * fract(vec3(0.27, 0.53, 0.79) * (kind + 1.0));
		if (kind < 0.5) { color = vec3(0.04, 0.16, 0.40); }
	}
	if (debug_mode == 5) { color = abs(h) < max(fwidth(h) * 1.5, 8.0) ? vec3(1.0, 0.85, 0.2) : (h < 0.0 ? vec3(0.03, 0.14, 0.30) : vec3(0.28)); }
	if (debug_mode == 6) {
		float coast = max(COLOR.b, 1.0 - smoothstep(0.0, 50.0, abs(h)));
		color = mix(vec3(0.06, 0.12, 0.22), vec3(1.0, 0.65, 0.15), coast);
	}
	if (debug_mode >= 7 && debug_mode < 16) {
		int kind = int(province_id + 0.5) % 16;
		vec3 province_color = 0.25 + 0.65 * fract(vec3(0.317, 0.537, 0.719) * (province_id + 1.0));
		color = kind == 0 ? vec3(0.03, 0.13, 0.30) : province_color;
		if (debug_mode == 8) {
			color = mix(vec3(0.95, 0.24, 0.10), vec3(0.20, 0.45, 0.85), geological_attributes.x);
		}
		if (debug_mode >= 9) {
			int selected_kind = debug_mode - 8;
			color = mix(vec3(0.07, 0.09, 0.13), province_color, kind == selected_kind ? geological_attributes.y : 0.0);
		}
	}
	if (debug_mode >= 16) {
		if (debug_mode == 16) {
			float t = clamp((climate_values.x + 30.0) / 65.0, 0.0, 1.0);
			color = t < 0.5 ? mix(vec3(0.14, 0.25, 0.72), vec3(0.76, 0.82, 0.51), t * 2.0) :
				mix(vec3(0.76, 0.82, 0.51), vec3(0.87, 0.17, 0.08), (t - 0.5) * 2.0);
		}
		if (debug_mode == 17) { color = mix(vec3(0.63, 0.42, 0.18), vec3(0.06, 0.56, 0.74), climate_values.y); }
		if (debug_mode == 18) { color = mix(vec3(0.57, 0.38, 0.19), vec3(0.12, 0.64, 0.83), climate_values.z); }
		if (debug_mode == 19) { color = mix(vec3(0.73, 0.58, 0.34), vec3(0.13, 0.44, 0.78), climate_values.w); }
		if (debug_mode == 20) { color = mix(vec3(0.11, 0.47, 0.66), vec3(0.82, 0.40, 0.13), climate_shadow); }
		if (debug_mode >= 21) {
			int first = int(primary_biome + 0.5);
			int second = int(secondary_biome + 0.5);
			color = h <= 0.0 ? vec3(0.04, 0.17, 0.35) : biome_color(first);
			if (debug_mode == 22 && h > 0.0) {
				color = mix(biome_color(second), biome_color(first), biome_pair_mix);
			}
		}
	}
	vec2 width = max(fwidth(UV) * 1.5, vec2(0.0001));
	vec2 edge = smoothstep(vec2(0.0), width, min(UV, 1.0 - UV));
	if (show_borders) { color = mix(vec3(0.04), color, min(edge.x, edge.y)); }
	ALBEDO = color;
}
