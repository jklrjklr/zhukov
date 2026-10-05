class_name Awareness
extends RefCounted
## Enemy awareness rules shared by all bugs (Terminid, Charger).
##   UNAWARE -> SUSPICIOUS -> ALERT, per enemy.
## - Sounds and partial sightings raise a SUSPICION meter (0..1). A suspicious enemy turns and walks
##   to investigate the cue; its "?" icon fills with the meter. Suspicion decays over DECAY_S seconds
##   without cues.
## - ALERT needs the identified player: line of sight inside the sight cone held for a dwell time that
##   grows with distance (0.4 s at <= 10 m, 1.5 s at 40 m), or being hit by the player (instant).
##   ALERT is never broadcast. Only suspicion spreads: a suspicious / alert enemy raises the
##   suspicion of same-faction enemies within SPREAD_M (they investigate; they do not learn where
##   the player is).
## - Hearing: gunfire is never heard beyond GUN_CAP_M (hard cap) and gets quieter with distance;
##   explosions carry to EXPLOSION_CAP_M; footsteps / sprint only a few metres.
## - Only an ALERT enemy of a type with the reinforcement call gimmick (breach callers) calls, and
##   the call is a visible CALL_TIME s action that is cancelled if the caller is killed or staggered.

enum Level { UNAWARE, SUSPICIOUS, ALERT }
enum Sound { GUNFIRE, EXPLOSION, FOOTSTEP }

const GUN_CAP_M := 50.0
const EXPLOSION_CAP_M := 80.0
const FOOTSTEP_WALK_M := 6.0
const FOOTSTEP_SPRINT_M := 12.0
## Meter value from which an enemy counts as suspicious (and investigates) / drops back to unaware.
const SUSPICIOUS_AT := 0.2
const UNAWARE_BELOW := 0.08
const DECAY_S := 8.0
const QUIET_GRACE_S := 0.5
const SPREAD_M := 15.0
const SPREAD_FACTOR := 0.7
const DWELL_NEAR_M := 10.0
const DWELL_FAR_M := 40.0
const DWELL_NEAR_S := 0.4
const DWELL_FAR_S := 1.5
const CALL_TIME := 2.0


## Hard distance cap (m) of a sound.
static func cap_m(kind: int, loudness: float) -> float:
	match kind:
		Sound.EXPLOSION:
			return EXPLOSION_CAP_M
		Sound.FOOTSTEP:
			return FOOTSTEP_SPRINT_M if loudness >= 75.0 else FOOTSTEP_WALK_M
		_:
			return minf(GUN_CAP_M, GUN_CAP_M * loudness / 100.0)


## Suspicion a sound adds `meters` away (0 beyond the cap): falls off linearly with distance.
static func sound_gain(kind: int, loudness: float, meters: float) -> float:
	var cap := cap_m(kind, loudness)
	if meters >= cap:
		return 0.0
	var k := 1.0 - meters / cap
	match kind:
		Sound.EXPLOSION:
			return minf(1.2 * k + 0.2, 1.0)
		Sound.FOOTSTEP:
			return 0.35 * k
		_:
			return 0.8 * k


## Seconds the player has to stay in sight to be identified at `meters`.
static func dwell_time(meters: float) -> float:
	return lerpf(DWELL_NEAR_S, DWELL_FAR_S, clampf((meters - DWELL_NEAR_M) / (DWELL_FAR_M - DWELL_NEAR_M), 0.0, 1.0))
