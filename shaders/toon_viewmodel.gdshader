shader_type spatial;
// Viewmodel variant of toon.gdshader. IDENTICAL cel shading -- the ONLY change is
// the render_mode: `depth_test_disabled` makes the first-person weapon draw on top
// of world geometry regardless of depth, so the gun never clips into walls /
// crates / pillars when the player stands close. `depth_draw_opaque` keeps the
// fill writing depth, so the model self-sorts (barrel over body) AND the
// inverted-hull outline (next_pass, depth-tested) still reads as a clean
// silhouette instead of flooding the whole gun with ink.
//
// This is the "render through walls" approach (vs pushing the weapon back toward
// the eye): the gun simply ignores the wall. WeaponClip swaps body+barrel meshes
// from toon.gdshader to this shader at runtime (uniforms carry over unchanged).
//
// `cull_disabled` (vs toon.gdshader's `cull_back`): the real weapon GLBs are ripped
// Sketchfab meshes whose materials are ALL authored double-sided (cull=DISABLED) --
// thin single-sided shells with inconsistent winding. Culling their back faces
// leaves see-through holes ("some materials look transparent"), so the viewmodel
// draws both sides. fragment() flips NORMAL on back faces so the cel light() shades
// them as a real surface instead of shadow.
//
// KEEP IN SYNC with toon.gdshader: only render_mode + the FRONT_FACING flip differ.
render_mode cull_disabled, depth_test_disabled, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Optional skin/diffuse map, multiplied by `albedo`. Defaults to white, so a mesh
// with no texture is shaded exactly as before; a textured weapon model (or the
// Kenney character rig) carries its texture through the WeaponClip swap too.
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest;
uniform int bands : hint_range(1, 5) = 3;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim_width : hint_range(0.0, 1.0) = 0.7;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 4.0) = 0.0;

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = emission_color.rgb * emission_energy;
	// Double-sided (cull_disabled): a back face keeps its outward geometric normal,
	// which points away from the light -> it would band as pure shadow. Flip it so
	// the newly-visible inner faces read as a lit surface, not a black hole.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	// Quantize N.L into `bands` discrete levels spanning 0 .. 1. Dividing by
	// (bands - 1) makes the brightest band reach full intensity instead of
	// stopping short, so 3 bands give a clean 0 / 0.5 / 1.0 ramp.
	float ndl = dot(NORMAL, LIGHT);
	float levels = float(bands);
	float stepped = floor(clamp(ndl, 0.0, 0.999) * levels) / max(levels - 1.0, 1.0);
	vec3 diffuse = ALBEDO * LIGHT_COLOR * stepped * ATTENUATION;

	// Rim light: brightens grazing angles, gated to the lit side so it doesn't
	// glow in shadow.
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(rim_width, rim_width + 0.06, fresnel);
	rim *= rim_strength * clamp(ndl, 0.0, 1.0);
	diffuse += rim * rim_color.rgb * LIGHT_COLOR;

	DIFFUSE_LIGHT += diffuse;
}
