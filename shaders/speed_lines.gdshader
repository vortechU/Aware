shader_type canvas_item;
// Screen-edge "speed lines" / wind-streak overlay for fast movement. One
// full-screen rect (mouse_filter = ignore) owned in code by the SpeedLines node
// (child of Player), so it shows in runs AND the sandbox with no HUD edit.
//
// Pure additive tint -- it does NOT sample the screen, so it never touches the
// back-buffer (no interaction with the upgrade-card glitch overlay). Radial
// streaks point toward the centre and are masked to the edges/corners, so the
// middle of the view stays clear (the crosshair reads); they "run" inward and
// flicker over TIME. `intensity` (0..1) is driven from speed_lines.gd; the rest
// are designer tunables. `aspect` keeps the ring circular on a wide viewport.

uniform float intensity = 0.0;                              // 0..1, from the script (speed-driven)
uniform vec3 tint : source_color = vec3(0.78, 0.93, 1.0);  // cool white, faint cyan
uniform float line_count = 150.0;                          // angular streak density (kept ~integer)
uniform float line_sharpness : hint_range(0.0, 1.0) = 0.72; // 0 = soft wind, 1 = razor speed lines
uniform float edge_start = 0.82;                           // radius (0..~1.4) where streaks begin (bigger = clearer centre)
uniform float edge_end = 1.05;                             // radius where streaks reach full strength
uniform float scroll_speed = 3.0;                          // inward "run" speed of the streaks
uniform float flicker_speed = 9.0;                         // per-streak twinkle rate
uniform float aspect = 1.7777;                             // viewport width / height
uniform float max_alpha : hint_range(0.0, 1.0) = 0.42;     // opacity cap at full intensity

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	if (intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		// Centre + aspect-correct so the streaks are radial, not elliptical.
		vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
		float r = length(p) * 2.0;            // ~0 centre, ~1 mid-edge, up to ~1.4 at corners
		float a = atan(p.y, p.x) / 6.2831853 + 0.5;  // 0..1 around the ring

		// Edge mask: clear centre, full at the rim/corners -> "around the corners".
		float edge = smoothstep(edge_start, edge_end, r);

		// Evenly spaced streaks, sharpened into thin lines.
		float streak = abs(sin(a * line_count * 3.1415927));
		streak = pow(streak, mix(3.0, 26.0, line_sharpness));

		// Per-streak variety + flicker so they don't read as a static fan.
		float idx = floor(a * line_count);
		float seed = hash11(idx);
		float tw = 0.55 + 0.45 * sin(TIME * flicker_speed + seed * 30.0);

		// Inward-moving radial band -> the streaks "run" toward the centre.
		float flow = 0.5 + 0.5 * sin(r * 16.0 - TIME * scroll_speed - seed * 6.2831853);

		float lines = streak * tw * flow;
		float alpha = lines * edge * intensity * max_alpha;
		COLOR = vec4(tint, clamp(alpha, 0.0, 1.0));
	}
}
