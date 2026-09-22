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
void vertex() {
	VERTEX += CUSTOM0.xyz * (1.0 - morph);
	radial = normalize(VERTEX);
	planet_position = VERTEX;
	// Categorical metadata must not invent intermediate IDs by interpolation.
	macro_form = floor(COLOR.g * 8.0 + 0.5);
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
	vec2 width = max(fwidth(UV) * 1.5, vec2(0.0001));
	vec2 edge = smoothstep(vec2(0.0), width, min(UV, 1.0 - UV));
	if (show_borders) { color = mix(vec3(0.04), color, min(edge.x, edge.y)); }
	ALBEDO = color;
}
