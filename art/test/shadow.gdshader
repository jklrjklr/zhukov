shader_type canvas_item;
// Soft dark drop shadow from a sprite's own silhouette (placed offset to the bottom-right in world space).
uniform float radius = 2.4;
uniform float strength = 0.42;
varying float va;
void vertex() { va = COLOR.a; }
void fragment() {
	vec2 px = radius / vec2(textureSize(TEXTURE, 0));
	float a = texture(TEXTURE, UV).a * 2.0;
	a += texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	a += texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
	a += texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	a += texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	a += texture(TEXTURE, UV + px).a;
	a += texture(TEXTURE, UV - px).a;
	a += texture(TEXTURE, UV + vec2(px.x, -px.y)).a;
	a += texture(TEXTURE, UV + vec2(-px.x, px.y)).a;
	a /= 10.0;
	COLOR = vec4(0.02, 0.03, 0.06, a * strength * va);
}
