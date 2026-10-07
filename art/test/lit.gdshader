shader_type canvas_item;
// Rotation-proof 3-tone shading: base / cold shadow / crisp pale highlight.
// The data map (hmap) holds blurred heights; slopes are sampled along the WORLD light direction
// (fixed key light from the top-left), converted into the sprite's local space every frame.
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform vec2 light_dir = vec2(-0.7071, -0.7071);
uniform float d_w = 2.6;
uniform float d_n = 1.0;
uniform float t_sh = 0.03;
uniform float t_hl = 0.035;
uniform vec3 sh_tint = vec3(0.50, 0.55, 0.70);
uniform vec3 hl_col = vec3(0.95, 0.94, 0.88);
uniform float hl_mix = 0.5;
varying vec2 ld;
varying vec4 vmod;

void vertex() {
	mat2 m = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	ld = normalize(inverse(m) * light_dir);
	vmod = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	vec3 h0 = texture(hmap, UV).rgb;
	float sw = texture(hmap, UV - ld * d_w / ts).r - texture(hmap, UV + ld * d_w / ts).r;
	float sn = texture(hmap, UV - ld * d_n / ts).g - texture(hmap, UV + ld * d_n / ts).g;
	float inside = step(0.25, h0.b);
	float emi = step(0.75, h0.b);
	float sh = (1.0 - smoothstep(-t_sh - 0.012, -t_sh + 0.012, sw)) * inside * (1.0 - emi);
	float hl = smoothstep(t_hl - 0.012, t_hl + 0.012, sn) * inside * (1.0 - emi) * (1.0 - sh);
	vec3 col = c.rgb;
	col = mix(col, col * sh_tint, sh);
	col = mix(col, mix(col, hl_col, hl_mix), hl);
	col = mix(col, col + vec3(0.12, 0.1, 0.05), emi);
	COLOR = vec4(col * vmod.rgb, c.a * vmod.a);
}
