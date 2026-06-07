// ADS vignette: darkens + blurs everything outside the arc aperture.
// arc_ratio > 1.0 makes the aperture wider than tall (top-down game).
shader_type canvas_item;

uniform float aspect_ratio  : hint_range(0.5, 4.0)  = 1.7778;
uniform float circle_radius : hint_range(0.05, 0.95) = 0.38;
uniform float arc_ratio     : hint_range(0.5, 3.0)   = 1.8;
uniform float softness      : hint_range(0.001, 0.1)  = 0.04;
uniform float dark_alpha    : hint_range(0.0, 1.0)    = 0.93;
uniform float blur_strength : hint_range(0.0, 0.025)  = 0.007;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// arc_ratio > 1 stretches aperture horizontally → wide arc for top-down
	float dist = length(vec2(uv.x * aspect_ratio / arc_ratio, uv.y));
	float outside = smoothstep(circle_radius - softness, circle_radius + softness, dist);

	vec4 s = (
		texture(SCREEN_TEXTURE, SCREEN_UV + vec2(blur_strength, 0.0)) +
		texture(SCREEN_TEXTURE, SCREEN_UV - vec2(blur_strength, 0.0)) +
		texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, blur_strength)) +
		texture(SCREEN_TEXTURE, SCREEN_UV - vec2(0.0, blur_strength))
	) * 0.25;

	vec3 darkened = s.rgb * (1.0 - dark_alpha);
	COLOR = vec4(darkened, outside);
}
