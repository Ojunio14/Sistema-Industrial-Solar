shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 selection;
uniform vec3 target_plane;
void fragment() {
 if (UV.x < selection.x - 0.01 || UV.y < selection.y - 0.01 || UV.x > selection.z + 0.01 || UV.y > selection.w + 0.01) { discard; }
 float diff = UV2.x - (dot(UV, target_plane.xy) + target_plane.z);
 ALBEDO = abs(diff) < 0.05 ? vec3(0.15, 1.0, 0.5) : (diff > 0.0 ? vec3(1.0, 0.45, 0.12) : vec3(0.15, 0.6, 1.0));
}
