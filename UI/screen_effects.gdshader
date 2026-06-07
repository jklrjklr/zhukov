shader_type canvas_item;
render_mode unshaded;

uniform float brightness : hint_range(-1.0, 1.0) = 0.0;
uniform float contrast   : hint_range(0.5, 2.0)  = 1.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

void fragment() {
	vec3 col = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	col += brightness;
	col  = (col - 0.5) * contrast + 0.5;
	col  = clamp(col, 0.0, 1.0);
	COLOR = vec4(col, 1.0);
}
