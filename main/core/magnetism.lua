-- Magnetized attraction (PRD 4.4/4.8). Unlike every other package state
-- implemented so far, Magnetized's force does NOT apply to the package's own
-- physics — it pulls nearby HAZARDS toward the package instead. Hazards
-- don't exist yet (they arrive with phase 9a), so there is nothing for
-- package.script to apply this force to this phase; this module exists so
-- the pure math is built and unit-tested now, ready for a future hazard
-- adapter to call via go.get_position("/package") and
-- go.get("/package#script", "current_state") == hash("magnetized") — both
-- already exposed synchronously by package.script (rule 4), so no new
-- package.script wiring is needed for a hazard to use this. Note the hash:
-- current_state is stored as a hash (see package.script), and a
-- hash-vs-string == is always false in Lua, never true. No Defold API calls
-- here (rule 1); this is plain geometry, not an engine physics query
-- (rule 9).

local M = {}

-- PRD 4.8's MAGNET_RADIUS. DEFAULT_STRENGTH has no PRD source — the PRD
-- specifies only the radius, not a force magnitude — so 150 is an initial
-- guess, sized to match Panic's impulse forces (80-160), to be tuned during
-- phase 22's playtest pass rather than hunted for in the spec.
local DEFAULT_RADIUS = 95
local DEFAULT_STRENGTH = 150

-- Returns the attraction force { x, y } pulling a point at (target_x,
-- target_y) — a hazard, once phase 9a exists — toward (package_x,
-- package_y). Zero force outside `radius`, and zero (rather than dividing
-- by zero) if the target is exactly at the package's own position. The
-- magnitude is constant (`strength`) anywhere within radius, not
-- distance-scaled — the PRD specifies a radius and "applies an attraction
-- force," not a falloff curve, so this is the simplest behavior matching
-- that spec rather than an invented one.
function M.attraction_force(package_x, package_y, target_x, target_y, config)
	config = config or {}
	local radius = config.radius or DEFAULT_RADIUS
	local strength = config.strength or DEFAULT_STRENGTH

	local dx = package_x - target_x
	local dy = package_y - target_y
	local distance = math.sqrt(dx * dx + dy * dy)

	if distance > radius or distance == 0 then
		return { x = 0, y = 0 }
	end

	return { x = (dx / distance) * strength, y = (dy / distance) * strength }
end

return M
