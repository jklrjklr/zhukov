// ADS vignette: darkens + blurs everything outside the circular aperture.
// The aperture is aspect-corrected so it's always a true circle.
shader_type canvas_item;

// Set from GDScript whenever viewport size changes.
uniform float aspect_ratio   : hint_range(0.5, 4.0)  = 1.7778;
uniform float circle_radius  : hint_range(0.05, 0.95) = 0.40;
uniform float softness       : hint_range(0.001, 0.1) = 0.035;
uniform float dark_alpha     : hint_range(0.0, 1.0)   = 0.93;
uniform float blur_strength  : hint_range(0.0, 0.025) = 0.007;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

void fragment() {
    // Aspect-corrected UV so the circle is perfectly round.
    vec2 uv = UV - vec2(0.5);
    uv.x *= aspect_ratio;
    float dist    = length(uv);
    float outside = smoothstep(circle_radius - softness, circle_radius + softness, dist);

    // 4-tap box blur of the scene (sampled before this overlay is composited).
    vec4 s = (
        texture(SCREEN_TEXTURE, SCREEN_UV + vec2(blur_strength, 0.0)) +
        texture(SCREEN_TEXTURE, SCREEN_UV - vec2(blur_strength, 0.0)) +
        texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, blur_strength)) +
        texture(SCREEN_TEXTURE, SCREEN_UV - vec2(0.0, blur_strength))
    ) * 0.25;

    // outside=0 → alpha 0 (fully transparent inside aperture)
    // outside=1 → alpha 1 (fully opaque darkened outside)
    vec3 darkened = s.rgb * (1.0 - dark_alpha);
    COLOR = vec4(darkened, outside);
}
