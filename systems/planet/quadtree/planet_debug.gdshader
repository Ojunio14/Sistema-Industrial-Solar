shader_type spatial;
render_mode unshaded, cull_back;
uniform float morph : hint_range(0.0, 1.0) = 1.0;
uniform vec4 face_color : source_color = vec4(0.4, 0.7, 0.9, 1.0);
uniform float level = 0.0;
uniform bool show_borders = true;
varying vec3 radial;
void vertex() {
	VERTEX += CUSTOM0.xyz * (1.0 - morph);
	radial = normalize(VERTEX);
}
void fragment() {
	float light = 0.45 + 0.55 * max(dot(normalize(radial), normalize(vec3(0.6, 0.8, 1.0))), 0.0);
	vec3 color = face_color.rgb * light * (0.85 + 0.15 * fract(level * 0.37));
	vec2 width = max(fwidth(UV) * 1.5, vec2(0.0001));
	vec2 edge = smoothstep(vec2(0.0), width, min(UV, 1.0 - UV));
	if (show_borders) { color = mix(vec3(0.04), color, min(edge.x, edge.y)); }
	ALBEDO = color;
}

