shader_type canvas_item;
// Digital-glitch overlay for the roguelite upgrade cards. One full-screen rect
// (mouse_filter = ignore) drawn ABOVE the cards, so the single automatic
// back-buffer copy already contains every card (three separate overlays each
// using SCREEN_TEXTURE only get one copy between them, so the later cards would
// sample a stale buffer -- hence one overlay).
//
// run_hud.gd feeds it the card-row rect (`cards_min/max`) for the resting IDLE
// shimmer on all three cards, plus the hovered/clicked card's rect
// (`focus_rect`) and level (`focus_intensity`) for the HOVER and CLICK states.
// Outside the card row it passes the screen through untouched. TIME keeps
// advancing while the tree is paused (like the matrix wipe), so it animates on
// the paused upgrade screen. Matrix-green tint to match the transition shader.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 cards_min = vec2(0.0);    // card-row bounding rect, screen UV
uniform vec2 cards_max = vec2(0.0);
uniform float base_intensity = 0.0;    // resting idle glitch over the whole row
uniform vec4 focus_rect = vec4(0.0);   // hovered/clicked card: xy = min, zw = max (screen UV)
uniform float focus_intensity = 0.0;   // hover / click level for the focused card
uniform vec3 glitch_tint : source_color = vec3(0.4, 1.0, 0.55);
uniform float block_count = 24.0;      // horizontal slices
uniform float max_shift = 0.013;       // largest sideways slice tear (screen UV) at full intensity
uniform float rgb_split = 0.0045;      // chromatic aberration at full intensity
uniform float speed = 12.0;            // glitch re-roll rate (snaps between frames)

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.13, 289.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float in_cards = step(cards_min.x, uv.x) * step(uv.x, cards_max.x)
			* step(cards_min.y, uv.y) * step(uv.y, cards_max.y);
	float in_focus = step(focus_rect.x, uv.x) * step(uv.x, focus_rect.z)
			* step(focus_rect.y, uv.y) * step(uv.y, focus_rect.w);
	float amt = max(base_intensity * in_cards, focus_intensity * in_focus);

	if (amt <= 0.001) {
		// Outside the cards (title, shade) or no glitch: pass through untouched.
		COLOR = texture(screen_tex, uv);
	} else {
		float t = floor(TIME * speed);  // stepped time -> digital, not smooth

		// --- horizontal slice displacement: only the noisiest bands tear, and
		// more of them light up as intensity climbs ---
		float band = floor(uv.y * block_count);
		float r = hash21(vec2(band, t));
		float active = step(1.0 - amt * 0.85, r);
		float dir = (hash21(vec2(band, t + 7.0)) - 0.5) * 2.0;
		float shift = dir * max_shift * amt * active;
		shift += sin(uv.y * 90.0 + TIME * 28.0) * 0.0015 * amt;  // fine high-freq jitter

		vec2 suv = uv;
		suv.x += shift;

		// --- chromatic aberration (R/B pulled apart, stronger on torn bands) ---
		float ca = rgb_split * amt * (0.5 + active);
		float cr = texture(screen_tex, suv + vec2(ca, 0.0)).r;
		vec4 cmid = texture(screen_tex, suv);
		float cb = texture(screen_tex, suv - vec2(ca, 0.0)).b;
		vec4 col = vec4(cr, cmid.g, cb, cmid.a);

		// --- digital scanlines ---
		float scan = 0.85 + 0.15 * sin(uv.y * block_count * 6.2831);
		col.rgb *= mix(1.0, scan, amt * 0.5);

		// --- occasional matrix-green "data" flash on torn bands ---
		float flash = step(0.93, hash21(vec2(band, t + 19.0))) * active * amt;
		col.rgb += glitch_tint * flash * 0.6;

		COLOR = col;
	}
}
