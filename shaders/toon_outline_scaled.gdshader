shader_type spatial;
// Scale-compensated inverted-hull outline, for heavily-scaled meshes (the rigged
// Kenney enemy: the FBX imports at ~62x cumulative, so a plain local-space hull
// offset balloons into a giant shell). Same backface-only push as toon_outline,
// but the offset is divided by the model's world scale so the ink line lands at a
// roughly CONSTANT world-space width regardless of how the mesh is scaled. Used
// only by the character rig; unit-scaled meshes keep toon_outline.gdshader.
render_mode cull_front, unshaded, shadows_disabled, fog_disabled;

uniform float outline_width : hint_range(0.0, 0.2) = 0.02;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	// length(MODEL_MATRIX[0].xyz) = world units per local unit (the cumulative
	// parent scale baked into the instance transform). Dividing the local offset
	// by it makes the resulting hull ~`outline_width` metres thick in world space.
	float scale = length(MODEL_MATRIX[0].xyz);
	VERTEX += normalize(NORMAL) * (outline_width / max(scale, 0.0001));
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
