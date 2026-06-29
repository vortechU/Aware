shader_type spatial;
// Cel / toon shading. A custom light() function quantizes the diffuse term into
// a handful of hard bands; a fresnel rim adds the comic edge-light. Specular is
// left flat. Ambient (from the environment) still fills the unlit side, so the
// darkest band reads as shadow rather than pure black.
//
// Driven entirely by uniforms so one shader serves every cel-shaded surface;
// ToonApplicator sets albedo (+ optional skin texture) + emission per mesh at
// runtime.
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Optional skin/diffuse map, multiplied by `albedo`. Defaults to white, so a mesh
// with no texture (every flat-coloured enemy/weapon/pickup/world surface) is shaded
// exactly as before; a textured rig (the Kenney character) carries its skin through.
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
