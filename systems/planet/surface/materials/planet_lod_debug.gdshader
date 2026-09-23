shader_type spatial;
render_mode cull_back;

uniform bool show_lod = false;
uniform float sea_normalized : hint_range(0.0, 1.0) = 0.28;
instance uniform vec3 lod_color = vec3(0.7);

varying vec3 radial_normal;
varying vec3 local_surface_normal;

void vertex() {
	radial_normal = normalize(VERTEX);
	local_surface_normal = normalize(NORMAL);
}

void fragment() {
	vec2 edge = min(UV, vec2(1.0) - UV);
	float border = smoothstep(0.0, 0.015, min(edge.x, edge.y));
	if (show_lod) {
		ALBEDO = mix(vec3(0.025), lod_color, border);
		ROUGHNESS = 0.86;
	} else {
		float height = COLOR.r;
		float land = COLOR.g;
		float mountains = COLOR.b;
		float plateaus = COLOR.a;
		float relative_land_height = clamp((height - sea_normalized) / max(1.0 - sea_normalized, 0.001), 0.0, 1.0);
		vec3 deep_ocean = vec3(0.018, 0.055, 0.095);
		vec3 shelf = vec3(0.045, 0.19, 0.23);
		vec3 beach = vec3(0.48, 0.43, 0.29);
		vec3 lowland = vec3(0.20, 0.32, 0.16);
		vec3 highland = vec3(0.34, 0.29, 0.22);
		vec3 rock = vec3(0.40, 0.39, 0.38);
		vec3 snow = vec3(0.82, 0.87, 0.90);
		vec3 water_floor = mix(deep_ocean, shelf, smoothstep(0.0, sea_normalized, height));
		vec3 ground = mix(beach, lowland, smoothstep(0.0, 0.08, relative_land_height));
		ground = mix(ground, highland, clamp(plateaus * 0.65 + relative_land_height * 0.35, 0.0, 1.0));
		ground = mix(ground, rock, smoothstep(0.12, 0.58, mountains));
	float slope = 1.0 - clamp(dot(normalize(local_surface_normal), normalize(radial_normal)), 0.0, 1.0);
		ground = mix(ground, rock * 0.75, smoothstep(0.12, 0.42, slope));
		ground = mix(ground, snow, smoothstep(0.68, 0.92, relative_land_height) * (1.0 - smoothstep(0.3, 0.65, slope)));
		ALBEDO = mix(water_floor, ground, smoothstep(0.35, 0.65, land));
		ROUGHNESS = mix(0.72, 0.96, land);
	}
}
