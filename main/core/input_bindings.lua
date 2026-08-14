-- Controls remapping (PRD 6.1's "Controles"). Pure Lua, no Defold API calls
-- (rule 1): this owns which physical key means which gameplay action and
-- what a legal binding is, never how a key press reaches the engine.
-- State in, new state out (rule 2).
--
-- WHY THIS LAYER EXISTS AT ALL: Defold compiles input/game.input_binding
-- into the build and offers no runtime API to change it, so remapping cannot
-- happen where the key is registered. It has to happen where the action is
-- CONSUMED. The binding file therefore names actions after physical keys
-- ("key_a", "key_left"), and this module translates a physical key into a
-- gameplay intent using whatever the player configured.
--
-- Only gameplay movement is remappable. Restart, pause and menu navigation
-- are fixed, for two reasons: restart is broadcast to every restorable
-- object in a level (nine scripts handle it), so remapping it would mean
-- teaching all nine about settings for one key; and a player who remaps menu
-- confirm to a key they cannot press is locked out of the screen that would
-- let them fix it.
--
-- Only R, Escape and Enter keep semantic action names in the binding file.
-- Everything else is a raw key with exactly ONE action, and the menus
-- translate through M.MENU below — see the comment there for the bug that
-- forced this.

local M = {}

M.VERSION = 1

-- The remappable actions, in the order the Controls screen lists them.
M.ACTIONS = { "move_left", "move_right", "jump" }

-- Every physical key the binding file exposes as a raw action, in the order
-- a UI would list them, mapped to the label shown to the player.
--
-- R is deliberately absent: it stays reserved for restart. Escape and Enter
-- are absent too — they are consumed by the pause/menu layer before a level
-- ever sees them, so binding a movement action to one would produce a key
-- that silently does nothing.
M.KEY_LABELS = {
	key_a = "A", key_b = "B", key_c = "C", key_d = "D", key_e = "E",
	key_f = "F", key_g = "G", key_h = "H", key_i = "I", key_j = "J",
	key_k = "K", key_l = "L", key_m = "M", key_n = "N", key_o = "O",
	key_p = "P", key_q = "Q", key_s = "S", key_t = "T", key_u = "U",
	key_v = "V", key_w = "W", key_x = "X", key_y = "Y", key_z = "Z",
	key_left = "Left", key_right = "Right", key_up = "Up", key_down = "Down",
	key_space = "Space",
}

-- The same keys in a fixed order. KEY_LABELS is a hash, and Lua's `pairs`
-- order is unspecified, so anything that has to pick "some key" must walk
-- this instead — otherwise the same corrupt settings file could sanitize to
-- different bindings on different runs.
M.KEYS = {
	"key_a", "key_b", "key_c", "key_d", "key_e", "key_f", "key_g", "key_h",
	"key_i", "key_j", "key_k", "key_l", "key_m", "key_n", "key_o", "key_p",
	"key_q", "key_s", "key_t", "key_u", "key_v", "key_w", "key_x", "key_y",
	"key_z", "key_left", "key_right", "key_up", "key_down", "key_space",
}

-- How the MENUS read the raw key actions. Fixed, never remappable, and
-- deliberately mapped onto the logical names the screen adapter already
-- handles ("menu_up", "move_left", "confirm") so translating a key changes
-- nothing downstream — including the test seam, which posts those logical
-- names directly.
--
-- This exists because the binding file used to give seven keys two actions
-- each (KEY_LEFT raised both "key_left" and "move_left"). Which one the
-- engine delivered was then an implementation detail, and the arrow keys
-- moved the menu cursor but not the player. One action per key, translated
-- here, removes the ambiguity.
M.MENU = {
	key_up = "menu_up",
	key_w = "menu_up",
	key_down = "menu_down",
	key_s = "menu_down",
	key_left = "move_left",
	key_a = "move_left",
	key_right = "move_right",
	key_d = "move_right",
	key_space = "confirm",
}

M.DEFAULTS = {
	move_left = { "key_a", "key_left" },
	move_right = { "key_d", "key_right" },
	jump = { "key_w", "key_up", "key_space" },
}

local function copy_keys(keys)
	local out = {}
	for i = 1, #keys do
		out[i] = keys[i]
	end
	return out
end

function M.new()
	local state = { version = M.VERSION }
	for _, action in ipairs(M.ACTIONS) do
		state[action] = copy_keys(M.DEFAULTS[action])
	end
	return state
end

local function copy(state)
	local out = { version = state.version or M.VERSION }
	for _, action in ipairs(M.ACTIONS) do
		out[action] = copy_keys(state[action] or M.DEFAULTS[action])
	end
	return out
end

-- Which gameplay action a physical key press means, or nil if that key is
-- not bound to anything. Called on every input event, so it walks the
-- bindings rather than building a reverse index that would have to be kept
-- in sync with every rebind.
function M.resolve(bindings, key_action)
	if type(key_action) ~= "string" then
		return nil
	end
	for _, action in ipairs(M.ACTIONS) do
		local keys = bindings[action]
		if keys then
			for i = 1, #keys do
				if keys[i] == key_action then
					return action
				end
			end
		end
	end
	return nil
end

-- Which action currently owns a key, used to explain a rejected rebind.
function M.owner_of(bindings, key_action)
	return M.resolve(bindings, key_action)
end

-- Binds `action` to exactly `key_action`, replacing whatever it had.
--
-- Replacing rather than appending is what makes an action impossible to
-- leave unbound: every rebind ends with exactly one key, so "no key does
-- this any more" is unreachable by construction rather than by a check that
-- could be missed. The cost is that the defaults' alternates (arrows as well
-- as WASD) are dropped the first time a player remaps that action, which is
-- what a player asking to rebind a key expects.
--
-- Returns new_bindings, nil on success or bindings, message on rejection.
function M.rebind(bindings, action, key_action)
	if not M.KEY_LABELS[key_action] then
		return bindings, "that key cannot be bound"
	end
	local known = false
	for _, candidate in ipairs(M.ACTIONS) do
		if candidate == action then
			known = true
		end
	end
	if not known then
		return bindings, "unknown action"
	end
	local owner = M.resolve(bindings, key_action)
	if owner and owner ~= action then
		return bindings, M.KEY_LABELS[key_action] .. " is already " .. M.describe_action(owner)
	end
	local new_state = copy(bindings)
	new_state[action] = { key_action }
	return new_state, nil
