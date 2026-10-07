shader_type canvas_item;
// Upscale for the low-res world buffer, plus lighting and the final grade, all in this one
// pass (no extra render targets, no screen reads).
// Sharp bilinear: inside a pixel samples its centre (hard, square pixels); across a pixel
// border it blends over ~1 screen pixel, which removes the uneven-pixel-width shimmer of
// plain nearest at non-integer scales. One bilinear tap (node texture_filter must be LINEAR).

// Lantern: a warm light around light_px (buffer pixels), dark cool ambient elsewhere.
// The falloff is computed per BUFFER pixel and stepped into bands with a dithered edge,
// so the light itself looks pixel-art.
uniform vec2 light_px = vec2(0.0);
uniform float light_radius = 150.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 ambient : source_color = vec3(0.5, 0.55, 0.72);
uniform float light_bands = 4.0;
// Darkening toward the screen corners (0 = off), pulled toward a cool shadow tint.
uniform float vignette : hint_range(0.0, 1.0) = 0.45;
uniform vec3 shadow_tint : source_color = vec3(0.04, 0.03, 0.08);
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
uniform float saturation : hint_range(0.0, 2.0) = 1.15;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.y * 4 + i.x;
	// 4x4 ordered dither thresholds, row-major.
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = UV * size;
	vec2 seam = floor(px + 0.5);
	vec2 dudv = max(fwidth(px), vec2(1e-5));
	vec2 spx = seam + clamp((px - seam) / dudv, -0.5, 0.5);
	vec3 c = texture(TEXTURE, spx / size).rgb;

	// Stepped, dithered light per buffer pixel.
	vec2 cell = floor(px);
	float f = clamp(1.0 - distance(cell + 0.5, light_px) / light_radius, 0.0, 1.0);
	f = f * f * (3.0 - 2.0 * f) * light_bands;
	f = (floor(f) + step(bayer4(cell), fract(f))) / light_bands;
	c *= mix(ambient, light_color * 1.15, f);

	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;

	vec2 v = SCREEN_UV - 0.5;
	float k = clamp(dot(v, v) * 2.2 * vignette, 0.0, 1.0);
	c = mix(c, shadow_tint, k);
	COLOR = vec4(c, 1.0);
}
