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

local input_bindings = require "main.core.input_bindings"

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
		bindings = input_bindings.new(),
	}
end

local function copy(state)
	return {
		version = state.version,
		master = state.master,
		music = state.music,
		sfx = state.sfx,
		fullscreen = state.fullscreen,
		-- Shared by reference on purpose: input_bindings is itself a
		-- state-in/new-state-out module (rule 2), so a rebind produces a
		-- fresh table rather than mutating this one. Deep-copying here
		-- would just make every volume nudge allocate the bindings again.
		bindings = state.bindings,
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

-- Rebinds a gameplay action, delegating every rule about what is legal to
-- input_bindings — this module only owns that bindings live in the settings
-- file alongside the volumes. Returns new_state, nil on success or
-- state, message on rejection, passing the module's own wording through so
-- the Controls screen and the rule that rejected it cannot disagree.
function M.rebind(state, action, key_action)
	local new_bindings, err = input_bindings.rebind(state.bindings, action, key_action)
	if err then
		return state, err
	end
	local new_state = copy(state)
	new_state.bindings = new_bindings
	return new_state, nil
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
	-- input_bindings.sanitize never errors and always returns a playable
	-- set, so an absent or corrupt `bindings` degrades to the defaults the
	-- same way an absent volume does.
	state.bindings = input_bindings.sanitize(raw.bindings)
	return state
end

return M
