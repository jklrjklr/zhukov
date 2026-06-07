// Two-layer FOV: ambient circle around player + directional sight cone.
// Both are centered on the player's screen position, not the screen center.
shader_type canvas_item;

// Player screen position in UV (0-1). Updated every frame.
uniform vec2  player_uv        = vec2(0.5, 0.5);
// Clockwise angle from screen-up (radians). Updated every frame.
uniform float facing_angle     = 0.0;
uniform float aspect_ratio     : hint_range(0.5, 4.0)  = 1.7778;

// Layer 1 — ambient circle (skill-based; wired later)
uniform float ambient_radius   : hint_range(0.0, 0.5)  = 0.12;

// Layer 2 — sight cone (extends to screen edges — no distance cutoff)
uniform float sight_half_angle : hint_range(0.0, 1.6)  = 0.90;  // radians

uniform float dark_alpha       : hint_range(0.0, 1.0)  = 0.88;
uniform float softness         : hint_range(0.001, 0.1) = 0.03;

void fragment() {
	// Offset from player, x corrected for aspect ratio so distance is in screen-height units
	vec2 uv = UV - player_uv;
	uv.x *= aspect_ratio;
	float dist = length(uv);

	// --- Ambient circle ---
	float ambient = 1.0 - smoothstep(
		ambient_radius - softness,
		ambient_radius + softness,
		dist);

	// --- Sight cone ---
	// atan(uv.x, -uv.y): clockwise angle from screen-up (matches facing_angle convention)
	float pixel_angle = atan(uv.x, -uv.y);
	float raw_diff    = pixel_angle - facing_angle;
	// Wrap to [-PI, PI] then take absolute value → [0, PI]
	float angle_diff  = abs(mod(raw_diff + PI, TAU) - PI);

	float in_angle = 1.0 - smoothstep(
		sight_half_angle - softness * 3.0,
		sight_half_angle + softness,
		angle_diff);
	float sight = in_angle;

	// Lit if inside ambient circle OR inside sight cone
	float visibility = max(ambient, sight);

	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - visibility) * dark_alpha);
}