end

-- Display copy. Kept here rather than in the adapter so the Controls screen
-- and a rejection message can never disagree about what an action is called.
local ACTION_LABELS = {
	move_left = "Move Left",
	move_right = "Move Right",
	jump = "Jump",
}

function M.describe_action(action)
	return ACTION_LABELS[action] or action
end

-- The keys bound to an action, as one readable string ("A / Left").
function M.describe_keys(bindings, action)
	local keys = bindings[action] or {}
	local parts = {}
	for i = 1, #keys do
		parts[i] = M.KEY_LABELS[keys[i]] or keys[i]
	end
	if #parts == 0 then
		return "unbound"
	end
	return table.concat(parts, " / ")
end

-- See core/save.lua and core/settings.lua's sanitize for the reasoning; this
-- is the same contract for the same reason — the bindings are written to
-- disk and read back, so they can be absent, truncated, hand-edited or
-- written by an older build, and must never crash the game on boot.
--
-- Beyond rejecting junk, this enforces the two invariants rebind() enforces:
-- an action never ends up with zero keys, and no key is claimed by two
-- actions (first action listed wins, later duplicates are dropped). A file
-- that violated either would otherwise produce a game that is unplayable in
-- a way the player cannot diagnose.
function M.sanitize(raw)
	local state = { version = M.VERSION }
	local claimed = {}
	if type(raw) ~= "table" then
		return M.new()
	end
	for _, action in ipairs(M.ACTIONS) do
		local keys = {}
		local candidates = raw[action]
		if type(candidates) == "table" then
			for i = 1, #candidates do
				local key = candidates[i]
				if type(key) == "string" and M.KEY_LABELS[key] and not claimed[key] then
					claimed[key] = true
					keys[#keys + 1] = key
				end
			end
		end
		if #keys == 0 then
			-- Fall back to this action's defaults, minus anything an
			-- earlier action already took, so a partially-corrupt file
			-- degrades to something playable instead of to a conflict.
			for _, key in ipairs(M.DEFAULTS[action]) do
				if not claimed[key] then
					claimed[key] = true
					keys[#keys + 1] = key
				end
			end
		end
		if #keys == 0 then
			-- Every default was already taken — reachable with a file that
			-- binds one action to another's defaults. Grab the first key
			-- nobody owns, walking M.KEYS so the result is deterministic.
			-- An arbitrary key is a poor binding but a playable one; zero
			-- keys is an action the player cannot perform at all, with no
			-- way to tell why.
			for _, key in ipairs(M.KEYS) do
				if not claimed[key] then
					claimed[key] = true
					keys[#keys + 1] = key
					break
				end
			end
		end
		state[action] = keys
	end
	return state
end

return M
