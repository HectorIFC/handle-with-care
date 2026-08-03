-- Explosive detonation timer (PRD 4.4/4.7/4.8). Deciding WHEN the package
-- enters Explosive is not this module's job — that's package_state_machine
-- (stress crossing explosive_threshold) or an explicit set_state call from a
-- later phase's own trigger (e.g. Hot Potato's cyclic heat-up, phase 14).
-- This module only owns the countdown and the moment of detonation, once
-- told to start — the same split of responsibility panic_impulse.lua has
-- for Panic. Rule 6: both entry paths reach the exact same start()/update()
-- pair, so there is nothing "stress-specific" here to bolt a second trigger
-- onto later. No Defold API calls here; dt is injected (rule 3).

local M = {}

local DEFAULT_EXPLOSIVE_TIME = 1.5

function M.new()
	return { timer = 0, active = false }
end

-- Starts (or restarts) the countdown at explosive_time. Called once by the
-- adapter, on the frame Explosive is entered — regardless of which trigger
-- caused it. `active` (not the timer's sign) is what update()/the adapter
-- use to tell "counting down" apart from "never started" and "just
-- detonated" — both of the latter also leave timer at 0, and a
-- config.explosive_time of exactly 0 would otherwise be indistinguishable
-- from idle, leaving the package stuck re-arming every frame without ever
-- reporting detonated.
function M.start(config)
	config = config or {}
	return { timer = config.explosive_time or DEFAULT_EXPLOSIVE_TIME, active = true }
end

-- state: { timer, active }
-- dt: elapsed seconds this frame
-- returns: new_state, detonated (true only on the exact frame the timer
--   crosses to zero — false before that frame and on every frame after,
--   including a config.explosive_time <= 0, which detonates immediately)
function M.update(state, dt)
	if not state.active then
		return state, false
	end

	local new_timer = state.timer - dt
	if new_timer <= 0 then
		return { timer = 0, active = false }, true
	end
	return { timer = new_timer, active = true }, false
end

-- 0 (just started) to 1 (about to detonate) — drives the accelerating
-- blink/beep/shake called for by PRD 4.4. Only meaningful while active;
-- the caller is expected to know that from package_state_machine's own
-- current_state, the same way panic_impulse's force fields are only read
-- while Panic is active.
function M.progress(state, config)
	config = config or {}
	local total = config.explosive_time or DEFAULT_EXPLOSIVE_TIME
	if total <= 0 then
		return 1
	end

	local ratio = 1 - (state.timer / total)
	if ratio < 0 then
		return 0
	elseif ratio > 1 then
		return 1
	end
	return ratio
end

return M
