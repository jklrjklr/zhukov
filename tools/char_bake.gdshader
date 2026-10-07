shader_type spatial;
render_mode unshaded;
// Bake-time character material, flat (cel) shaded so the downsampled sprite reads as pixel art:
// light from straight above (sprites rotate in game, so no side is favoured) in three flat
// bands, no gradients, no grain. Surface colour: the skin texture, with the outfit painted
// into the mesh's vertex colours (tools/reshape_character.py) mixed over it by their alpha
// (outfit = 0: zombies keep their rags); alpha 0.5 marks the face (faceless: skin tone).
uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform float outfit : hint_range(0.0, 1.0) = 1.0;
uniform float faceless : hint_range(0.0, 1.0) = 1.0;
uniform vec2 skin_uv = vec2(0.3153, 0.4051);
// Band thresholds on the up-facing amount, and the band brightness.
uniform vec2 band_at = vec2(0.5, 0.05);
uniform vec3 band_light = vec3(1.0, 0.74, 0.52);

void fragment() {
	vec3 t = texture(skin_tex, UV).rgb;
	float face = (1.0 - step(0.12, abs(COLOR.a - 0.5))) * faceless;
	t = mix(t, texture(skin_tex, skin_uv).rgb, face);
	float cloth = step(0.75, COLOR.a) * COLOR.a * outfit;
	vec3 c = mix(t, COLOR.rgb, cloth);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = wn.y;
	float band = up > band_at.x ? band_light.x : (up > band_at.y ? band_light.y : band_light.z);
	ALBEDO = c * band;
}
