-- User settings (PRD 6.1's Opções: "Volume Master, Música, SFX, Tela Cheia,
-- Controles").
--
-- Pure Lua, no Defold API calls (rule 1): this owns what a setting is and
-- what values are legal, never how it reaches a sound mixer or a window.
-- State in, new state out (rule 2).
--
-- Same shape as core/save.lua on purpose, including sanitize(): a settings
-- file is written to disk and read back, so it is subject to exactly the
-- same "absent, truncated, hand-edited, older build" problem, and must
-- never be able to crash the game on boot.

local M = {}

M.VERSION = 1

-- The three gains the PRD names. Kept as an ordered list so the options
-- screen renders them without hardcoding an order that could drift from
-- this table.
M.VOLUMES = { "master", "music", "sfx" }

local DEFAULT_VOLUME = 0.8

function M.new()
	return {
		version = M.VERSION,
		master = DEFAULT_VOLUME,
		music = DEFAULT_VOLUME,
		sfx = DEFAULT_VOLUME,
		fullscreen = false,
	}
end

local function copy(state)
	return {
		version = state.version,
		master = state.master,
		music = state.music,
		sfx = state.sfx,
		fullscreen = state.fullscreen,
	}
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

-- Nudges a volume by `delta`, clamped. Stepping rather than setting an
-- absolute value because the options screen is keyboard-driven (left/right
-- on a row), and clamping here means no caller can ever store a gain
-- outside 0..1 for the mixer to choke on.
function M.adjust_volume(state, kind, delta)
	local new_state = copy(state)
	new_state[kind] = clamp01((new_state[kind] or DEFAULT_VOLUME) + delta)
	return new_state
end

function M.toggle_fullscreen(state)
	local new_state = copy(state)
	new_state.fullscreen = not new_state.fullscreen
	return new_state
end

-- The gain a given channel should actually play at. Music and SFX are
-- scaled BY master rather than being independent of it, which is what makes
-- a master slider mean anything — otherwise pulling master to zero would
-- leave both channels audible.
function M.effective_gain(state, kind)
	if kind == "master" then
		return clamp01(state.master)
	end
	return clamp01(state.master) * clamp01(state[kind] or DEFAULT_VOLUME)
end

-- See core/save.lua's sanitize for the reasoning; this is the same contract
-- for the same reason. Never errors, never trusts a field.
function M.sanitize(raw)
	local state = M.new()
	if type(raw) ~= "table" then
		return state
	end
	for _, kind in ipairs(M.VOLUMES) do
		local value = raw[kind]
		if type(value) == "number" and value == value then -- rejects NaN
			state[kind] = clamp01(value)
		end
	end
	if type(raw.fullscreen) == "boolean" then
		state.fullscreen = raw.fullscreen
	end
	return state
end

return M
