class_name SightData
extends RefCounted

var display_name: String  = "Iron Sights"
var reticle_type: String  = "dot"    # "dot" | "crosshair" | "none"
var ergo_mult: float      = 0.85     # ergonomics multiplier while ADS (<1 = penalty)
var scope_mult: float     = 1.0      # 1.3 = camera sees 30% further when ADS
var fov_radius: float     = 0.40     # vignette aperture radius (fraction of screen height)

static func from_dict(d: Dictionary) -> SightData:
	var s := SightData.new()
	s.display_name = d.get("display_name", "Iron Sights")
	s.reticle_type = d.get("reticle_type", "dot")
	s.ergo_mult    = d.get("ergo_mult",    0.85)
	s.scope_mult   = d.get("scope_mult",   1.0)
	s.fov_radius   = d.get("fov_radius",   0.40)
	return s

# Default iron-sight values used when no sight is configured.
static func iron_sights() -> SightData:
	return SightData.new()
