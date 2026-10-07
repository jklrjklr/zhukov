shader_type canvas_item;
// Sharp-bilinear upscale for the low-res world buffer: inside a pixel samples its centre
// (hard, square pixels); across a pixel border it blends over ~1 screen pixel, which
// removes the uneven-pixel-width shimmer of plain nearest at non-integer scales.
// One bilinear tap per fragment (the node's texture_filter must be LINEAR).

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = UV * size;
	vec2 seam = floor(px + 0.5);
	vec2 dudv = max(fwidth(px), vec2(1e-5));
	px = seam + clamp((px - seam) / dudv, -0.5, 0.5);
	COLOR = texture(TEXTURE, px / size);
}
