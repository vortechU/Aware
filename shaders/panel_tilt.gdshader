shader_type canvas_item;
// Fake-3D "tilt" for the shop panel: ShopTerminal renders the whole panel (holo
// backing + edge frame + every UI control) into a SubViewport, then shows that
// through a SubViewportContainer wearing this shader.
//
// The tilt has to move the QUAD ITSELF, not just warp the picture inside a
// frozen rectangle -- a fragment-only UV warp leaves the outer silhouette
// (the border!) perfectly axis-aligned and just clips the warped content
// against it. `vertex()` shears the four corners in local pixel space (scaled
// by `panel_size`, since VERTEX is in pixels but UV is 0..1), so the whole
// panel -- border included -- reads as one rigid tilted card. `fragment()`
// only adds a specular glare band sliding opposite the lean, reinforcing the
// "glass slab catching the light" read. Purely visual: the real Controls
// underneath keep their normal click rects, so SubViewportContainer's input
// forwarding stays accurate except at extreme tilt.

uniform vec2 tilt = vec2(0.0);          // x: left/right lean, y: up/down lean
uniform vec2 panel_size = vec2(1.0);    // TiltView's current size in pixels
uniform float shear_strength = 0.06;    // how far the corners shift, as a
                                         // fraction of the panel's own size
uniform float glare_strength = 0.35;
uniform float glare_width = 0.35;
uniform vec3 glare_tint : source_color = vec3(0.55, 0.9, 0.8);

void vertex() {
	// Opposite edges shear in opposite directions -- top/bottom slide apart
	// horizontally with tilt.y, left/right slide apart vertically with tilt.x --
	// turning the flat rect into a leaning parallelogram.
	VERTEX.x += tilt.y * (UV.y - 0.5) * shear_strength * panel_size.x;
	VERTEX.y -= tilt.x * (UV.x - 0.5) * shear_strength * panel_size.y;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// A soft light band sweeping opposite the lean.
	float diag = UV.x - UV.y;
	float glare_pos = (tilt.x - tilt.y) * 0.5;
	float glare = 1.0 - smoothstep(0.0, glare_width, abs(diag - glare_pos));
	col.rgb += glare_tint * glare * glare_strength * col.a;

	COLOR = col;
}
