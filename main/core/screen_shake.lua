-- Camera shake, on the usual "trauma" model (PRD section 11's "o pacote
-- reage de forma visível" — an explosion or a hard landing should be felt,
-- not just seen).
--
-- Pure Lua, no Defold API calls (rule 1). State in, new state out (rule 2).
-- Time is injected, never read from a clock (rule 3).
--
-- Trauma rather than "shake for N frames": events ADD trauma, trauma decays
-- continuously, and the offset is derived from however much is left. That
-- makes overlapping events compose — a detonation during a hard landing
-- shakes harder than either alone — where a duration-based shake would just
-- restart its own timer and lose the first event.
--
-- The offset is quadratic in trauma (trauma^2). Linear reads as a constant
-- rattle that stops abruptly; squaring makes a big hit punch and then settle
-- quickly, which is the whole point of the model.
--
-- The displacement uses SUMMED SINES, not math.random. Rule 3 forbids
-- reading randomness in here, and an injected rng would make the shake
-- frame-rate-shaped noise rather than a smooth wobble. Sines of unrelated
-- frequencies look random enough at this amplitude and are exactly
-- reproducible for a given time value, which is what lets this be tested at
-- all. Same reasoning as package_physics' sinusoidal shake.

local M = {}

local DEFAULT_DECAY = 1.8        -- trauma per second
local DEFAULT_MAX_OFFSET = 6     -- pixels at full trauma
local DEFAULT_FREQUENCY = 28     -- oscillations per second

function M.new()
	return { trauma = 0 }
end

local function clamp01(value)
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

-- Events add trauma; it saturates at 1 so a pile-up of hits cannot produce
-- an offset far off screen.
function M.add(state, amount)
	return { trauma = clamp01(state.trauma + (amount or 0)) }
end

function M.update(state, dt, config)
	config = config or {}
	local decay = config.decay or DEFAULT_DECAY
	return { trauma = clamp01(state.trauma - decay * dt) }
end

-- The displacement to apply this frame. Returns 0, 0 once trauma is spent,
-- so a caller can apply it unconditionally.
function M.offset(state, time, config)
	config = config or {}
	local max_offset = config.max_offset or DEFAULT_MAX_OFFSET
	local frequency = config.frequency or DEFAULT_FREQUENCY

	local magnitude = state.trauma * state.trauma * max_offset
	if magnitude == 0 then
		return 0, 0
	end
	-- Two incommensurable frequencies per axis, and different ones per axis,
	-- so x and y never trace a straight diagonal the way a single shared
	-- sine would.
	local x = math.sin(time * frequency) * 0.7
		+ math.sin(time * frequency * 1.7 + 1.3) * 0.3
	local y = math.sin(time * frequency * 1.3 + 2.1) * 0.7
		+ math.sin(time * frequency * 2.3) * 0.3
	return x * magnitude, y * magnitude
end

function M.is_active(state)
	return state.trauma > 0
end

return M
