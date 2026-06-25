shader_type spatial;
// Inverted-hull outline. Rendered as a second pass (next_pass) on a cel-shaded
// material: backfaces only (cull_front), pushed out along their normals, drawn
// flat and unshaded. The model itself occludes the expanded hull everywhere
// except the silhouette, leaving a clean ink line around the edge.
//
// Note: outline_width is a local-space offset, so a non-uniformly scaled mesh
// (e.g. the elite's 1.25x XZ Visual) gets a slightly uneven line. Acceptable
// for now; revisit with a view-space width if it ever reads wrong.
render_mode cull_front, unshaded, shadows_disabled, fog_disabled;

uniform float outline_width : hint_range(0.0, 0.2) = 0.02;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	VERTEX += normalize(NORMAL) * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
