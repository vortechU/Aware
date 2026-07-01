shader_type canvas_item;
// Holographic-terminal panel background for the in-world shop (ShopTerminal).
// Drawn on a single ColorRect BEHIND the panel content (mouse_filter = ignore).
// Pure emissive fill -- it never samples the screen (no hint_screen_texture), so
// unlike ui_glitch.gdshader it has no back-buffer / multi-overlay interaction and
// can coexist with any other screen-space effect. Matrix-green to match the
// project's computer-world palette (deletion VFX / transition shaders).

uniform vec3 tint : source_color = vec3(0.20, 1.00, 0.55);   // body + scanline colour
uniform vec3 edge_tint : source_color = vec3(0.55, 1.00, 0.85); // border + sweep glow
uniform float fill_alpha = 0.30;   // base panel opacity
uniform float scan_count = 90.0;   // horizontal scanline density
uniform float sweep_speed = 0.22;  // vertical bright "refresh" band speed
uniform float flicker = 0.05;      // brightness jitter amount
uniform float edge_glow = 1.0;     // border-glow strength
uniform float edge_width = 0.045;  // how far the border glow bleeds inward (UV)

float hash(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void fragment() {
	vec2 uv = UV;

	// --- base translucent fill ---
	vec3 col = tint * 0.14;
	float a = fill_alpha;

	// --- horizontal scanlines ---
	float scan = 0.5 + 0.5 * sin(uv.y * scan_count * 6.2831);
	col += tint * scan * 0.06;

	// --- moving bright "refresh" band sweeping up the panel ---
	float band = fract(uv.y + TIME * sweep_speed);
	float sweep = smoothstep(0.94, 1.0, band);
	col += edge_tint * sweep * 0.45;
	a += sweep * 0.20;

	// --- border glow: brighten toward the nearest edge ---
	float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float edge = smoothstep(edge_width, 0.0, d) * edge_glow;
	col += edge_tint * edge * 0.85;
	a += edge * 0.55;

	// --- subtle CRT flicker ---
	col *= 1.0 - flicker * hash(floor(TIME * 30.0));

	COLOR = vec4(col, clamp(a, 0.0, 1.0)) * COLOR;
}
