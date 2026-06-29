shader_type spatial;
// Death "deletion" effect: the enemy is wiped out of the world like a corrupted
// process being killed. A blocky cell-noise dissolve eats the mesh away in little
// digital squares (driven by `dissolve` 0->1), each freshly-deleted cell flaring a
// hot emissive edge; an RGB-split + scanline flicker + per-vertex jitter sell the
// glitch. DeletionVFX swaps this onto the corpse meshes on death and tweens
// `dissolve` to 1, carrying over the enemy's own albedo so it still reads as THAT
// enemy dissolving. cull_disabled so the thinning shell shows from both sides.
render_mode cull_disabled;

// The enemy's own look, copied over by DeletionVFX (white default = colour-only).
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);

uniform float dissolve : hint_range(0.0, 1.0) = 0.0;     // 0 intact -> 1 gone
uniform vec3 edge_color : source_color = vec3(0.35, 1.0, 0.65);  // hot "delete" glow
uniform float edge_width : hint_range(0.0, 0.5) = 0.14;
uniform float cell : hint_range(4.0, 80.0) = 26.0;       // dissolve block density
uniform float glitch : hint_range(0.0, 2.0) = 1.0;       // jitter / RGB-split amount
uniform float jitter : hint_range(0.0, 0.1) = 0.012;     // per-vertex wobble (0 = clean fade)
uniform float emission_boost : hint_range(0.0, 8.0) = 4.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	// A corruption wobble that grows as the body is deleted (jitter tunes the spikiness).
	float j = hash(vec2(float(VERTEX_ID) * 0.013, TIME)) - 0.5;
	VERTEX += NORMAL * j * jitter * dissolve * glitch;
}

void fragment() {
	// Blocky per-cell noise -> a digital, not-smooth dissolve.
	vec2 cuv = floor(UV * cell) / cell;
	float n = hash(cuv);

	// Cells whose threshold is already passed are deleted.
	if (n < dissolve) {
		discard;
	}

	// RGB-split sampling for the glitchy read (grows with the dissolve).
	float split = 0.02 * glitch * smoothstep(0.0, 1.0, dissolve);
	vec3 col;
	col.r = texture(albedo_tex, UV + vec2(split, 0.0)).r;
	col.g = texture(albedo_tex, UV).g;
	col.b = texture(albedo_tex, UV - vec2(split, 0.0)).b;
	col *= albedo_color.rgb;

	// Scanline flicker.
	col *= 0.85 + 0.15 * sin(UV.y * 140.0 + TIME * 40.0);
	ALBEDO = col;

	// Hot edge on the cells about to be deleted + a global glitch flash.
	float edge = 1.0 - smoothstep(dissolve, dissolve + edge_width, n);
	EMISSION = edge_color * edge * emission_boost;
	EMISSION += edge_color * dissolve * 0.6 * (0.5 + 0.5 * sin(TIME * 60.0));
	ROUGHNESS = 0.8;
}
