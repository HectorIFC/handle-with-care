-- Save data and level progression (PRD 6.2: "Completar uma fase desbloqueia
-- a próxima", "Save automático local"; PRD 9.4: LocalStorage on Web, a local
-- file on Steam).
--
-- Pure Lua, no Defold API calls (rule 1): this module owns *what* the save
-- contains and how progression advances, never how it reaches a disk. The
-- adapter (main/ui/save_adapter.script) is what calls sys.save/sys.load, and
-- swapping that for a Steam file path or a localStorage shim later must not
-- require touching anything here.
--
-- State is passed in and a new state is returned (rule 2) — nothing is held
-- as a module upvalue, since Defold's require() caches this table and every
-- caller would otherwise share one mutable save.
--
-- No clock is read here (rule 3): completion times arrive as a parameter.

local M = {}

-- Bumped whenever the shape of a saved table changes incompatibly, so
-- sanitize() can tell "written by an older build" from "corrupt".
M.VERSION = 1

-- PRD section 10 ships 10 levels. Callers pass their own count so this
-- module never has to be edited when that changes; this is only the
-- fallback for callers that don't care.
M.DEFAULT_TOTAL_LEVELS = 10

function M.new(total_levels)
	return {
		version = M.VERSION,
		total_levels = total_levels or M.DEFAULT_TOTAL_LEVELS,
		-- Highest level the player may enter. Level 1 is always playable,
		-- which is also what makes a fresh save and a wiped save identical.
		unlocked = 1,
		completed = {},
		best_times = {},
		attempts = {},
	}
end

function M.is_unlocked(state, level)
	return level >= 1 and level <= state.unlocked
end

function M.is_completed(state, level)
	return state.completed[level] == true
end

-- True once every level has been completed (PRD 6.2's "após zerar as 10
-- fases"). Deliberately checks `completed`, not `unlocked`: finishing the
-- last level can't unlock an eleventh, so `unlocked` alone can never
-- distinguish "on the final level" from "finished the game".
function M.all_complete(state)
	for level = 1, state.total_levels do
		if not state.completed[level] then
			return false
		end
	end
	return true
end

-- Should the menu offer "Continuar"? (PRD 6.1: "só aparece se existir
-- save".) Any progress at all counts — an attempt on level 1 is progress
-- the player would be annoyed to silently lose, even with nothing completed.
function M.has_progress(state)
	if state.unlocked > 1 then
		return true
	end
	for _ in pairs(state.attempts) do
		return true
	end
	return false
end

local function copy(state)
	local new_state = {
		version = state.version,
		total_levels = state.total_levels,
		unlocked = state.unlocked,
		completed = {},
		best_times = {},
		attempts = {},
	}
	for k, v in pairs(state.completed) do new_state.completed[k] = v end
	for k, v in pairs(state.best_times) do new_state.best_times[k] = v end
	for k, v in pairs(state.attempts) do new_state.attempts[k] = v end
	return new_state
end

-- PRD 6.2's result screen shows an attempt count, so every start of a level
-- is recorded — including restarts, which is the number that makes the
-- "tentativas" line meaningful.
function M.record_attempt(state, level)
	local new_state = copy(state)
	new_state.attempts[level] = (new_state.attempts[level] or 0) + 1
	return new_state
end

-- PRD 6.2: completing a level unlocks the next one. `time` is the attempt's
-- duration, supplied by the caller (rule 3) and kept only if it beats the
-- stored best, so replaying a level can improve a record but never lose one.
function M.complete_level(state, level, time)
	local new_state = copy(state)
	new_state.completed[level] = true

	-- Clamp to the last level rather than skipping the update entirely when
	-- there is no next one: completing the final level must still leave it
	-- unlocked (the player is standing on it), and an earlier version that
	-- only handled `level + 1 <= total_levels` left `unlocked` stale there.
	-- Written as max(current, min(level+1, total)) so it also never moves
	-- backwards when an already-completed early level is replayed — and so
	-- it derives `unlocked` by exactly the same rule sanitize() does, which
	-- is where the two silently disagreed before.
	local next_unlocked = math.min(level + 1, new_state.total_levels)
	if next_unlocked > new_state.unlocked then
		new_state.unlocked = next_unlocked
	end

	if time then
		local best = new_state.best_times[level]
		if not best or time < best then
			new_state.best_times[level] = time
		end
	end

	return new_state
end

-- PRD 6.1's "Novo Jogo (apaga save e começa da Fase 1)".
function M.wipe(state)
	return M.new(state and state.total_levels or M.DEFAULT_TOTAL_LEVELS)
end

local function positive_int_keys_only(source, validator)
	local out = {}
	if type(source) ~= "table" then
		return out
	end
	for k, v in pairs(source) do
		if type(k) == "number" and k >= 1 and k == math.floor(k) and validator(v) then
			out[k] = v
		end
	end
	return out
end

-- Turns whatever came back from disk into a state this module can safely
-- operate on. A save file is the one input this game reads that it did not
-- write this run — it can be absent, truncated, hand-edited, or written by
-- an older build — so this never errors and never trusts a field: anything
-- missing or malformed falls back to its fresh-save value. Returning a
-- usable state rather than nil is deliberate; a player with a corrupt save
-- should get a playable game, not a crash on boot.
function M.sanitize(raw, total_levels)
	local fresh = M.new(total_levels)
	if type(raw) ~= "table" then
		return fresh
	end

	local state = M.new(total_levels)

	state.completed = positive_int_keys_only(raw.completed, function(v) return v == true end)
	state.best_times = positive_int_keys_only(raw.best_times, function(v)
		return type(v) == "number" and v >= 0
	end)
	state.attempts = positive_int_keys_only(raw.attempts, function(v)
		return type(v) == "number" and v >= 0 and v == math.floor(v)
	end)

	-- Clamped rather than trusted: a save claiming level 99 is unlocked
	-- would otherwise let the menu offer a level that doesn't exist.
	if type(raw.unlocked) == "number" and raw.unlocked >= 1 then
		state.unlocked = math.min(math.floor(raw.unlocked), state.total_levels)
	end

	-- A completed level implies the next one is unlocked, even if the
	-- `unlocked` field itself was lost or rolled back — the completion
	-- records are the more trustworthy signal, since they are only ever
	-- added to.
	for level in pairs(state.completed) do
		local next_level = math.min(level + 1, state.total_levels)
		if next_level > state.unlocked then
			state.unlocked = next_level
		end
	end

	return state
end

return M
