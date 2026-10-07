shader_type spatial;
// Bake-time character material: the skin texture, with the outfit painted into the mesh's
// vertex colours (tools/reshape_character.py: suit colours x crease shading) mixed over it by
// their alpha. outfit = 0 shows the plain skin (zombies keep their rags).
// Cloth gets a fine grain (UV-space, so it doesn't swim between frames), a satin sheen and a
// soft rim so black fabric shows its form instead of reading as a flat silhouette.
uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform float outfit : hint_range(0.0, 1.0) = 1.0;
// Faceless: vertex alpha 0.5 marks the face; it takes the skin tone found at skin_uv (neck).
uniform float faceless : hint_range(0.0, 1.0) = 1.0;
uniform vec2 skin_uv = vec2(0.3153, 0.4051);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 t = texture(skin_tex, UV).rgb;
	float face = (1.0 - step(0.12, abs(COLOR.a - 0.5))) * faceless;
	t = mix(t, texture(skin_tex, skin_uv).rgb, face);
	float cloth = step(0.75, COLOR.a) * COLOR.a * outfit;
	vec3 c = mix(t, COLOR.rgb, cloth);
	float grain = hash(floor(UV * 96.0)) * 0.5 + hash(floor(UV * 37.0)) * 0.5;
	c *= mix(1.0, 0.82 + 0.36 * grain, cloth);
	ALBEDO = c;
	float dark = 1.0 - smoothstep(0.1, 0.4, dot(COLOR.rgb, vec3(0.33)));
	ROUGHNESS = mix(0.85, 0.66, cloth * dark);
	SPECULAR = mix(0.5, 0.35, cloth);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.07, 0.07, 0.085) * rim * cloth * dark;
}
