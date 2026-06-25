shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled;
// Spatial sibling of matrix_spiral.gdshader for the exit-gate portal surface.
// Same binary-spiral field, but sampled from the quad's own UV and written as an
// unshaded, semi-transparent emissive pane so the doorway reads as a live portal
// of falling code. ToonApplicator never touches it (the gate is an Area3D, not
// one of the node types it filters), so this material survives untouched.
//
// TAU / PI are built-in shader constants in Godot, so they are used directly.

uniform vec4 tint : source_color = vec4(0.18, 1.0, 0.45, 1.0);
uniform float spin_speed = 0.5;
uniform float arms = 16.0;
uniform float rings = 14.0;
uniform float twist = 4.0;
uniform float stream_speed = 0.7;
uniform float aspect = 0.71;   // portal is taller than wide (≈ 3.0 / 4.2)


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}


float glyph(vec2 c, float one) {
	vec2 g = (c - 0.5) / 0.34;
	float box = step(max(abs(g.x), abs(g.y)), 1.0);
	if (one > 0.5) {
		return box * step(abs(g.x), 0.32);
	}
	float inner = step(max(abs(g.x), abs(g.y)), 0.5);
	return box - inner;
}


void fragment() {
	vec2 p = UV - 0.5;
	p.x *= aspect;

	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME;

	float ang = a / TAU;
	float a_cells = max(floor(arms), 1.0);      // integer arm count
	float u = ang * a_cells + r * twist + t * spin_speed;
	float v = r * rings - t * stream_speed;
	// Wrap the angular cell index so the pattern matches across the atan seam.
	vec2 cid = vec2(mod(floor(u), a_cells), floor(v));
	vec2 cuv = fract(vec2(u, v));

	float h = hash21(cid + 7.3);
	float is_one = step(0.5, hash21(cid + 1.7));
	float fl = hash21(cid + floor(t * (1.5 + h * 4.0)) * 0.137);
	float on = step(0.28, fl);

	float gl = glyph(cuv, is_one) * on;
	float wave = fract(r * 2.5 - t * stream_speed);
	float head = smoothstep(0.0, 0.08, wave) * smoothstep(0.55, 0.12, wave);
	float bright = (0.35 + 0.65 * head) * (0.55 + 0.45 * h);

	vec3 col = tint.rgb * gl * bright;
	col += tint.rgb * smoothstep(0.14, 0.0, r) * 0.6;  // glowing core
	col += tint.rgb * 0.05;

	ALBEDO = col;
	EMISSION = col;
	ALPHA = clamp(max(gl * bright, head * 0.35) + 0.12, 0.0, 1.0);
}
