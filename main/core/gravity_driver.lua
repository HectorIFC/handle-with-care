-- Per-level gravity driver (PRD section 10, level 6 "Gravity Moods": "a
-- gravidade do pacote muda sozinha", with the second layer being "mudança
-- no meio do pulo + atraso proposital").
--
-- Pure Lua, no Defold API calls (rule 1). State in, new state out (rule 2).
-- dt injected, never a clock read; the mood order is driven by an injected
-- rng so a test can pin it (rule 3).
--
-- Deliberately NOT built on heavy_cycle.lua even though both are timers.
-- That one flips between exactly two states on two fixed durations; this
-- picks the NEXT mood from a set and — the whole point of the level —
-- telegraphs the change before it lands. Forcing both into one module would
-- have made each harder to read than two small ones.

local M = {}

-- Multipliers applied to the player's own gravity. Named so a level reads
-- as moods rather than magic numbers.
M.MOODS = {
	{ name = "normal", multiplier = 1.0 },
	{ name = "floaty", multiplier = 0.45 },
	{ name = "heavy", multiplier = 1.8 },
}

local DEFAULT_MOOD_DURATION = 4.0
-- PRD's "atraso proposital": the mood is announced, then actually lands a
-- beat later. Without this the change is an unfair death rather than a
-- readable threat (PRD section 11: deaths must be legible in under 2s).
local DEFAULT_TELEGRAPH = 1.0

function M.new()
	return { index = 1, elapsed = 0, pending = nil }
end

function M.multiplier(state)
	return M.MOODS[state.index].multiplier
end

function M.name(state)
	return M.MOODS[state.index].name
end

-- True while a change has been announced but not yet applied, so the
-- adapter can flash a warning.
function M.telegraphing(state)
	return state.pending ~= nil
end

-- returns: new_state, changed
--   `changed` is true only on the exact frame a new mood takes effect.
function M.update(state, dt, rng, config)
	config = config or {}
	local duration = config.mood_duration or DEFAULT_MOOD_DURATION
	local telegraph = config.telegraph or DEFAULT_TELEGRAPH
	local elapsed = state.elapsed + dt

	if state.pending then
		if elapsed < telegraph then
			return { index = state.index, elapsed = elapsed, pending = state.pending }, false
		end
		-- Overshoot carried forward, same as heavy_cycle, so a long frame
		-- cannot make every later mood run late.
		return { index = state.pending, elapsed = elapsed - telegraph, pending = nil }, true
	end

	if elapsed < duration then
		return { index = state.index, elapsed = elapsed, pending = nil }, false
	end

	-- Never announce the mood already running: "it changed to the same
	-- thing" is indistinguishable from a bug, and wastes a telegraph.
	local choice = state.index
	if #M.MOODS > 1 then
		local offset = rng(1, #M.MOODS - 1)
		choice = ((state.index - 1 + offset) % #M.MOODS) + 1
	end
	return { index = state.index, elapsed = elapsed - duration, pending = choice }, false
end

return M
