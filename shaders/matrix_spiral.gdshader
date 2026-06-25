shader_type canvas_item;
// Matrix-style binary spiral, used as a full-screen room-transition cover.
//
// Screen space is mapped to polar coordinates and tiled into cells; the angular
// coordinate is twisted by the radius so the cells wind into spiral arms, and
// the whole field rotates with TIME. Each cell shows a flickering binary digit
// (a "1" bar or a "0" ring) in matrix green, with a brightness head streaming
// outward like falling code.
//
// `cover` (0..1) fades the whole overlay via alpha so it doubles as a smooth
// transition: at cover = 1 the gaps are opaque near-black (the game is hidden),
// at cover = 0 it is fully transparent (the room behind shows through).
//
// TAU / PI are built-in shader constants in Godot, so they are used directly.

uniform vec4 tint : source_color = vec4(0.18, 1.0, 0.45, 1.0);
uniform float cover : hint_range(0.0, 1.0) = 1.0;
uniform float spin_speed = 0.5;   // angular rotation rate
uniform float arms = 20.0;        // angular cells per full turn
uniform float rings = 18.0;       // radial cells
uniform float twist = 4.0;        // how tightly arms wind into a spiral
uniform float stream_speed = 0.7; // outward code-stream rate


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}


// Blocky binary glyph inside a cell (cell uv in 0..1). one > 0.5 -> "1" bar,
// otherwise a "0" ring.
float glyph(vec2 c, float one) {
	vec2 g = (c - 0.5) / 0.34;                 // glyph area roughly [-1, 1]
	float box = step(max(abs(g.x), abs(g.y)), 1.0);
	if (one > 0.5) {
		return box * step(abs(g.x), 0.32);     // vertical bar
	}
	float inner = step(max(abs(g.x), abs(g.y)), 0.5);
	return box - inner;                        // ring
}


void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = size.x / max(size.y, 1.0);
	vec2 p = UV - 0.5;
	p.x *= aspect;

	float r = length(p);
	float a = atan(p.y, p.x);                   // -PI..PI
	float t = TIME;

	// Spiral cell space: angular coord twisted by radius + rotated by time;
	// radial bands stream outward.
	float ang = a / TAU;                        // -0.5..0.5
	float a_cells = max(floor(arms), 1.0);      // integer arm count
	float u = ang * a_cells + r * twist + t * spin_speed;
	float v = r * rings - t * stream_speed;
	// Wrap the angular cell index modulo the arm count. Across the atan seam
	// (a = ±PI) u jumps by exactly a_cells, so mod() makes the cell id -- and
	// thus the digit/brightness hash -- identical on both sides: no visible join.
	vec2 cid = vec2(mod(floor(u), a_cells), floor(v));
	vec2 cuv = fract(vec2(u, v));

	float h = hash21(cid + 7.3);
	float is_one = step(0.5, hash21(cid + 1.7));
	// Flicker: re-roll the cell on/off at a cell-specific cadence.
	float fl = hash21(cid + floor(t * (1.5 + h * 4.0)) * 0.137);
	float on = step(0.28, fl);

	float gl = glyph(cuv, is_one) * on;

	// Bright head streaming outward through the rings.
	float wave = fract(r * 2.5 - t * stream_speed);
	float head = smoothstep(0.0, 0.08, wave) * smoothstep(0.55, 0.12, wave);

	float bright = (0.30 + 0.70 * head) * (0.55 + 0.45 * h);
	vec3 col = tint.rgb * gl * bright;

	col += tint.rgb * smoothstep(0.16, 0.0, r) * 0.5;  // glowing core
	col += tint.rgb * 0.025;                            // faint ambient fill
	float vig = smoothstep(1.10, 0.35, r);             // corner vignette
	col *= mix(0.5, 1.0, vig);

	COLOR = vec4(col, cover);
}
