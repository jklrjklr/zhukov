class_name FirearmStats
extends Resource
## Data for one firearm. Units: meters, seconds, degrees (1 m = Firearm.PX_PER_M px).

enum FireMode { SEMI, BURST, AUTO }
enum BulletType { NORMAL, PELLETS, FLECHETTE, INCENDIARY, ROCKET }

@export_group("Identity")
@export var display_name := "Firearm"
## Art id drawn by WeaponArt.
@export var model := ""
@export var caliber := ""

@export_group("Damage")
## Per projectile, before falloff.
@export var damage := 30.0
## Projectiles per shot (pellets).
@export var bullet_count := 1
@export var bullet_type := BulletType.NORMAL
## 0..10. At or above the target's armor class: full damage. Each level below: -25%.
@export_range(0, 10) var armor_penetration := 1
## Durability removed from armor per hit, scaled by the same penetration factor.
@export var armor_damage := 10.0
## 0..100. Objects (crates 3, trees 30, ...) only take damage from weapons at or above
## their level, and then always take the flat base damage (no falloff, no armor).
@export_range(0, 100) var destruction_level := 0
## m: damage falloff starts.
@export var range_min := 25.0
## m: projectile expires.
@export var range_max := 150.0
## Damage fraction left at range_max.
@export_range(0.0, 1.0) var falloff_min_damage := 0.5
## m/s
@export var muzzle_velocity := 400.0
## Impact power of one hit (knockback, slowdown, interrupt, stun build-up).
## Effect on a target = stagger / target weight; scales with range falloff,
## x1.5 on criticals. See Terminid for the rules.
@export var stagger := 10.0

@export_group("Explosive (ROCKET bullets)")
## m blast radius around the impact (0 = none).
@export var blast_radius := 0.0
@export var blast_damage := 0.0

@export_group("Fire control")
@export var rpm := 800.0
@export var fire_modes := PackedInt32Array([FireMode.SEMI, FireMode.AUTO])
@export var burst_count := 3
@export var mag_size := 30
## Closed bolt holds +1 in the chamber; open bolt fires straight from the mag.
@export var closed_bolt := true
@export var spare_mags := 4
## Single-use launcher: thrown away when empty.
@export var disposable := false
## s, round still chambered.
@export var reload_time_tactical := 2.4
## s, chamber empty (needs bolt work).
@export var reload_time_empty := 3.1
## Per shot. A jam blocks firing until cleared with reload (loses a round).
@export_range(0.0, 1.0) var jam_chance := 0.0
@export var jam_clear_time := 1.2

@export_group("Recoil & accuracy")
## Vertical stack added per shot (0..1). Eased: each shot adds less the higher the stack.
## Pushes the camera back and zooms in slightly; also widens spread via recoil_spread.
@export var vertical_recoil := 0.12
## Degrees of aim bounce per shot.
@export var horizontal_recoil := 0.8
## Fraction of bounces that go right (clockwise).
@export_range(0.0, 1.0) var horizontal_recoil_right := 0.6
## Fraction of each bounce that rolls back by itself (speed scales with ergonomics).
@export_range(0.0, 1.0) var recoil_recovery := 0.5
## Degrees, full cone, standing still, no recoil.
@export var bullet_spread := 1.0
## Extra degrees at full movement speed.
@export var moving_spread := 2.0
## Extra degrees at full vertical recoil stack.
@export var recoil_spread := 3.0

@export_group("Handling")
## 0..100: swap speed, recoil roll back, vertical recovery, turn speed, walk sway.
@export_range(0.0, 100.0) var ergonomics := 50.0
## kg, slows movement.
@export var weight := 3.0
## m, butt to muzzle. Firing is blocked while the muzzle is inside a wall.
@export var weapon_length := 0.7
## Loudness of a shot at the muzzle (0..~150; unsuppressed 9mm ~ 100).
@export var sound := 100.0
## % of loudness lost per meter from the muzzle (compounding).
@export_range(0.0, 100.0) var sound_falloff := 4.0
## Sfx slot played per shot (audio/<name>.ogg).
@export var shot_sound := "rifle_shot"

@export_group("Aim down sights")
## Sight cone while aiming (degrees).
@export var ads_fov := 60.0
## m, farthest aim circle distance.
@export var ads_range := 20.0
@export var ads_spread_mult := 0.6
@export var ads_move_mult := 0.55

@export_group("Art")
## px, weapon-local (grip at origin, muzzle toward -Y).
@export var grip_hand := Vector2.ZERO
@export var support_hand := Vector2(0, -18)
## px of stock behind the grip.
@export var stock_length := 10.0
## Where the mag goes in (support hand target during reloads).
@export var mag_well := Vector2(0, -9)
## Cocking lever / charging handle (pulled on empty reload and jam clear).
@export var bolt_handle := Vector2(-4, -20)


func ergo() -> float:
	return ergonomics / 100.0


func swap_time() -> float:
	return lerpf(1.2, 0.35, ergo())


## Vertical stack recovered per second.
func vertical_recovery_rate() -> float:
	return lerpf(1.2, 4.0, ergo())


## How fast the horizontal roll back happens (1/s).
func roll_back_rate() -> float:
	return lerpf(3.0, 12.0, ergo())


## Peak weapon swing (degrees) while walking at full speed.
func move_sway_deg() -> float:
	return lerpf(6.0, 2.0, ergo())


## s to bring the sights up.
func ads_time() -> float:
	return lerpf(0.5, 0.2, ergo())


func turn_multiplier() -> float:
	return lerpf(0.65, 1.0, ergo())


func move_multiplier() -> float:
	return clampf(1.0 - weight * 0.025, 0.6, 1.0)


func shot_interval() -> float:
	return 60.0 / rpm


## Damage multiplier vs an armor class: 1.0 when ap >= armor, -25% per level short.
static func armor_factor(ap: int, armor_class: int) -> float:
	if ap >= armor_class:
		return 1.0
	return maxf(0.0, 1.0 - 0.25 * (armor_class - ap))


## Loudness heard `meters` away from the muzzle.
static func loudness_at(loudness: float, falloff_pct: float, meters: float) -> float:
	return loudness * pow(1.0 - falloff_pct / 100.0, meters)


func damage_at(meters: float) -> float:
	if meters <= range_min:
		return damage
	var t := clampf((meters - range_min) / maxf(range_max - range_min, 0.001), 0.0, 1.0)
	return damage * lerpf(1.0, falloff_min_damage, t)
