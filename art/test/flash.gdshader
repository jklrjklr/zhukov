shader_type canvas_item;
// Hit flash: solid near-white silhouette (1-2 frames).
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(1.0, 0.97, 0.9, c.a * COLOR.a);
}
