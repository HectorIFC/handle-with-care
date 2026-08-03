-- Pure external-force ("knockback") tracking for the player: an impulse
-- applied by an outside source (Panic's random impulses, PRD 4.6 — "aplica
-- porcentagem das forças no personagem") that displaces the player
-- temporarily, decaying independently of the player's own input-driven
-- movement. No Defold API calls here — see main/player/player.script.

local M = {}

local DEFAULT_DAMPING = 0.85

function M.new()
	return { velocity_x = 0, velocity_y = 0 }
end

function M.apply(state, force_x, force_y)
	return {
		velocity_x = state.velocity_x + force_x,
		velocity_y = state.velocity_y + force_y,
	}
end

function M.decay(state, config)
	config = config or {}
	local damping = config.damping or DEFAULT_DAMPING
	return {
		velocity_x = state.velocity_x * damping,
		velocity_y = state.velocity_y * damping,
	}
end

return M
